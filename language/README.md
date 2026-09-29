# language/: AI summaries and notes (Platform team)

Post-session "catch me up" summaries/notes built from the caption log (speaker + text + tone).
They're shown in the iOS **past-meetings dashboard** (also Platform). Spec: `docs/GRAPTION_CONTEXT.md` §10.

- **Target:** Apple Foundation Models, on-device (written in Swift in the app, not here).
- **Here:** Python prototypes (Ollama on the Mac) and the OpenAI benchmark that sets the quality bar.
  Eval set: ~20 transcripts + reference summaries.
- On-device context is ~4K tokens: chunk and summarize hierarchically.
- `OPENAI_API_KEY` goes in `.env` only. **Never** call OpenAI from the iOS app.
- Not on the MVP critical path. Add deps with `uv add --package graption-language <pkg>`.
