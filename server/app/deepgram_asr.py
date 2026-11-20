"""Deepgram cloud transcription (ASR_BACKEND=deepgram). Opt-in, demo use.

The phone sends a completed speech segment to this Mac, which forwards it to Deepgram's
pre-recorded API and returns the text. The API key stays on the Mac (DEEPGRAM_API_KEY in the
repo-root .env); it never ships in the iOS app. Audio is sent to Deepgram over HTTPS with
`mip_opt_out=true` (Deepgram's Model Improvement Program opt-out) and is never written to
disk or logs here. Captions still fall back to on-device WhisperKit when this fails.
"""

import asyncio
import json
import os
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from app.asr import ASRPrediction

LISTEN_URL = "https://api.deepgram.com/v1/listen"
DEFAULT_MODEL = "nova-3"
TIMEOUT_SECONDS = 8


def transcript_from(reply: dict) -> str:
    """The first alternative of the first channel, or "" when Deepgram heard nothing."""
    try:
        return reply["results"]["channels"][0]["alternatives"][0]["transcript"].strip()
    except (KeyError, IndexError, TypeError, AttributeError):
        raise ValueError("Unexpected Deepgram response shape") from None


class DeepgramASRBackend:
    def __init__(self, api_key: str | None = None, model: str | None = None) -> None:
        self._key = (api_key if api_key is not None else os.getenv("DEEPGRAM_API_KEY", "")).strip()
        if not self._key:
            raise ValueError("Set DEEPGRAM_API_KEY in the repo-root .env for ASR_BACKEND=deepgram")
        self.model = (model or os.getenv("DEEPGRAM_MODEL") or DEFAULT_MODEL).strip()
        self.model_version = f"deepgram-{self.model}"

    async def transcribe(self, audio: bytes) -> ASRPrediction:
        try:
            text = await asyncio.to_thread(self._request, audio)
        except (HTTPError, URLError, TimeoutError, ValueError, OSError):
            # No details: the error body or URL could carry request data.
            return ASRPrediction("", "error", self.model_version)
        return ASRPrediction(text, "ok", self.model_version)

    def _request(self, audio: bytes) -> str:
        query = urlencode(
            {
                "model": self.model,
                "language": "en",
                "smart_format": "true",
                "punctuate": "true",
                "encoding": "linear16",
                "sample_rate": 16000,
                "channels": 1,
                "mip_opt_out": "true",
            }
        )
        request = Request(
            f"{LISTEN_URL}?{query}",
            data=audio,
            method="POST",
            headers={
                "Authorization": f"Token {self._key}",
                "Content-Type": "application/octet-stream",
            },
        )
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return transcript_from(json.loads(response.read()))
