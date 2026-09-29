# server/: tone server (Platform team)

FastAPI + WebSocket server the phone sends sentence audio to for tone tags. Same code runs on the
Mac (local), behind a Cloudflare tunnel, or on Cloud Run. Spec: `docs/GRAPTION_CONTEXT.md` §5, §7.

## What to build (Milestone 1: "Mac echo server")
Put code in `server/app/`:

| File | Does |
|---|---|
| `main.py` | FastAPI app, `GET /health` |
| `ws.py` | `/ws/session?session_id=...`: receive `tone_request` → reply `tone_result` (stub: `tag: null`); accept `caption_log` |
| `config.py` | env vars from `.env.example`: `DEPLOY_MODE`, `TONE_BACKEND`, `TONE_TOKEN`, `TAG_THRESHOLD`, … |
| `auth.py` | if `TONE_TOKEN` is set, reject the handshake unless `Authorization: Bearer <token>` matches |
| `tone.py` | `ToneBackend` interface + stub. **Audio team** plugs the real model in here later |

Later: `tags.py` (tag mapper), `db.py` (SQLite logging), `Dockerfile` (Cloud Run, weeks 9–10).

Rules: messages must match `schemas/events.schema.json`. **Never write audio to disk or logs.**
No torch/mediapipe in this package's deps.

## Run (once `app/main.py` exists)
```bash
cd server
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
curl localhost:8000/health
```
Add deps with `uv add --package graption-server <pkg>`. Tests go in `server/tests/`
(`uv add --dev httpx` for FastAPI's `TestClient`).
