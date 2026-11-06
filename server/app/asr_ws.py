"""Completed-segment ASR transport. Never echo, persist, or log request content."""

import base64
import binascii
import json
import logging
import os
from hmac import compare_digest
from time import perf_counter
from uuid import uuid4

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from pydantic import ValidationError

from app.asr import ASRBackend, ASRPrediction
from app.events import ASRRequest, ASRResult, SessionError
from app.observability import record

router = APIRouter()
MAX_FRAME_BYTES = 450_000
MAX_AUDIO_BYTES = 320_000  # 10 seconds, 16 kHz, mono PCM16


def reject_constant(value: str) -> None:
    raise ValueError("Non-finite JSON")


@router.websocket("/ws/asr")
async def asr_session(websocket: WebSocket, session_id: str = Query(min_length=1)) -> None:
    backend: ASRBackend = websocket.app.state.asr_backend
    connection_id = str(uuid4())
    token = os.getenv("ASR_TOKEN", "")
    auth = websocket.headers.get("authorization", "")
    if (os.getenv("DEPLOY_MODE", "local") != "local" and not token) or (
        token and not compare_digest(auth.encode(), f"Bearer {token}".encode())
    ):
        await websocket.close(code=1008)
        return
    await websocket.accept()
    record(logging.DEBUG, "asr_connected", backend.model_version, connection_id=connection_id)
    try:
        while True:
            frame = await websocket.receive()
            if frame["type"] == "websocket.disconnect":
                return
            started = perf_counter()
            raw = frame.get("text")
            if raw is None or len(raw.encode("utf-8")) > MAX_FRAME_BYTES:
                await websocket.close(code=1009 if raw is not None else 1003)
                return
            try:
                json.loads(raw, parse_constant=reject_constant)
                event = ASRRequest.model_validate_json(raw, strict=True)
                if event.session_id.root != session_id:
                    raise ValueError("Session mismatch")
                audio = base64.b64decode(event.audio_b64, validate=True)
                duration = event.t_end.root - event.t_start.root
                if not audio or len(audio) % 2 or len(audio) > MAX_AUDIO_BYTES:
                    raise ValueError("Invalid PCM length")
                if duration <= 0 or abs(len(audio) / 32000 - duration) > 1 / 16000:
                    raise ValueError("Audio duration mismatch")
            except (ValueError, ValidationError, binascii.Error, TypeError):
                # Fixed error text; even malformed requests are not echoed.
                error = SessionError.model_validate(
                    {
                        "type": "session_error",
                        "session_id": session_id,
                        "schema_version": "1.3",
                        "code": "invalid_asr_request",
                        "message": "Invalid ASR request",
                        "request": "",
                        "request_encoding": "text",
                        "model_version": backend.model_version,
                    }
                )
                await websocket.send_text(error.model_dump_json())
                record(
                    logging.WARNING,
                    "asr_rejected",
                    backend.model_version,
                    connection_id=connection_id,
                    reason="invalid_asr_request",
                )
                continue
            try:
                prediction = await backend.transcribe(audio)
            except Exception:
                # Never include exception details: libraries may attach audio/text.
                prediction = ASRPrediction("", "error", backend.model_version)
                record(
                    logging.ERROR,
                    "asr_inference_failed",
                    backend.model_version,
                    connection_id=connection_id,
                )
            response = ASRResult.model_validate(
                {
                    "type": "asr_result",
                    "session_id": session_id,
                    "schema_version": "1.3",
                    "caption_id": event.caption_id.root,
                    "t_start": event.t_start.root,
                    "t_end": event.t_end.root,
                    "status": prediction.status,
                    "text": prediction.text,
                    "model_version": prediction.model_version,
                    "latency_ms": {"recv_to_send": (perf_counter() - started) * 1000},
                }
            )
            del audio, raw, frame, event, prediction
            await websocket.send_text(response.model_dump_json())
            record(
                logging.DEBUG,
                "asr_result_sent",
                backend.model_version,
                connection_id=connection_id,
                status=response.status.value,
                recv_to_send_ms=response.latency_ms.recv_to_send,
            )
    except WebSocketDisconnect:
        pass
    except Exception:
        record(
            logging.ERROR,
            "asr_connection_failed",
            backend.model_version,
            connection_id=connection_id,
        )
        await websocket.close(code=1011)
