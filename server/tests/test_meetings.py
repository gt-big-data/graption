"""Durable idempotent text-only meeting sync and dashboard contract."""

import json
from io import BytesIO
from pathlib import Path
from urllib.error import HTTPError
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from jsonschema import Draft202012Validator, FormatChecker

from app import meeting_ai
from app.main import create_app


@pytest.fixture
def client(monkeypatch, tmp_path):
    monkeypatch.setattr(meeting_ai, "ENV_FILE", tmp_path / ".env")
    monkeypatch.setenv("MEETINGS_DB", str(tmp_path / "meetings.sqlite3"))
    monkeypatch.setenv("DEPLOY_MODE", "local")
    monkeypatch.delenv("TONE_TOKEN", raising=False)
    return TestClient(create_app())


def export():
    return {
        "export_version": "1",
        "exported_at": "2026-11-15T12:00:00Z",
        "sessions": [
            {
                "id": str(uuid4()),
                "started_at": "2026-11-15T12:00:00Z",
                "duration": 2,
                "captions": [
                    {
                        "caption_id": str(uuid4()),
                        "text": "Hello",
                        "speaker_id": "unknown",
                        "tone_tag": None,
                        "t_start": 0,
                        "t_end": 2,
                        "model_versions": {"asr": "whisperkit-base.en"},
                    }
                ],
            }
        ],
    }


def test_retry_late_tone_and_restart(client):
    data = export()
    assert client.post("/api/meetings", json=data).status_code == 200
    data["sessions"][0]["captions"][0]["tone_tag"] = "happy"
    data["sessions"][0]["captions"][0]["model_versions"]["tone"] = "tone-v1"
    assert client.post("/api/meetings", json=data).status_code == 200
    reopened = TestClient(create_app()).get("/api/meetings").json()
    assert len(reopened["sessions"]) == 1
    assert reopened["sessions"][0]["captions"][0]["tone_tag"] == "happy"
    schema = json.loads(
        (Path(__file__).resolve().parents[2] / "schemas/session_export.schema.json").read_text()
    )
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(reopened)


def test_reject_audio_and_invalid_timing(client):
    data = export()
    data["sessions"][0]["audio_b64"] = "forbidden"
    assert client.post("/api/meetings", json=data).status_code == 422
    del data["sessions"][0]["audio_b64"]
    data["sessions"][0]["captions"][0]["t_end"] = 3
    assert client.post("/api/meetings", json=data).status_code == 422
    assert client.get("/api/meetings").json()["sessions"] == []


def test_read_and_write_require_token(client, monkeypatch):
    monkeypatch.setenv("TONE_TOKEN", "test-token")
    assert client.post("/api/meetings", json=export()).status_code == 401
    assert client.get("/api/meetings").status_code == 401
    headers = {"Authorization": "Bearer test-token"}
    assert client.post("/api/meetings", json=export(), headers=headers).status_code == 200
    assert client.get("/api/meetings", headers=headers).status_code == 200
    monkeypatch.setenv("DEPLOY_MODE", "cloud")
    monkeypatch.delenv("TONE_TOKEN")
    assert client.get("/api/meetings").status_code == 401


def test_v2_details_and_rename_roundtrip(client):
    data = export()
    data["export_version"] = "2"
    meeting = data["sessions"][0]
    meeting["title"] = "Planning"
    meeting["sound_events"] = [
        {
            "id": str(uuid4()),
            "label": "doorbell",
            "t": 1,
            "confidence": 0.9,
            "model_version": "sound-v1",
        }
    ]
    meeting["captions"][0]["tone_probs"] = {"happy": 0.4, "neutral": 0.6}
    meeting["captions"][0]["tone_scores"] = {"arousal": 0.3, "valence": 0.6, "dominance": 0.4}
    assert client.post("/api/meetings", json=data).status_code == 200
    meeting["title"] = "Renamed"
    assert client.post("/api/meetings", json=data).status_code == 200
    result = client.get("/api/meetings").json()
    assert result["export_version"] == "2"
    assert result["sessions"][0] == meeting
    schema = json.loads(
        (Path(__file__).resolve().parents[2] / "schemas/session_export.schema.json").read_text()
    )
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(result)


