# Branch review — 2026-11-15

Reviewed the live GitHub branch inventory and the local commits/diffs for branches
with commits outside the current dashboard branch. This is a review, not a blanket
merge; the working tree contains ongoing meeting-sync work. No remote branches changed.

| Branch | Finding | Decision |
|---|---|---|
| [28-p7-match-each-caption-to-a-speaker](https://github.com/gt-big-data/graption/tree/28-p7-match-each-caption-to-a-speaker) | P7's time-window average and ambiguity margin are already present as `captionSpeaker`, but live camera/caption wiring was absent. | Reuse that helper in `SpeakerScoreBuffer`; capture real per-track scores at segment delivery. No duplicate implementation or cherry-pick needed. |
| [29-p8-save-past-meetings-on-the-phone](https://github.com/gt-big-data/graption/tree/29-p8-save-past-meetings-on-the-phone) | Persistence primitives already present. | Extend existing store/recorder instead of importing a second store. |
| [demo](https://github.com/gt-big-data/graption/tree/demo) | Older real-capture persistence/lifecycle wiring in `LiveSession`; still uses `Someone`, not a trained speaker model. | Current integration retains the existing calibration, ASR fallback, UI and pending-caption drain. A wholesale merge would replace newer app flows without solving speaker attribution. |
| [96-a9-finish-loudness-and-tone-tags-before-training](https://github.com/gt-big-data/graption/tree/96-a9-finish-loudness-and-tone-tags-before-training) | Adds relative loudness, Python/Swift fixtures and custom emotion-to-screen-tag mapping. | Useful next integration for trained ASD. Keep separate: changes `ml/common` feature handling and live event tag contracts, requiring generated-type/parity coordination with the lead. Not needed to save current sound/tone outputs. |
| [a7-tune-tone-thresholds](https://github.com/gt-big-data/graption/tree/a7-tune-tone-thresholds) | Data-driven threshold tuning with speaker-separated evaluation. | Useful offline evaluation tool; do not claim improved live accuracy until recordings and results are reviewed. No runtime change pulled here. |
| [feature/ios-caption-tone-tags](https://github.com/gt-big-data/graption/tree/feature/ios-caption-tone-tags) | Alternative serialized tone request client and delayed card expiry. | Current monitor already delivers asynchronous tone responses. Extend its full-result callback to retain probabilities/scores, avoiding a second socket and waiting up to 30s for tone in the UI. |
| [a10-crema-d](https://github.com/gt-big-data/graption/tree/a10-crema-d) | Dataset download and actor-split training prep. | Training work, not meeting functionality; leave on its branch. |
| [68-a8-stream-server-side-captions-with-whisperkit-fallback](https://github.com/gt-big-data/graption/tree/68-a8-stream-server-side-captions-with-whisperkit-fallback) | Extra research documentation. Actual Mac-ASR fallback code is already present from the other A8 branch. | No additional runtime functionality to import. |
| `P5-AI-meeting-summary-prototype`, `P9-define-the-meeting-export-file-format`, camera/UI/server feature branches | Their useful code is already in the current ancestry; local history also includes equivalent dashboard commits with different merge/cherry-pick SHAs. | Do not re-import or replace the current dashboard. |

No reviewed branch provides a trained active-speaker model. The new `MouthMotionScorer`
is explicitly provisional: unlike the old largest-face stub, different moving mouths
can win different segment windows, but silent lip movement, chewing, tracking loss,
off-camera speech and overlapping speakers remain device-validation cases.

Meeting export/storage changes in this work are v2, with v1 read compatibility.
The live event schema remains v1.3 and `ml/common` is unchanged. Coordinate the
session-export contract update with the platform lead when opening the PR.
