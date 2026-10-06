# server/: tone server (Platform team)

Small FastAPI server for local Mac development. Requires Python 3.11+ and `uv`.
Spec: [`docs/GRAPTION_CONTEXT.md`](../docs/GRAPTION_CONTEXT.md) §5, §7.

## Run on the Mac

From the repo root, one command installs dependencies as needed and starts the server:

```bash
uv run --directory server uvicorn app.main:app --host 0.0.0.0 --port 8000
```

From `server/`, use `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000`.
Check it with `curl http://localhost:8000/health` (plain text `ok`). On the same
Wi-Fi or phone hotspot, the phone connects to
`ws://<mac-lan-ip>:8000/ws/session?session_id=<session-id>`.

## Session protocol

Send JSON text frames matching `schemas/events.schema.json`, including `session_id`
and `schema_version: "1.0"`. Example sentence audio (PCM16 mono little-endian, base64):

```json
{
  "type": "tone_request",
  "session_id": "demo",
  "schema_version": "1.0",
  "caption_id": "3f1c2a9e-8b7d-4c6e-9a01-2b3c4d5e6f70",
  "t_start": 1.0,
  "t_end": 1.1,
  "sample_rate": 16000,
  "audio_b64": "AAABAAIA"
}
```

Each request gets a `tone_result` with the same session and caption IDs, `tag: null`
("no tone"), six zero probabilities, `model_version: "tone-stub-v1"`, and
`latency_ms.recv_to_send`. The connection stays open for further requests.
`caption_log` events are accepted and discarded; persistence is not implemented yet.
Invalid messages close the connection with code 1008 without echoing their contents.

`app/tone.py` defines `ToneBackend` and `MockToneBackend`. The server currently always
uses the mock; Audio can plug in inference later. No audio is written to disk or logs.
Torch and MediaPipe stay out of this package's dependencies.

Export `TONE_TOKEN` to require `Authorization: Bearer <token>` on the handshake.
Export `DEPLOY_MODE=tunnel` or `cloud` to require a configured token as well.
These environment variables are read from the process; to load a local `.env` file,
pass uvicorn's `--env-file <path>` option. Hosting and real inference are later work.

## Verify and regenerate

From the repo root:

```bash
uv run ruff check .
uv run pytest
```

Tests cover health, repeated audio replies, the schema contract, caption logs,
invalid messages, and token checks. `app/events.py` is generated; never hand-edit it.
Regenerate it from the repo root with:

```bash
uv run datamodel-codegen \
  --input schemas/events.schema.json --input-file-type jsonschema \
  --output server/app/events.py --output-model-type pydantic_v2.BaseModel \
  --target-python-version 3.11 --disable-timestamp --use-standard-collections \
  --use-union-operator --use-default-kwarg --use-title-as-name --use-annotated \
  --formatters ruff-check ruff-format
```

Later: tag mapping, SQLite logging, and Docker packaging. Add server dependencies with
`uv add --package graption-server <pkg>`; tests live in `server/tests/`.
