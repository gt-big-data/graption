"""ASR protocol, fallback signals, validation and payload privacy with fake inference."""

import base64
import json
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator, FormatChecker
from starlette.websockets import WebSocketDisconnect

from app.asr import ASRPrediction, MockASRBackend, create_asr_backend
from app.main import create_app

SCHEMA = json.loads((Path(__file__).parents[2] / "schemas/events.schema.json").read_text())
VALIDATOR = Draft202012Validator(SCHEMA, format_checker=FormatChecker())


def request():
    return {
        "type": "asr_request",
        "session_id": "asr-test",
        "schema_version": "1.3",
        "caption_id": str(uuid4()),
        "t_start": 1.0,
        "t_end": 1.1,
        "sample_rate": 16000,
        "audio_b64": base64.b64encode(b"\0\0" * 1600).decode(),
    }


@pytest.fixture
def app(monkeypatch, tmp_path):
    monkeypatch.setenv("ASR_BACKEND", "mock")
    monkeypatch.setenv("TONE_BACKEND", "mock")
    monkeypatch.setenv("DEPLOY_MODE", "local")
    monkeypatch.setenv("TONE_LOG_DIR", str(tmp_path))
    monkeypatch.delenv("ASR_TOKEN", raising=False)
    return create_app(verbose=True)


def test_mock_explicitly_requests_fallback(app):
    assert isinstance(create_asr_backend(), MockASRBackend)
    with TestClient(app) as client, client.websocket_connect("/ws/asr?session_id=asr-test") as ws:
        for _ in range(2):
            item = request()
            VALIDATOR.validate(item)
            ws.send_json(item)
            result = ws.receive_json()
            VALIDATOR.validate(result)
            assert result["caption_id"] == item["caption_id"]
            assert result["status"] == "unavailable"
            assert result["text"] == ""


def test_real_result_keeps_phone_identity_times_and_never_persists_audio(app, tmp_path, caplog):
    class Backend:
        model_version = "test-asr-v1"

        async def transcribe(self, audio):
            assert isinstance(audio, bytes) and len(audio) == 3200
            return ASRPrediction("private-transcript", "ok", self.model_version)

    app.state.asr_backend = Backend()
    with TestClient(app) as client, client.websocket_connect("/ws/asr?session_id=asr-test") as ws:
        item = request()
        ws.send_json(item)
        result = ws.receive_json()
        VALIDATOR.validate(result)
        assert result["text"] == "private-transcript"
        for key in ["caption_id", "t_start", "t_end", "session_id"]:
            assert result[key] == item[key]
        assert result["latency_ms"]["recv_to_send"] >= 0
    content = "".join(p.read_text() for p in tmp_path.iterdir()) + caplog.text
    assert item["audio_b64"] not in content
    assert "private-transcript" not in content
    assert all(p.suffix == ".jsonl" for p in tmp_path.iterdir())


@pytest.mark.parametrize(
    "changes",
    [
        {"schema_version": "1.1"},
        {"sample_rate": 48000},
        {"session_id": "wrong"},
        {"audio_b64": "invalid!"},
        {"audio_b64": "AA=="},
        {"audio_b64": ""},
        {"t_start": 2.0},
        {"t_end": 1.2},
        {"t_end": float("inf")},
        {"caption_id": "invalid"},
        {"extra": "private-audio-marker"},
    ],
)
def test_invalid_requests_are_not_echoed_and_connection_recovers(app, changes, caplog):
    with TestClient(app) as client, client.websocket_connect("/ws/asr?session_id=asr-test") as ws:
        ws.send_json({**request(), **changes})
        error = ws.receive_json()
        VALIDATOR.validate(error)
        assert error["type"] == "session_error"
        assert error["request"] == ""
        ws.send_json(request())
        assert ws.receive_json()["status"] == "unavailable"
    assert "private-audio-marker" not in caplog.text


@pytest.mark.parametrize("raw", ["not JSON", "[]", '{"x": NaN}', "null"])
def test_malformed_requests_recover_without_payload_echo(app, raw):
    with TestClient(app) as client, client.websocket_connect("/ws/asr?session_id=asr-test") as ws:
        ws.send_text(raw)
        assert ws.receive_json()["request"] == ""
        ws.send_json(request())
        assert ws.receive_json()["status"] == "unavailable"


@pytest.mark.parametrize("binary,expected", [(True, 1003), (False, 1009)])
def test_binary_and_oversized_frames_close(app, binary, expected):
    with TestClient(app) as client, client.websocket_connect("/ws/asr?session_id=asr-test") as ws:
        if binary:
            ws.send_bytes(b"private")
        else:
            ws.send_text("x" * 450001)
        with pytest.raises(WebSocketDisconnect) as error:
            ws.receive_json()
        assert error.value.code == expected


