# ml/asr: speech recognition research (Audio team)

Optional Mac speech recognition with on-device WhisperKit fallback (A8, issue #68).
Context: `docs/GRAPTION_CONTEXT.md` §§3, 6, 11. Server ASR is a proposed expansion
of the current tone-only server architecture and needs team agreement before integration.

Planned: compare ASR candidates with WhisperKit `base.en` for English accuracy,
caption latency, and streaming behavior. Research only; no integration or benchmarks yet.

- Captions must remain usable fully offline; online ASR is optional.
- Switching between online and local results must avoid duplicate captions.
- Tone never blocks captions. Never store server request audio on disk or in logs.
- Use free local runtimes on team Macs. Data and weights never go in git.
