# ml/common: shared feature spec (Vision team)

`ml/common/features.py` (to be written) is the **one** definition of the per-face, per-frame
feature vector. The iOS FeatureBuilder must match it exactly: same order, same normalization.
Spec: `docs/GRAPTION_CONTEXT.md` §6 (FeatureBuilder) and §8.

| Block | Size | Notes |
|---|---|---|
| Lip landmarks | 80 | 40 pts × (x, y), minus nose tip, ÷ inter-ocular distance |
| Mouth blendshapes | 12 | `jawOpen, mouthClose, mouthFunnel, mouthPucker, mouthLowerDownLeft, mouthLowerDownRight, mouthUpperUpLeft, mouthUpperUpRight, mouthStretchLeft, mouthStretchRight, mouthRollLower, mouthRollUpper` |
| Head pose | 3 | yaw, pitch, roll (radians) |
| Loudness | 1 | frame RMS dBFS minus rolling 30 s median |
| **Total** | **96** | model input `[1, 15, 96]` (15 frames at 15 fps) |

Reference data:
- The 40 unique points of MediaPipe's `FACEMESH_LIPS` (checked against mediapipe 1.0.1), sorted:
  `0, 13, 14, 17, 37, 39, 40, 61, 78, 80, 81, 82, 84, 87, 88, 91, 95, 146, 178, 181, 185, 191,
  267, 269, 270, 291, 308, 310, 311, 312, 314, 317, 318, 321, 324, 375, 402, 405, 409, 415`.
  Pick an order and lock it; Swift uses the same.
- **Undecided:** which landmarks are the nose tip and the eyes (for inter-ocular distance). The doc
  doesn't say. Decide before extracting any training data.

Parity: Python writes small fixtures to `ml/common/fixtures/`; a Swift unit test must reproduce them.
