# P2 WAV replay client

Start P2 from the repository root in one terminal:

```bash
uv run --directory server python -m app
```

In another terminal, replay an uncompressed 16-bit PCM mono WAV ([sample](https://mauvecloud.net/sounds/pcm1608m.wav)):

```bash
uv run python scripts/replay_client.py /path/to/audio.wav
```

The client sends one-second chunks over a single WebSocket connection and prints
one JSON reply per chunk, including the final shorter chunk. It waits for each
reply before sending the next chunk; replay runs as fast as the server responds.
P2's mock backend returns `tone_result` with `tag: null`.

For a different server or chunk size:

```bash
uv run python scripts/replay_client.py /path/to/audio.wav \
  --url ws://127.0.0.1:8000/ws/session --chunk-seconds 0.5 --session-id demo
```

Use `wss://` for a remote server and set `TONE_TOKEN` in the client environment
when authentication is enabled. `--timeout` controls connection and per-reply
timeouts (default 30 seconds). Errors exit with a nonzero status.

Audio is read in chunks, without sending the WAV header or creating recordings.
The file's sample rate is sent unchanged; 16 kHz is recommended. Other bit depths,
stereo, and compressed WAV files must be converted first. Timestamps emulate a
phone session starting at zero using sample offsets. Keep recordings out of git.
