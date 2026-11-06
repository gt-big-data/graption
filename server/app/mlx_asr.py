"""Local Apple Silicon inference; never use filenames for incoming audio."""

import asyncio
import json
import os
import re
from concurrent.futures import ThreadPoolExecutor
from importlib.metadata import version
from pathlib import Path

from app.asr import ASRPrediction


def checkpoint_variant(path: Path) -> str:
    """Identify supported architectures before load; never mislabel timing results."""
    try:
        config = json.loads((path / "config.json").read_text())
    except (OSError, ValueError):
        raise ValueError("Local ASR checkpoint config is unreadable") from None
    if not isinstance(config, dict) or config.get("quantization") is not None:
        raise ValueError("Use an unquantized base.en, small.en or large-v3-turbo checkpoint")
    keys = ("n_mels", "n_audio_state", "n_audio_layer", "n_text_state", "n_text_layer", "n_vocab")
    shape = tuple(config.get(key) for key in keys)
    variants = {
        (80, 512, 6, 512, 6, 51864): "base.en",
        (80, 768, 12, 768, 12, 51864): "small.en",
        (128, 1280, 32, 1280, 4, 51866): "large-v3-turbo",
    }
    for expected, name in variants.items():
        if shape == expected:
            return name
    raise ValueError(
        "Unsupported ASR checkpoint architecture; use base.en, small.en or large-v3-turbo"
    )


class MLXASRBackend:
    def __init__(self) -> None:
        # Local checkpoint required: requests must never trigger downloads.
        path = Path(os.environ.get("ASR_MODEL_PATH", "")).expanduser()
        revision = os.environ.get("ASR_MODEL_REVISION", "")
        if not path.is_dir() or not (path / "config.json").is_file():
            raise ValueError("Set ASR_MODEL_PATH to a preprovisioned local checkpoint")
        if not any((path / name).is_file() for name in ("weights.npz", "weights.safetensors")):
            raise ValueError("Local ASR checkpoint weights are missing")
        if not re.fullmatch(r"[a-f0-9]{40}", revision):
            raise ValueError("ASR_MODEL_REVISION must identify the 40-character source commit")
        self._path = str(path.resolve())
        variant = checkpoint_variant(path)
        self.model_version = f"mlx-whisper-{version('mlx-whisper')}-{variant}@{revision}"
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="graption-asr")
        # MLX streams and compiled operations are thread-local. Import, load and
        # inference must use the same dedicated worker, not the event-loop thread.
        try:
            self._executor.submit(self._load).result()
        except Exception:
            self._executor.shutdown(wait=False, cancel_futures=True)
            raise
        self._active: asyncio.Future | None = None

    def _load(self) -> None:
        import mlx.core as mx
        import mlx_whisper
        import numpy as np
        from mlx_whisper.transcribe import ModelHolder

        self._np, self._transcribe = np, mlx_whisper.transcribe
        model = ModelHolder.get_model(self._path, mx.float16)
        mx.eval(model.parameters())
        # Compile/warm the decode path before accepting phone requests. Synthetic
        # silence is not a recognition trial, and its output is discarded.
        self._transcribe(
            np.zeros(16000, dtype=np.float32),
            path_or_hf_repo=self._path,
            language="en",
            task="transcribe",
            verbose=None,
            word_timestamps=False,
            condition_on_previous_text=False,
        )

    async def transcribe(self, audio: bytes) -> ASRPrediction:
        # No unbounded GPU-work queue. A timed-out client cannot free the slot while
        # its non-cancellable model call still runs in the worker thread.
        if self._active is not None and not self._active.done():
            return ASRPrediction("", "busy", self.model_version)
        self._active = asyncio.get_running_loop().run_in_executor(
            self._executor, self._infer, audio
        )
        # Consume background exceptions even if the connection disappears, without
        # allowing asyncio to print exception details that may contain user data.
        self._active.add_done_callback(
            lambda future: None if future.cancelled() else future.exception()
        )
        return await asyncio.shield(self._active)

    def _infer(self, audio: bytes) -> ASRPrediction:
        samples = self._np.frombuffer(audio, dtype="<i2").astype(self._np.float32) / 32768.0
        # Exactly digital silence carries no words. This is not a general VAD
        # or noise detector; imperfect/noisy silence still needs evaluation.
        if not self._np.any(samples):
            return ASRPrediction("", "ok", self.model_version)
        result = self._transcribe(
            samples,
            path_or_hf_repo=self._path,
            language="en",
            task="transcribe",
            verbose=None,
            word_timestamps=False,
            condition_on_previous_text=False,
        )
        text = result["text"].strip()
        return ASRPrediction(text, "ok", self.model_version)
