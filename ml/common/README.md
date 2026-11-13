# ml/common: shared feature spec (Vision team)

`ml/common/features.py` is the **one** definition of the per-face, per-frame feature vector
(`features-v1`). The iOS mirror is `apps/ios/Packages/GraptionVision/Sources/GraptionVision/FeatureBuilder.swift`.
Spec: `docs/GRAPTION_CONTEXT.md` §6 (FeatureBuilder, Missing landmarks) and §8.

| Index | Block | Size | Notes |
|---|---|---|---|
| 0–79 | Lip landmarks | 80 | 40 `FACEMESH_LIPS` pts (sorted) × (x, y), pixels, minus nose tip (1), ÷ inter-ocular distance (irises 468, 473) |
| 80–91 | Mouth blendshapes | 12 | `jawOpen, mouthClose, mouthFunnel, mouthPucker, mouthLowerDownLeft, mouthLowerDownRight, mouthUpperUpLeft, mouthUpperUpRight, mouthStretchLeft, mouthStretchRight, mouthRollLower, mouthRollUpper` |
| 92–94 | Head pose | 3 | yaw, pitch, roll (radians), R = Ry·Rx·Rz from the transformation matrix |
| 95 | Loudness | 1 | RMS dBFS of the last 1/15 s of audio minus the median of the past 30 s (`LoudnessTracker`; rule in §6 Loudness) |
| | **Total** | **96** | model input `[1, 15, 96]` (15 frames at 15 fps) |

Missing landmarks: `FeatureHistory` / `windows_from_track` repeat the last good frame (with
current loudness) for up to 2 frames, then restart the face's history.

## Parity fixtures

```bash
uv run python ml/common/make_fixtures.py   # rewrites fixtures/features_v1.json
uv run pytest ml/common                    # fails if the fixtures are stale
swift test --package-path apps/ios/Packages/GraptionVision   # Swift must reproduce them
```

Loudness has its own fixture, `fixtures/loudness_v1.json` (same command writes it, plus a byte-identical copy in `apps/ios/Packages/GraptionAudio/Tests/GraptionAudioTests/Fixtures/` that the simulator tests bundle; pytest fails if they differ). GraptionAudio
is iOS-only, so its `LoudnessTests` run on the simulator (any installed iPhone simulator name):

```bash
cd apps/ios/Packages/GraptionAudio && xcodebuild test -scheme GraptionAudio \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:GraptionAudioTests/LoudnessTests
```

## See it on a real face

`fixtures/real_faces_v1.json` is real MediaPipe output (the app's `face_landmarker.task`, the
app's 2.2x/256 px face crops) on the repo's placeholder photo, plus Python's 96 numbers.

```bash
# Python vs iPhone, all 96 numbers per face, labeled
GRAPTION_SHOW_FEATURES=1 swift test --package-path apps/ios/Packages/GraptionVision --filter RealFaceFeatureTests

# Re-capture (or try another photo with --image); also writes a PNG of the points used
uv run --no-project --python 3.12 --with mediapipe python ml/common/capture_faces.py --overlay /tmp/overlay.png
```

Changing anything in `features.py` invalidates trained models: bump `FEATURE_SPEC_VERSION`
(both sides), regenerate the fixtures, update the Swift code and §6, and tag the Vision lead.
