"""Issue short-lived device pairing codes from the Mac's local dashboard."""

import json
import os
import re
from io import BytesIO
from ipaddress import ip_address
from pathlib import Path
from secrets import compare_digest, token_urlsafe
from subprocess import SubprocessError, check_output
from tempfile import NamedTemporaryFile
from time import monotonic
from urllib.parse import urlsplit

import segno
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

router = APIRouter()
PAIRING_LIFETIME = 120


def credential_file() -> Path:
    database = Path(os.getenv("MEETINGS_DB", "data/meetings.sqlite3"))
    return database.with_suffix(".pairing-token")


def paired_token() -> str:
    try:
        return credential_file().read_text().strip()
    except FileNotFoundError:
        return ""


def server_token() -> str:
    return os.getenv("TONE_TOKEN") or paired_token()


def ensure_server_token() -> str:
    if token := server_token():
        return token
    path = credential_file()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Publish the complete credential atomically, even if two processes pair at once.
    with NamedTemporaryFile(dir=path.parent, mode="w") as tmp:
        tmp.write(token_urlsafe(32))
        tmp.flush()
        try:
            os.link(tmp.name, path)
        except FileExistsError:
            pass
    return paired_token()


def pairing_url(request: Request) -> str:
    if url := os.getenv("GRAPTION_PAIR_URL"):
        parts = urlsplit(url)
        host = parts.hostname
        allowed_transport = parts.scheme == "wss" or (
            parts.scheme == "ws" and host and host.endswith(".local")
        )
        if (
            host and allowed_transport and parts.path in {"", "/"}
            and not (parts.username or parts.password or parts.query or parts.fragment)
        ):
            return url
        raise HTTPException(503, "GRAPTION_PAIR_URL must use wss:// or a ws:// .local address.")
    try:
        hostname = check_output(
            ["/usr/sbin/scutil", "--get", "LocalHostName"], text=True, timeout=2
        ).strip()
    except (OSError, SubprocessError):
        hostname = ""
    if not re.fullmatch(r"[A-Za-z0-9-]+", hostname):
        raise HTTPException(503, "Set GRAPTION_PAIR_URL to this Mac's reachable server address.")
    port = request.scope["server"][1]
    return f"ws://{hostname}.local:{port}"


def require_local_dashboard(request: Request) -> None:
    host = request.url.hostname
    client = request.client
    origin = request.headers.get("origin")
    forwarded = ("forwarded", "x-forwarded-for", "x-forwarded-host")
    try:
        loopback = client is not None and ip_address(client.host).is_loopback
    except ValueError:
        loopback = False
    if (
        host not in {"localhost", "127.0.0.1", "::1"}
        or not loopback
        or any(name in request.headers for name in forwarded)
        or (origin and urlsplit(origin).netloc != request.url.netloc)
    ):
        raise HTTPException(403, "Open the dashboard at localhost on the Mac to pair a device.")


class PairingCode(BaseModel):
    code: str = Field(min_length=16, max_length=100, pattern=r"^[A-Za-z0-9_-]+$")


@router.post("/api/pairing")
async def create_pairing(request: Request):
    require_local_dashboard(request)
    url = pairing_url(request)
    token = ensure_server_token()
    code = token_urlsafe(24)
    request.app.state.device_pairing = (code, monotonic() + PAIRING_LIFETIME)
    payload = json.dumps({"v": 1, "url": url, "code": code}, separators=(",", ":"))
    qr = segno.make_qr(payload, error="m")
    svg = BytesIO()
    qr.save(svg, kind="svg", dark="#142929", light="#ffffff", scale=6)
    return JSONResponse(
        {"qr": svg.getvalue().decode(), "token": token},
        headers={"Cache-Control": "no-store"},
    )


@router.post("/api/pairing/connect")
async def connect_device(body: PairingCode, request: Request):
    code, expiry = getattr(request.app.state, "device_pairing", ("", 0))
    if monotonic() >= expiry or not compare_digest(body.code, code):
        raise HTTPException(
            401, "Pairing code expired or already used. Show a new code on the Mac."
        )
    token = server_token()
    if not token:
        raise HTTPException(503, "Pairing is unavailable.")
    request.app.state.device_pairing = ("", 0)
    asr_token = None
    if os.getenv("ASR_BACKEND", "").strip().lower() == "mlx":
        asr_token = os.getenv("ASR_TOKEN") or token
    return JSONResponse(
        {"token": token, "asr_token": asr_token},
        headers={"Cache-Control": "no-store"},
    )