def test_deletion_survives_stale_retry_and_redacts_database(client):
    import copy
    import os
    import sqlite3

    data = export()
    assert client.post("/api/meetings", json=data).status_code == 200
    deletion = copy.deepcopy(data)
    deletion["export_version"] = "2"
    deletion["sessions"][0]["deleted_at"] = "2026-11-16T12:00:00Z"
    assert client.post("/api/meetings", json=deletion).status_code == 200
    assert client.post("/api/meetings", json=data).status_code == 200
    assert client.get("/api/meetings").json()["sessions"] == []
    connection = sqlite3.connect(os.environ["MEETINGS_DB"])
    try:
        stored = json.loads(connection.execute("SELECT body FROM meetings").fetchone()[0])
    finally:
        connection.close()
    assert stored["deleted_at"]
    assert stored["captions"] == []
    assert stored["sound_events"] == []
    assert "Hello" not in json.dumps(stored)


def test_invalid_probabilities_and_sound_times_are_rejected(client):
    data = export()
    data["export_version"] = "2"
    data["sessions"][0]["captions"][0]["tone_probs"] = {"happy": 1.1}
    assert client.post("/api/meetings", json=data).status_code == 422
    del data["sessions"][0]["captions"][0]["tone_probs"]
    data["sessions"][0]["sound_events"] = [
        {
            "id": str(uuid4()),
            "label": "alarm",
            "t": 3,
            "confidence": 0.8,
            "model_version": "sound-v1",
        }
    ]
    assert client.post("/api/meetings", json=data).status_code == 422


def test_meeting_ai_uses_only_selected_transcript(client, monkeypatch):
    data = export()
    meeting = data["sessions"][0]
    other = export()["sessions"][0]
    other["captions"][0]["text"] = "Another meeting"
    data["sessions"].append(other)
    assert client.post("/api/meetings", json=data).status_code == 200
    endpoint = f"/api/meetings/{meeting['id']}/ai"
    monkeypatch.setenv("OPENROUTER_API_KEY", "stale-shell-key")
    monkeypatch.setenv("OPENROUTER_MODEL", "stale/shell-model")
    meeting_ai.ENV_FILE.write_text(
        'OPENROUTER_API_KEY="mock-openrouter-key"\nOPENROUTER_MODEL=google/mock-model\n'
    )
    assert client.post(endpoint, json={}).status_code == 503
    monkeypatch.setenv("TONE_TOKEN", "test-token")
    assert client.post(endpoint, json={}).status_code == 401
    headers = {"Authorization": "Bearer test-token"}
    requests = []

    def complete(request, timeout):
        assert request.full_url == meeting_ai.OPENROUTER_URL
        assert request.get_header("Authorization") == "Bearer mock-openrouter-key"
        assert timeout == 30
        requests.append(json.loads(request.data))
        assert requests[-1]["model"] == "google/mock-model"
        return BytesIO(b'{"choices":[{"message":{"content":"A meeting answer."}}]}')

    monkeypatch.setattr(meeting_ai, "urlopen", complete)
    for body in ({}, {"question": "What did they say?"}):
        assert client.post(endpoint, json=body, headers=headers).json() == {
            "answer": "A meeting answer."
        }
    summary, question = (payload["messages"][1]["content"] for payload in requests)
    assert "Summarize the meeting" in summary
    assert "What did they say?" in question
    for content in (summary, question):
        assert "[00:00] unknown: Hello" in content
        assert "Another meeting" not in content
    meeting["deleted_at"] = "2026-11-16T12:00:00Z"
    assert client.post("/api/meetings", json=data, headers=headers).status_code == 200
    assert client.post(endpoint, json={}, headers=headers).status_code == 404
    assert len(requests) == 2


def test_meeting_ai_explains_rejected_openrouter_key(client, monkeypatch):
    data = export()
    assert client.post("/api/meetings", json=data).status_code == 200
    monkeypatch.setenv("TONE_TOKEN", "test-token")
    monkeypatch.setenv("OPENROUTER_API_KEY", "mock-invalid-key")
    monkeypatch.setenv("OPENROUTER_MODEL", "google/mock-model")

    def reject(request, timeout):
        raise HTTPError(request.full_url, 401, "Invalid API key", None, None)

    monkeypatch.setattr(meeting_ai, "urlopen", reject)
    meeting_id = data["sessions"][0]["id"]
    response = client.post(
        f"/api/meetings/{meeting_id}/ai", json={}, headers={"Authorization": "Bearer test-token"}
    )
    assert response.status_code == 502
    assert "OpenRouter rejected the API key" in response.json()["detail"]
    assert "OPENROUTER_API_KEY" in response.json()["detail"]
    assert "mock-invalid-key" not in response.text
