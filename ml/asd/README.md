# ml/asd: speaker detection model (Vision team)

"Is this face speaking?" from 15 frames of 96-dim features. Spec: `docs/GRAPTION_CONTEXT.md` §8.

Planned: `extract.py` (AVA → MediaPipe → features → `.npz`), `dataset.py`, `train.py`
(GRU and 1D-CNN), `eval.py`, `export.py` (Core ML `.mlpackage` + parity test, versions `asd-vN`).

- Features come only from `ml/common/features.py`.
- Baseline to beat: logistic regression on `std(jawOpen)` + `mean(loudness)`.
- Training runs on team Macs (`mps`). Data and weights never go in git (see `.gitignore`); log runs to W&B.
- Add deps with `uv add --package graption-ml <pkg>` (torch, mediapipe, coremltools, wandb).

## Getting the AVA-ActiveSpeaker data (`ava_download.py`)

AVA-ActiveSpeaker: 153 movies (120 train + 33 val). Only seconds 900-1800 of each are labeled.
`ava_download.py` downloads each movie, keeps only that window at 15 fps (at most 720p, H.264,
no audio), saves the audio as a 16 kHz mono WAV, then deletes the full movie.

**Where the data is:** shared Drive folder
<https://drive.google.com/drive/folders/1p2VGn1h_gq6GOEkYEZaqTaFIRljTRmGv?usp=sharing>.
It mirrors the local layout under `data/ava/` (gitignored; never commit videos, audio or labels):

```
data/ava/labels/{train,val}/<video_id>-activespeaker.csv   # video id, time, x1,y1,x2,y2, label, face id
data/ava/{train,val}/videos/<video_id>.mp4                 # seconds 900-1800, 15 fps, <=720p
data/ava/{train,val}/audio/<video_id>.wav                  # same window, 16 kHz mono
data/ava/failed_<shard>.txt                                # videos that failed (id, reason)
```

**Run it** (needs `brew install ffmpeg`; ~a few GB of temp disk, one movie at a time):

```bash
uv run python ml/asd/ava_download.py --shard 1/4   # person 1 of 4; use 2/4, 3/4, 4/4 for the others
uv run python ml/asd/ava_download.py --dry-run     # show what would be done
uv run python ml/asd/ava_download.py --only <video_id>   # retry one video
```

Shards are disjoint and together cover all 153 videos. Reruns skip finished videos, so an
interrupted run can just be restarted. Label CSVs are downloaded automatically (small).
Failures don't stop the run: they are printed, written to `failed_<shard>.txt`, and the exit
code is 1. Upload `data/ava/` (labels, videos, audio) to the Drive folder when your shard is done.

Notes:
- The `ava` "val" split is the official `ava_activespeaker_val_v1.0` (its tarball unpacks to a
  folder named `..._test_v1.0`; those 33 videos are val, not a test set).
- 8 videos have labels but are missing from the official `ava_file_names_trainval_v2.1.txt`
  (`20TAGRElvfE 2XeFK-DTSZk a5mEmM6w_ks iK4Y-JKRRAc LgBQlW6OTr0 U6m3kNFjdTs uPJPNPbWMFk
  WwoTG3_OjUg`). They do exist under `trainval/` on S3, so the script finds their extension by
  checking for `.mp4` then `.mkv`.

**Failed downloads:** N/A
