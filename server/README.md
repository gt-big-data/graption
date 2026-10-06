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
and `schema_version: "1.1"`. Example sentence audio (PCM16 mono little-endian, base64):

```json
{
  "type": "tone_request",
  "session_id": "demo",
  "schema_version": "1.1",
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
Invalid messages receive a `session_error` reply and the connection stays open:

```json
{
  "type": "session_error",
  "session_id": "demo",
  "schema_version": "1.1",
  "code": "invalid_json",
  "message": "Invalid JSON at line 1, column 1: Expecting value",
  "request": "not json",
  "request_encoding": "text",
  "model_version": "tone-stub-v1"
}
```

`request` preserves the exact received text, even if it is invalid JSON. Unsupported
binary frames get an error with the received bytes encoded as base64 and
`request_encoding: "base64"`. Errors describe missing or invalid fields, session mismatches,
invalid base64, PCM16 length, and reversed segment times. Correct and resend on the same
connection. Authentication failures still reject the handshake.

For `session_mismatch`, the error message shows the expected ID from the connection URL
and the received ID from the request, with escaped invisible characters and character
counts. The values must match exactly (including case and spaces). Use `?session_id=demo`
with `"session_id": "demo"` to start. Reconnect after changing the URL in a client app.
Query strings decode `+` as a space; encode a literal plus as `%2B`.

Request contents, audio, authorization headers, and validation exception details are
never logged or stored. Error replies echo payloads only to the client that sent them.

`app/tone.py` defines `ToneBackend` and `MockToneBackend`. The server currently always
uses the mock; Audio can plug in inference later. No audio is written to disk or logs.
Torch and MediaPipe stay out of this package's dependencies.

Export `TONE_TOKEN` to require `Authorization: Bearer <token>` on the handshake.
Export `DEPLOY_MODE=tunnel` or `cloud` to require a configured token as well.
These environment variables are read from the process; to load a local `.env` file,
pass uvicorn's `--env-file <path>` option. Hosting and real inference are later work.

## Verbose logs and metrics

Enable application diagnostics from the repo root:

```bash
uv run --directory server python -m app --verbose
```

The launcher defaults to `--host 0.0.0.0 --port 8000`; both can be overridden.
From `server/`, run `uv run python -m app --verbose`. Omit `--verbose` for normal logging.

Logs appear in the terminal and in a **new repo-root `logs/server-<UTC-timestamp>-<unique-id>.jsonl`**
file on every server start, regardless of whether you start from the root or `server/`.
`logs/` is gitignored and created on startup. The startup log prints the current file path.
Each run's file rotates at 5 MiB with three backups (`<filename>.1` through `.3`);
previous runs remain available and are never appended to or overwritten.
Override the directory with `TONE_LOG_DIR=/path/to/logs` if needed. Without `--verbose`,
only startup/shutdown and warnings/errors are recorded; verbose mode adds:

- Connection open/close events, duration, and close code.
- Received frame types and byte counts; accepted tone requests and caption logs.
- Validated caption IDs, sample rates, segment durations, and decoded audio byte counts.
- Inference, send, and receive-to-send timings in milliseconds.
- Per-connection totals for received messages, accepted/rejected requests, bytes, and timings.

Each entry includes a UTC diagnostic timestamp, level, event, and model version.
A generated `connection_id` links entries without logging caller-provided session IDs.
These are application diagnostics; uvicorn's own access/startup messages remain console-only.
Use `--verbose` for payload-free diagnostics; uvicorn's `--log-level debug` can expose
raw WebSocket frames and should not be used with audio.

To follow the file from the repo root:

```bash
tail -f "$(ls -t logs/server-*.jsonl | head -1)"
```

## Verify and regenerate

From the repo root:

```bash
uv run ruff check .
uv run pytest
```

Tests cover health, repeated audio replies, the schema contract, caption logs,
recoverable errors with exact request echoes, and token checks. `app/events.py` is generated; never hand-edit it.
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