def test_backend_exception_is_fixed_error_without_payload(app, caplog):
    class Broken:
        model_version = "broken-asr-v1"

        async def transcribe(self, audio):
            raise RuntimeError("private-exception-audio")

    app.state.asr_backend = Broken()
    with TestClient(app) as client, client.websocket_connect("/ws/asr?session_id=asr-test") as ws:
        ws.send_json(request())
        result = ws.receive_json()
        assert result["status"] == "error" and result["text"] == ""
    assert "private-exception-audio" not in caplog.text


def test_authentication(app, monkeypatch):
    monkeypatch.setenv("ASR_TOKEN", "test-secret")
    with TestClient(app) as client:
        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect("/ws/asr?session_id=asr-test"):
                pass
        with client.websocket_connect(
            "/ws/asr?session_id=asr-test", headers={"Authorization": "Bearer test-secret"}
        ) as ws:
            ws.send_json(request())
            assert ws.receive_json()["status"] == "unavailable"


def test_nonlocal_requires_token(app, monkeypatch):
    monkeypatch.setenv("DEPLOY_MODE", "tunnel")
    with TestClient(app) as client, pytest.raises(WebSocketDisconnect):
        with client.websocket_connect("/ws/asr?session_id=asr-test"):
            pass


def test_unknown_backend_rejected(monkeypatch):
    monkeypatch.setenv("ASR_BACKEND", "unknown")
    with pytest.raises(ValueError):
        create_asr_backend()


def test_exact_digital_silence_does_not_invent_text():
    from app.mlx_asr import MLXASRBackend

    np = pytest.importorskip("numpy")
    backend = object.__new__(MLXASRBackend)
    backend._np = np
    backend.model_version = "test-silence-v1"

    def unexpected(*args, **kwargs):
        raise AssertionError("Digital silence must not enter the decoder")

    backend._transcribe = unexpected
    result = backend._infer(b"\0\0" * 16000)
    assert result.text == "" and result.status == "ok"


def test_cancelled_request_keeps_gpu_slot_busy_until_worker_finishes():
    import asyncio
    import threading
    from concurrent.futures import ThreadPoolExecutor

    from app.mlx_asr import MLXASRBackend

    async def exercise():
        backend = object.__new__(MLXASRBackend)
        backend.model_version = "test-concurrency-v1"
        backend._active = None
        backend._executor = ThreadPoolExecutor(max_workers=1)
        started, release = threading.Event(), threading.Event()

        def infer(audio):
            started.set()
            assert release.wait(timeout=5)
            return ASRPrediction("fixture", "ok", backend.model_version)

        backend._infer = infer
        first = asyncio.create_task(backend.transcribe(b"\0\0"))
        try:
            for _ in range(1000):
                if started.is_set():
                    break
                await asyncio.sleep(0.001)
            assert started.is_set()
            first.cancel()
            with pytest.raises(asyncio.CancelledError):
                await first
            assert (await backend.transcribe(b"\0\0")).status == "busy"
            release.set()
            await backend._active
            assert (await backend.transcribe(b"\0\0")).text == "fixture"
        finally:
            release.set()
            backend._executor.shutdown(wait=True)

    asyncio.run(exercise())


@pytest.mark.parametrize(
    ("variant", "dimensions"),
    [
        ("base.en", (80, 512, 6, 512, 6, 51864)),
        ("small.en", (80, 768, 12, 768, 12, 51864)),
        ("large-v3-turbo", (128, 1280, 32, 1280, 4, 51866)),
    ],
)
def test_checkpoint_version_matches_architecture(tmp_path, monkeypatch, variant, dimensions):
    import json

    import app.mlx_asr as mlx_asr

    keys = ("n_mels", "n_audio_state", "n_audio_layer", "n_text_state", "n_text_layer", "n_vocab")
    (tmp_path / "config.json").write_text(json.dumps(dict(zip(keys, dimensions, strict=True))))
    (tmp_path / "weights.npz").write_bytes(b"fixture-only")
    monkeypatch.setenv("ASR_MODEL_PATH", str(tmp_path))
    monkeypatch.setenv("ASR_MODEL_REVISION", "a" * 40)
    monkeypatch.setattr(mlx_asr, "version", lambda _: "test-runtime")
    # These are model selection/provenance tests, not fake successful inference.
    monkeypatch.setattr(mlx_asr.MLXASRBackend, "_load", lambda _: None)
    backend = mlx_asr.MLXASRBackend()
    try:
        assert backend.model_version == f"mlx-whisper-test-runtime-{variant}@{'a' * 40}"
    finally:
        backend._executor.shutdown(wait=True)


@pytest.mark.parametrize("config", ["not json", "[]", '{"n_vocab": 51865}', '{"quantization": {}}'])
def test_unsupported_or_malformed_checkpoint_cannot_be_mislabeled(tmp_path, config):
    from app.mlx_asr import checkpoint_variant

    (tmp_path / "config.json").write_text(config)
    with pytest.raises(ValueError):
        checkpoint_variant(tmp_path)
