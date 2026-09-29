# ml/asd: speaker detection model (Vision team)

"Is this face speaking?" from 15 frames of 96-dim features. Spec: `docs/GRAPTION_CONTEXT.md` §8.

Planned: `extract.py` (AVA → MediaPipe → features → `.npz`), `dataset.py`, `train.py`
(GRU and 1D-CNN), `eval.py`, `export.py` (Core ML `.mlpackage` + parity test, versions `asd-vN`).

- Features come only from `ml/common/features.py`.
- Baseline to beat: logistic regression on `std(jawOpen)` + `mean(loudness)`.
- Training runs on PACE. Data and weights never go in git (see `.gitignore`); log runs to W&B.
- Add deps with `uv add --package graption-ml <pkg>` (torch, mediapipe, coremltools, wandb).
