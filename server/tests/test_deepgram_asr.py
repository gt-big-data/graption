"""Deepgram ASR backend with the network faked: parsing, failures, selection and auth."""

import asyncio
import json
from urllib.error import URLError

import pytest

from app import deepgram_asr
from app.asr import asr_requires_pairing, create_asr_backend
from app.deepgram_asr import DeepgramASRBackend, transcript_from


def reply(text: str) -> dict:
    return {"results": {"channels": [{"alternatives": [{"transcript": text}]}]}}


def test_transcript_parsing():
    assert transcript_from(reply(" Hello there. ")) == "Hello there."
    assert transcript_from(reply("")) == ""
    with pytest.raises(ValueError):
        transcript_from({"results": {}})


def test_missing_key_fails_at_startup(monkeypatch):
    monkeypatch.setenv("ASR_BACKEND", "deepgram")
    monkeypatch.delenv("DEEPGRAM_API_KEY", raising=False)
    with pytest.raises(ValueError, match="DEEPGRAM_API_KEY"):
        create_asr_backend()


def test_selected_backend_requires_pairing(monkeypatch):
    monkeypatch.setenv("ASR_BACKEND", "deepgram")
    monkeypatch.setenv("DEEPGRAM_API_KEY", "test-key")
    backend = create_asr_backend()
    assert isinstance(backend, DeepgramASRBackend)
    assert backend.model_version == "deepgram-nova-3"
    assert asr_requires_pairing()
    monkeypatch.setenv("ASR_BACKEND", "mock")
    assert not asr_requires_pairing()


def test_request_sends_raw_pcm_with_opt_out(monkeypatch):
    sent = {}

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def read(self):
            return json.dumps(reply("Did someone knock?")).encode()

    def fake_urlopen(request, timeout):
        sent["url"] = request.full_url
        sent["auth"] = request.get_header("Authorization")
        sent["body"] = request.data
        return Response()

    monkeypatch.setattr(deepgram_asr, "urlopen", fake_urlopen)
    backend = DeepgramASRBackend(api_key="test-key")
    prediction = asyncio.run(backend.transcribe(b"\0\0" * 1600))
    assert prediction.status == "ok"
    assert prediction.text == "Did someone knock?"
    assert sent["auth"] == "Token test-key"
    assert sent["body"] == b"\0\0" * 1600
    assert "mip_opt_out=true" in sent["url"]
    assert "encoding=linear16" in sent["url"] and "sample_rate=16000" in sent["url"]


def test_network_failure_is_an_error_status_so_the_phone_falls_back(monkeypatch):
    def failing_urlopen(request, timeout):
        raise URLError("offline")

    monkeypatch.setattr(deepgram_asr, "urlopen", failing_urlopen)
    prediction = asyncio.run(DeepgramASRBackend(api_key="test-key").transcribe(b"\0\0" * 1600))
    assert prediction.status == "error"
    assert prediction.text == ""
