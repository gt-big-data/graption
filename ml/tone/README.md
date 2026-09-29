# ml/tone: tone model (Audio team)

6-class emotion per sentence (anger, disgust, fear, happy, neutral, sad). Spec: `docs/GRAPTION_CONTEXT.md` §7, §9.

Planned: `embed.py` (CREMA-D through frozen WavLM once → `[13, 768]` per clip), `train_head.py`,
`eval.py`, `baseline.py` (audEERING arousal/valence mapping).

- Split CREMA-D **by actor** 70/15/15, fixed seed. Team recordings are the real test set.
- Must match/beat the audEERING baseline before replacing it on the server (`server/app/tone.py`).
- Data and weights never go in git. Add deps with `uv add --package graption-ml <pkg>`.
