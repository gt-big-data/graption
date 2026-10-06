"""Schema-compatible session transport. Never log request bodies or audio."""

import base64
import binascii
import json
import os
from hmac import compare_digest
from time import perf_counter

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from pydantic import TypeAdapter, ValidationError

from app.events import CaptionLog, ToneRequest, ToneResult
from app.tone import ToneBackend

router = APIRouter()
incoming = TypeAdapter(ToneRequest | CaptionLog)


@router.websocket("/ws/session")
async def session(websocket: WebSocket, session_id: str = Query(min_length=1)) -> None:
    token = os.getenv("TONE_TOKEN", "")
    mode = os.getenv("DEPLOY_MODE", "local")
    authorization = websocket.headers.get("authorization", "")
    if (mode != "local" and not token) or (
        token and not compare_digest(authorization.encode(), f"Bearer {token}".encode())
    ):
        await websocket.close(code=1008)
        return

    await websocket.accept()
    backend: ToneBackend = websocket.app.state.tone_backend
    try:
        while True:
            message = await websocket.receive_json()
            received_at = perf_counter()
            try:
                event = incoming.validate_python(message)
                if event.session_id.root != session_id:
                    raise ValueError("Session mismatch")
                if isinstance(event, CaptionLog):
                    # Accepted for compatibility; persistence is a later milestone.
                    if event.caption.session_id.root != session_id:
                        raise ValueError("Caption session mismatch")
                    continue
                audio = base64.b64decode(event.audio_b64, validate=True)
                if len(audio) % 2 or event.t_end.root < event.t_start.root:
                    raise ValueError("Invalid PCM16 segment")
            except (ValidationError, ValueError, binascii.Error):
                await websocket.close(code=1008, reason="Invalid session event")
                return

            prediction = await backend.predict(audio, event.sample_rate)
            caption_id = event.caption_id.root
            del audio, message, event
            result = ToneResult.model_validate(
                {
                    "type": "tone_result",
                    "session_id": session_id,
                    "schema_version": "1.0",
                    "caption_id": caption_id,
                    "tag": prediction.tag,
                    "probs": prediction.probs,
                    "model_version": prediction.model_version,
                    "latency_ms": {"recv_to_send": (perf_counter() - received_at) * 1000},
                }
            )
            await websocket.send_json(result.model_dump(mode="json"))
    except WebSocketDisconnect:
        pass
    except (json.JSONDecodeError, KeyError, UnicodeDecodeError):
        await websocket.close(code=1008, reason="Expected a JSON session event")
