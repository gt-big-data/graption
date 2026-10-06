"""Schema-compatible session transport. Never log request bodies or audio."""

import base64
import binascii
import json
import logging
import os
from hmac import compare_digest
from time import perf_counter

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from app.events import CaptionLog, SessionError, ToneRequest, ToneResult
from app.tone import ToneBackend

router = APIRouter()
logger = logging.getLogger("uvicorn.error")


async def send_error(
    websocket: WebSocket,
    session_id: str,
    backend: ToneBackend,
    code: str,
    message: str,
    request: str,
    request_encoding: str = "text",
) -> None:
    # Only fixed codes: exceptions and echoed requests can contain raw audio.
    logger.warning(
        "Rejected WebSocket request: reason=%s model_version=%s", code, backend.model_version
    )
    result = SessionError.model_validate(
        {
            "type": "session_error",
            "session_id": session_id,
            "schema_version": "1.1",
            "code": code,
            "message": message,
            "request": request,
            "request_encoding": request_encoding,
            "model_version": backend.model_version,
        }
    )
    await websocket.send_json(result.model_dump(mode="json"))


def reject_nonfinite(value: str) -> None:
    raise ValueError("Non-finite numbers are not valid JSON.")


def session_mismatch_message(expected: str, received: str, field: str = "session_id") -> str:
    # Escaping makes invisible characters visible in the client response, never the logs.
    return (
        f"{field} must exactly match the session_id in the connection URL. "
        f"Expected {ascii(expected)} ({len(expected)} characters); "
        f"received {ascii(received)} ({len(received)} characters). "
    )


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
            frame = await websocket.receive()
            if frame["type"] == "websocket.disconnect":
                return
            received_at = perf_counter()
            if "text" not in frame:
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "expected_json_text_frame",
                    "Send a JSON text frame; binary audio frames are not supported.",
                    base64.b64encode(frame["bytes"]).decode("ascii"),
                    "base64",
                )
                continue
            raw = frame["text"]
            try:
                message = json.loads(raw, parse_constant=reject_nonfinite)
            except json.JSONDecodeError as error:
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "invalid_json",
                    f"Invalid JSON at line {error.lineno}, column {error.colno}: {error.msg}",
                    raw,
                )
                continue
            except ValueError:
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "invalid_json",
                    "Non-finite numbers (NaN or Infinity) are not valid JSON.",
                    raw,
                )
                continue

            if not isinstance(message, dict) or message.get("type") not in (
                "tone_request",
                "caption_log",
            ):
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "unsupported_event",
                    "Expected a JSON object with type 'tone_request' or 'caption_log'.",
                    raw,
                )
                continue
            model = ToneRequest if message["type"] == "tone_request" else CaptionLog
            try:
                event = model.model_validate(message)
            except ValidationError as error:
                details = "; ".join(
                    f"{'.'.join(map(str, item['loc'])) or 'request'}: {item['msg']}"
                    for item in error.errors(include_input=False, include_context=False)
                )
                await send_error(
                    websocket, session_id, backend, "schema_validation_failed", details, raw
                )
                continue

            if event.session_id.root != session_id:
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "session_mismatch",
                    session_mismatch_message(session_id, event.session_id.root),
                    raw,
                )
                continue
            if isinstance(event, CaptionLog):
                if event.caption.session_id.root != session_id:
                    await send_error(
                        websocket,
                        session_id,
                        backend,
                        "caption_session_mismatch",
                        session_mismatch_message(
                            session_id, event.caption.session_id.root, "caption.session_id"
                        ),
                        raw,
                    )
                # Accepted for compatibility; persistence is a later milestone.
                continue
            try:
                audio = base64.b64decode(event.audio_b64, validate=True)
            except (ValueError, binascii.Error):
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "invalid_base64_audio",
                    "audio_b64 must contain valid base64-encoded PCM16 mono little-endian audio.",
                    raw,
                )
                continue
            if len(audio) % 2:
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "invalid_pcm16_length",
                    "PCM16 audio must have an even byte count (two bytes per sample).",
                    raw,
                )
                continue
            if event.t_end.root < event.t_start.root:
                await send_error(
                    websocket,
                    session_id,
                    backend,
                    "invalid_segment_times",
                    "t_end must be greater than or equal to t_start.",
                    raw,
                )
                continue

            prediction = await backend.predict(audio, event.sample_rate)
            caption_id = event.caption_id.root
            del audio, message, event, raw, frame
            result = ToneResult.model_validate(
                {
                    "type": "tone_result",
                    "session_id": session_id,
                    "schema_version": "1.1",
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
