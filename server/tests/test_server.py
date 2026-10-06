"""Exercise the real routes and their shared wire contract."""

import json
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator, FormatChecker
from starlette.websockets import WebSocketDisconnect

from app.main import app

SCHEMA = json.loads(
    (Path(__file__).resolve().parents[2] / "schemas/events.schema.json").read_text()
)
VALIDATOR = Draft202012Validator(SCHEMA, format_checker=FormatChecker())


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("DEPLOY_MODE", "local")
    monkeypatch.delenv("TONE_TOKEN", raising=False)
    with TestClient(app) as client:
        yield client


def tone_request():
    return {
        "type": "tone_request",
        "session_id": "test-session",
        "schema_version": "1.0",
        "caption_id": str(uuid4()),
        "t_start": 1.0,
        "t_end": 1.1,
        "sample_rate": 16000,
        "audio_b64": "AAABAAIA",
    }


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.text == "ok"


def test_session_replies_to_multiple_audio_segments(client, caplog):
    with client.websocket_connect("/ws/session?session_id=test-session") as websocket:
        for _ in range(2):
            request = tone_request()
            VALIDATOR.validate(request)
            websocket.send_json(request)
            response = websocket.receive_json()
            VALIDATOR.validate(response)
            assert response["type"] == "tone_result"
            assert response["caption_id"] == request["caption_id"]
            assert response["session_id"] == request["session_id"]
            assert response["tag"] is None
            assert response["model_version"] == "tone-stub-v1"
            assert set(response["probs"].values()) == {0.0}
            assert response["latency_ms"]["recv_to_send"] >= 0
    assert request["audio_b64"] not in caplog.text


def test_caption_log_does_not_interrupt_tone(client):
    request = tone_request()
    caption_log = {
        "type": "caption_log",
        "session_id": request["session_id"],
        "schema_version": "1.0",
        "tone_tag": None,
        "caption": {
            "type": "caption",
            "session_id": request["session_id"],
            "schema_version": "1.0",
            "caption_id": request["caption_id"],
            "t_start": 1.0,
            "t_end": 1.1,
            "text": "Hello",
            "speaker_id": "unknown",
            "model_versions": {"asr": "mock-asr-v1", "asd": "mock-asd-v1"},
        },
    }
    with client.websocket_connect("/ws/session?session_id=test-session") as websocket:
        websocket.send_json(caption_log)
        websocket.send_json(request)
        assert websocket.receive_json()["caption_id"] == request["caption_id"]


@pytest.mark.parametrize(
    "changes",
    [
        {"session_id": "another-session"},
        {"schema_version": "2.0"},
        {"audio_b64": "invalid base64!"},
        {"audio_b64": "AA=="},
        {"t_end": 0.5},
        {"caption_id": "not-a-uuid"},
        {"type": "unknown"},
    ],
)
def test_invalid_events_close_without_echoing_audio(client, changes):
    with client.websocket_connect("/ws/session?session_id=test-session") as websocket:
        websocket.send_json({**tone_request(), **changes})
        with pytest.raises(WebSocketDisconnect) as error:
            websocket.receive_json()
        assert error.value.code == 1008
        assert error.value.reason == "Invalid session event"


def test_malformed_json_closes_cleanly(client):
    with client.websocket_connect("/ws/session?session_id=test-session") as websocket:
        websocket.send_text("not json")
        with pytest.raises(WebSocketDisconnect) as error:
            websocket.receive_json()
        assert error.value.code == 1008


@pytest.mark.parametrize("authorization", [None, "Bearer wrong-token"])
def test_configured_token_rejects_unauthorized_handshake(client, monkeypatch, authorization):
    monkeypatch.setenv("TONE_TOKEN", "test-token")
    headers = {"Authorization": authorization} if authorization else {}
    with pytest.raises(WebSocketDisconnect) as error:
        with client.websocket_connect("/ws/session?session_id=test-session", headers=headers):
            pass
    assert error.value.code == 1008


def test_authorized_handshake(client, monkeypatch):
    monkeypatch.setenv("TONE_TOKEN", "test-token")
    with client.websocket_connect(
        "/ws/session?session_id=test-session", headers={"Authorization": "Bearer test-token"}
    ) as websocket:
        websocket.send_json(tone_request())
        assert websocket.receive_json()["tag"] is None


@pytest.mark.parametrize("mode", ["tunnel", "cloud"])
def test_nonlocal_mode_requires_token(client, monkeypatch, mode):
    monkeypatch.setenv("DEPLOY_MODE", mode)
    with pytest.raises(WebSocketDisconnect) as error:
        with client.websocket_connect("/ws/session?session_id=test-session"):
            pass
    assert error.value.code == 1008
