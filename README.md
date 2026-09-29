# Graption

Real-time, speaker-aware captions for Deaf and hard-of-hearing users. Point an iPhone at a
conversation and see **who** is speaking, **how** they sound (tone), and important **sounds**
(doorbell, alarm, siren). Big Data Big Impact @ Georgia Tech.

> **Sarah** 😃 *excited*: "Did someone ring the doorbell?!"   🔔 **Doorbell**

Captions, speaker highlighting, and sound alerts run **on the phone, offline**. Only tone tags come
from a small server (a Mac on the same Wi-Fi, or optionally the cloud).

📖 **Read first:** [`docs/GRAPTION_CONTEXT.md`](docs/GRAPTION_CONTEXT.md) (the full plan) and
[`docs/graption-architecture-v4.drawio`](docs/graption-architecture-v4.drawio) (open at
[app.diagrams.net](https://app.diagrams.net)).

## Where each team works

| Folder | What | Team |
|---|---|---|
| `apps/ios/` | iOS app (not created yet; plan in its README) | all four |
| `ml/common/`, `ml/asd/` | feature spec + speaker detection model | Vision |
| `ml/tone/` | tone model | Audio |
| `server/` | tone server (FastAPI + WebSocket) | Platform (Audio plugs in the model) |
| `language/` | AI summaries/notes for the past-meetings dashboard | Platform |
| `schemas/` | JSON shape of every message between teams | Platform owns; everyone reads |
| `docs/` | the plan | lead |

Each folder's README says what to build first.

## Setup (Python parts, any OS)

```bash
# 1. install uv: https://docs.astral.sh/uv/getting-started/installation/
uv sync                  # 2. install everything
uv run pytest            # 3. check it works
cp .env.example .env     # 4. only if you need secrets/config; never commit .env
```

iOS work needs a Mac with Xcode. Coding agents: see [`CLAUDE.md`](CLAUDE.md).

## Rules
- Branch → PR to `main`; CI (lint + tests) must pass.
- Never commit datasets, model weights, recordings, or secrets (`.gitignore` blocks the common ones).
- Changing `schemas/` or `ml/common/` affects other teams: tag the lead.
