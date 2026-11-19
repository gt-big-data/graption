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
and `schema_version: "1.3"`. Example sentence audio (PCM16 mono little-endian, base64):

```json
{
  "type": "tone_request",
  "session_id": "demo",
  "schema_version": "1.3",
  "caption_id": "3f1c2a9e-8b7d-4c6e-9a01-2b3c4d5e6f70",
  "t_start": 1.0,
  "t_end": 1.1,
  "sample_rate": 16000,
  "audio_b64": "AAABAAIA"
}
```

Each request gets a `tone_result` with the same session and caption IDs, a `tag`, six
probabilities, `model_version`, and `latency_ms.recv_to_send`. With the default mock backend
the tag is always `null` ("no tone"), the probabilities are zero, and the model version is
`tone-stub-v1`; see "Real tone tags" below. The connection stays open for further requests.
`caption_log` events are accepted and discarded; persistence is not implemented yet.
Invalid messages receive a `session_error` reply and the connection stays open:

```json
{
  "type": "session_error",
  "session_id": "demo",
  "schema_version": "1.3",
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

## Real tone tags (audEERING baseline)

`TONE_BACKEND` picks the backend: `mock` (default) or `audeering`. One-time setup from the
repo root downloads the model (~1.2 GB) into the Hugging Face cache, never into the repo:

```bash
uv run hf download audeering/wav2vec2-large-robust-12-ft-emotion-msp-dim
```

Then start the server with the real model:

```bash
TONE_BACKEND=audeering uv run --directory server python -m app
```

Tags are `excited`, `upset`, `calm`, or `null`, from the arousal/valence thresholds tuned in
A4 (`AudeeringThresholds` in `app/tone.py`). Segments under 0.5 s always get `null`, and
`probs` stay zero because the model has no 6-emotion output. `model_version` is
`audeering-msp-dim-a4`. The model runs on `cuda`, `mps`, or `cpu`, whichever is available,
one segment at a time, off the event loop. On an M-series Mac a 3 s segment takes ~40 ms
after the first request (~0.5 s warm-up). Check it with the P3 replay client
(`scripts/README.md`). If the model isn't downloaded, startup fails with the command above.

`app/tone.py` defines `ToneBackend`, `MockToneBackend`, the tag rules, and `create_backend`.
`app/audeering.py` holds the model and is imported only when selected. No audio is written
to disk or logs. Torch, transformers, and scipy come from the uv workspace (`graption-ml`);
they are not dependencies of this package, and MediaPipe stays out entirely.

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

`RUN_MODEL_TESTS=1 uv run pytest server/tests/test_tone.py` also runs the downloaded model.
Tests cover tag thresholds, backend selection, health, repeated audio replies, the schema contract, caption logs,
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

Later: the custom WavLM backend, SQLite logging, and Docker packaging. Add server dependencies with
`uv add --package graption-server <pkg>`; tests live in `server/tests/`.


## Optional Mac transcription

The separate `/ws/asr` endpoint accepts finished 16 kHz mono PCM16 segments and
returns one final transcript per request. It does not store or log request audio.
The mock backend returns unavailable, so the app falls back to WhisperKit.

On Apple Silicon, install the optional runtime and cache a checkpoint before startup:

```sh
uv sync --package graption-server --extra asr
uv run --no-sync python - <<'PYMODEL'
from pathlib import Path
from huggingface_hub import snapshot_download
print(snapshot_download(
    "mlx-community/whisper-base.en-mlx",
    revision="aa0678c3466ed62c5c6114ec600a0e1f96820089",
    cache_dir=Path.home() / "Library/Caches/Graption/huggingface",
    allow_patterns=["config.json", "weights.npz"],
))
PYMODEL
```

From the repository root, set `ASR_MODEL_PATH` to the printed snapshot path:

```sh
ASR_BACKEND=mlx \
ASR_MODEL_PATH="/path/to/cached/snapshot" \
ASR_MODEL_REVISION=aa0678c3466ed62c5c6114ec600a0e1f96820089 \
uv run --no-sync uvicorn app.main:app --app-dir server --host 0.0.0.0 --port 8000 \
  --ws-max-size 450000 --log-level info
```

Set `ASR_TOKEN` in the server environment and local iOS configuration if using
authentication (required outside local deployment mode). Use plain WS only on a
trusted local network. Keep uvicorn frame logging disabled. Both app and server
must use schema 1.3; rebuild the phone app when updating the server.


### Saved meetings and web dashboard

Real iPhone microphone sessions now save caption text locally as results arrive.
Stop finalizes the meeting after queued transcriptions finish. With `TONE_URL`
configured, the app also retries text-only JSON sync every 15 seconds while active,
including after a later app launch. No meeting-sync audio or video is stored or sent.
The server bearer credential protects upload and dashboard read endpoints once paired,
or when a manual `TONE_TOKEN` is configured. This is a shared development store.

`POST /api/meetings` accepts v1/v2 session exports and upserts meetings by
UUID. `GET /api/meetings` returns a v2 export the dashboard can read. The database
is `data/meetings.sqlite3` by default; set `MEETINGS_DB` to a persistent path to
retain meetings across server replacement (especially with ephemeral cloud disks).

Build the web app with `cd apps/web && npm ci && npm run build`, then start/restart
the server on `0.0.0.0` and open `http://localhost:8000/graption/` on the Mac.
Choose **Pair an iPhone or iPad**, then **Connection & Preferences → Scan pairing
code** in Graption. Keep both devices on the same trusted network and allow the app
local-network access. The code uses the Mac's Bonjour `.local` name and expires after
two minutes or one successful scan. The device saves the connection in Keychain
and the dashboard saves its access in that browser. The server uses
`data/meetings.pairing-token` by default, alongside its database. Keep that file
when restarting or moving the server. Set `GRAPTION_PAIR_URL` to a reachable
`wss://` or `ws://<hostname>.local:<port>` only if automatic addressing is unsuitable.

Click **Load / refresh from server** to fetch saved meetings. For `npm run dev`,
Vite proxies `/api` to `http://127.0.0.1:8000`. The standalone hosted dashboard
supports manual JSON imports. Server loading requires the same-origin API or a proxy.

The v2 export adds sound events (time, confidence, model version), tone probabilities
or baseline dimensional scores, meeting titles, and redacted deletion markers. The
phone's Saved sessions swipe actions rename/delete meetings. Retention is selectable
(forever/7/30/90 days); deletions propagate when the phone next syncs. A deleted UUID
cannot be resurrected by an older upload. Existing v1 JSON imports remain supported.
The dashboard displays numbered speakers with the same ID-based colors as the phone,
plus sound alerts and expandable tone details. Refresh replaces its previous server
snapshot so deleted meetings disappear. Separately exported files remain unchanged.

Speaker attribution uses a provisional mouth-motion heuristic. Sync resumes while the
app is active.

### Optional meeting AI (OpenRouter)

Put `OPENROUTER_API_KEY` in the gitignored **repository-root `.env`** on the Mac.
The dashboard gets its server credential from the pairing workflow.
The default model is `google/gemma-3-27b-it:free`.
`OPENROUTER_MODEL` selects another explicit non-OpenAI model.

After building the dashboard, start or restart the Mac server from the repo root.

```bash
uv run --directory server --env-file ../.env uvicorn app.main:app --host 0.0.0.0 --port 8000
```

In `/graption/`, load synced meetings and open one with
captions. **Generate summary** and **Ask** send the selected transcript text,
speaker IDs and timestamps to OpenRouter on demand. The app requests providers
with data collection disabled. Answers stay in browser memory. Each question
uses the transcript as context. Standalone JSON imports remain available offline.
