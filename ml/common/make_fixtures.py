"""Writes the Python/Swift parity fixtures for the feature spec.

    uv run python ml/common/make_fixtures.py

Output: ml/common/fixtures/features_v1.json. GraptionVision's FeatureBuilderTests reads it and
must reproduce every expected value. Inputs are synthetic but shaped like real MediaPipe output
(478 landmarks, all 52 blendshapes in model order, a rotation+translation matrix), and are
rounded to float32 first, since that's what the iPhone gets from MediaPipe. Expected outputs
are computed in float64 from those float32 inputs.

Re-run after any change to features.py; `ml/common/tests/test_features.py` fails if the
committed file is stale.
"""

import json
import math
import random
import struct
from pathlib import Path

try:
    from ml.common import features as F
except ImportError:  # run as a plain script
    import features as F  # type: ignore[no-redef]

FIXTURE_PATH = Path(__file__).parent / "fixtures" / "features_v1.json"

# MediaPipe's 52 blendshape categories in model output order (index 0 is "_neutral").
ALL_BLENDSHAPES = [
    "_neutral", "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft",
    "browOuterUpRight", "cheekPuff", "cheekSquintLeft", "cheekSquintRight", "eyeBlinkLeft",
    "eyeBlinkRight", "eyeLookDownLeft", "eyeLookDownRight", "eyeLookInLeft", "eyeLookInRight",
    "eyeLookOutLeft", "eyeLookOutRight", "eyeLookUpLeft", "eyeLookUpRight", "eyeSquintLeft",
    "eyeSquintRight", "eyeWideLeft", "eyeWideRight", "jawForward", "jawLeft", "jawOpen",
    "jawRight", "mouthClose", "mouthDimpleLeft", "mouthDimpleRight", "mouthFrownLeft",
    "mouthFrownRight", "mouthFunnel", "mouthLeft", "mouthLowerDownLeft", "mouthLowerDownRight",
    "mouthPressLeft", "mouthPressRight", "mouthPucker", "mouthRight", "mouthRollLower",
    "mouthRollUpper", "mouthShrugLower", "mouthShrugUpper", "mouthSmileLeft", "mouthSmileRight",
    "mouthStretchLeft", "mouthStretchRight", "mouthUpperUpLeft", "mouthUpperUpRight",
    "noseSneerLeft", "noseSneerRight",
]


def f32(value):
    return struct.unpack("f", struct.pack("f", value))[0]


def rotation(yaw, pitch, roll):
    """R = Ry(yaw) Rx(pitch) Rz(roll), the convention extract_head_ypr inverts."""
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    cr, sr = math.cos(roll), math.sin(roll)
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rx = [[1, 0, 0], [0, cp, -sp], [0, sp, cp]]
    rz = [[cr, -sr, 0], [sr, cr, 0], [0, 0, 1]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    return mul(mul(ry, rx), rz)


def make_case(name, rng, width, height, yaw, pitch, roll, loudness):
    # A face roughly centered in the frame, ~20% of its width, with eyes level.
    cx, cy = rng.uniform(0.35, 0.65), rng.uniform(0.35, 0.65)
    half = 0.1
    landmarks = [
        [cx + rng.uniform(-half, half), cy + rng.uniform(-half, half), rng.uniform(-0.05, 0.05)]
        for _ in range(F.MIN_LANDMARKS)
    ]
    landmarks[F.NOSE_TIP_LM][:2] = [cx, cy]
    landmarks[F.LEFT_EYE_LM][:2] = [cx - 0.04, cy - 0.05]
    landmarks[F.RIGHT_EYE_LM][:2] = [cx + 0.04, cy - 0.045]
    landmarks = [[f32(v) for v in point] for point in landmarks]

    blendshapes = [{"name": n, "score": f32(rng.random())} for n in ALL_BLENDSHAPES]

    r = rotation(yaw, pitch, roll)
    translation = [rng.uniform(-5, 5), rng.uniform(-5, 5), rng.uniform(-60, -30)]
    matrix = [r[i] + [translation[i]] for i in range(3)] + [[0.0, 0.0, 0.0, 1.0]]
    matrix = [[f32(v) for v in row] for row in matrix]

    loudness = f32(loudness)
    expected = F.extract_full_feature_vec(landmarks, blendshapes, matrix, width, height, loudness)
    return {
        "name": name,
        "image_width": width,
        "image_height": height,
        "landmarks": landmarks,
        "blendshapes": blendshapes,
        "facial_transformation_matrix": matrix,
        "loudness": loudness,
        "expected": expected,
    }


def face_features_for(frame):
    """Distinct, easy-to-check face features for history frame `frame`."""
    return [frame + j / 1000 for j in range(F.FEATURE_DIM - F.LOUDNESS_DIM)]


def make_history_case():
    # True = landmarks this frame, False = tracked but no landmarks.
    pattern = (
        [True] * 14 + [False]  # 15th frame held: first full window
        + [True] * 2 + [False] * 2  # two held frames: still full
        + [True] + [False] * 3  # third miss in a row: restart
        + [True] * 16
        + [False] * 2 + [True]  # held twice then recovers
    )
    frames = [(face_features_for(i) if ok else None, -float(i)) for i, ok in enumerate(pattern)]
    windows = F.windows_from_track(frames)

    # Encode each window compactly as (face source frame, loudness frame) per row.
    expected = []
    for window in windows:
        if window is None:
            expected.append(None)
            continue
        rows = []
        for row in window:
            rows.append([round(row[0]), round(-row[-1])])
            assert row[:-1] == face_features_for(round(row[0]))
        expected.append(rows)
    return {
        "has_landmarks": pattern,
        "face_features": "frame + j/1000 for j in 0..<95",
        "loudness": "-frame",
        "expected_rows": expected,
    }


def build():
    rng = random.Random(20261105)
    cases = [
        make_case("portrait_frontal", rng, 1080, 1920, 0.05, -0.02, 0.01, -3.5),
        make_case("landscape_turned", rng, 1920, 1080, 0.6, -0.3, 0.2, 7.25),
        make_case("portrait_720_tilted", rng, 720, 1280, -0.9, 0.45, -0.6, 0.0),
    ]
    return {
        "feature_spec_version": F.FEATURE_SPEC_VERSION,
        "feature_dim": F.FEATURE_DIM,
        "window_frames": F.WINDOW_FRAMES,
        "max_held_frames": F.MAX_HELD_FRAMES,
        "lip_landmarks": F.LIP_LANDMARKS,
        "blendshape_names": F.BLENDSHAPE_NAMES,
        "cases": cases,
        "history": make_history_case(),
    }


def render():
    return json.dumps(build(), separators=(",", ":")) + "\n"


if __name__ == "__main__":
    FIXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_PATH.write_text(render())
    print(f"wrote {FIXTURE_PATH}")
