"""Swappable ASR backends. Mock never fabricates a caption."""

import os
from dataclasses import dataclass
from functools import lru_cache
from typing import Literal, Protocol


@dataclass(frozen=True)
class ASRPrediction:
    text: str
    status: Literal["ok", "unavailable", "busy", "error"]
    model_version: str


class ASRBackend(Protocol):
    model_version: str

    async def transcribe(self, audio: bytes) -> ASRPrediction:
        """Accept validated 16 kHz mono PCM16 LE bytes, in memory only."""
        ...


class MockASRBackend:
    model_version = "asr-mock-v1"

    async def transcribe(self, audio: bytes) -> ASRPrediction:
        return ASRPrediction("", "unavailable", self.model_version)


def create_asr_backend() -> ASRBackend:
    name = os.getenv("ASR_BACKEND", "mock").strip().lower()
    if name == "mock":
        return MockASRBackend()
    if name == "mlx":
        return _mlx_backend(os.getenv("ASR_MODEL_PATH", ""), os.getenv("ASR_MODEL_REVISION", ""))
    if name == "deepgram":
        from app.deepgram_asr import DeepgramASRBackend

        return DeepgramASRBackend()
    raise ValueError("ASR_BACKEND must be mock, mlx or deepgram")


# Real backends cost compute or money, so they require the paired device's bearer token.
AUTHENTICATED_BACKENDS = {"mlx", "deepgram"}


def asr_requires_pairing() -> bool:
    return os.getenv("ASR_BACKEND", "").strip().lower() in AUTHENTICATED_BACKENDS


@lru_cache(maxsize=1)
def _mlx_backend(path: str, revision: str) -> ASRBackend:
    # create_app may run twice through the development launcher. Keep one worker
    # and MLX model cache per process; do not create competing Metal contexts.
    from app.mlx_asr import MLXASRBackend

    return MLXASRBackend()
