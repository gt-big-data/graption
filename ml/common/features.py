"""The one definition of Graption's per-face, per-frame feature vector.

Spec: docs/GRAPTION_CONTEXT.md §6 (FeatureBuilder) and §8. The iOS mirror is
apps/ios/Packages/GraptionVision/Sources/GraptionVision/FeatureBuilder.swift and must produce
the same numbers; `make_fixtures.py` writes the shared test cases to `fixtures/`.

Changing anything here (order, indices, normalization, the missing-landmarks rule) invalidates
every trained speaker model. Bump FEATURE_SPEC_VERSION, regenerate the fixtures, update the
Swift side, and tell the Vision lead.

Vector layout (96 values), locked:
    [0:80]   lips        40 landmarks x (x, y), minus nose tip, / inter-ocular distance
    [80:92]  blendshapes 12 mouth scores, in BLENDSHAPE_NAMES order
    [92:95]  head pose   yaw, pitch, roll (radians) from the facial transformation matrix
    [95]     loudness    frame RMS dBFS minus the session's rolling 30 s median (computed by
                         the audio side and passed in)
"""

import math
from collections import deque
from collections.abc import Mapping, Sequence

FEATURE_SPEC_VERSION = "features-v1"

# The 40 unique points of MediaPipe's FACEMESH_LIPS, sorted. This order is the lips block order.
LIP_LANDMARKS = [
    0, 13, 14, 17, 37, 39, 40, 61, 78, 80, 81, 82, 84, 87, 88, 91, 95, 146, 178, 181,
    185, 191, 267, 269, 270, 291, 308, 310, 311, 312, 314, 317, 318, 321, 324, 375, 402,
    405, 409, 415,
]
NOSE_TIP_LM = 1
# Iris centers. They exist only in the 478-point mesh (face_landmarker.task outputs it).
LEFT_EYE_LM = 468
RIGHT_EYE_LM = 473
MIN_LANDMARKS = 478

BLENDSHAPE_NAMES = [
    "jawOpen",
    "mouthClose",
    "mouthFunnel",
    "mouthPucker",
    "mouthLowerDownLeft",
    "mouthLowerDownRight",
    "mouthUpperUpLeft",
    "mouthUpperUpRight",
    "mouthStretchLeft",
    "mouthStretchRight",
    "mouthRollLower",
    "mouthRollUpper",
]

LIP_DIM = 2 * len(LIP_LANDMARKS)  # 80
BLENDSHAPE_DIM = len(BLENDSHAPE_NAMES)  # 12
HEAD_POSE_DIM = 3
LOUDNESS_DIM = 1
FEATURE_DIM = LIP_DIM + BLENDSHAPE_DIM + HEAD_POSE_DIM + LOUDNESS_DIM  # 96

# Model input is [1, WINDOW_FRAMES, FEATURE_DIM]: 15 frames at 15 fps.
WINDOW_FRAMES = 15
# Missing-landmarks rule (GRAPTION_CONTEXT.md §6 "Missing landmarks"): a face that is still
# tracked but has no landmarks this frame repeats its last good face features (lips,
# blendshapes, pose) with this frame's loudness, for at most this many consecutive frames.
# One more miss and that face's history starts over. Matches FaceTracker.maxCoastFrames.
MAX_HELD_FRAMES = 2


def feature_labels():
    """A name for each of the 96 positions, e.g. "lips lm61 x", "blend jawOpen", "pose yaw"."""
    labels = []
    for index in LIP_LANDMARKS:
        labels += [f"lips lm{index} x", f"lips lm{index} y"]
    labels += [f"blend {name}" for name in BLENDSHAPE_NAMES]
    labels += ["pose yaw", "pose pitch", "pose roll", "loudness"]
    assert len(labels) == FEATURE_DIM
    return labels


def _xy(point):
    """(x, y) from a MediaPipe landmark, a {"x", "y", ...} dict, or an (x, y, ...) sequence."""
    if isinstance(point, Mapping):
        return float(point["x"]), float(point["y"])
    if hasattr(point, "x"):
        return float(point.x), float(point.y)
    return float(point[0]), float(point[1])


def extract_lip_features(face_landmarks, image_width, image_height):
    """80 values: each lip point minus the nose tip, in pixels, over the inter-ocular distance.

    Landmarks are MediaPipe normalized coordinates of the full frame. Working in pixels keeps
    the result independent of the frame's aspect ratio (portrait vs landscape).
    """
    if len(face_landmarks) < MIN_LANDMARKS:
        raise ValueError(f"need {MIN_LANDMARKS} landmarks, got {len(face_landmarks)}")

    def pixel(index):
        x, y = _xy(face_landmarks[index])
        return x * image_width, y * image_height

    nose_x, nose_y = pixel(NOSE_TIP_LM)
    left_x, left_y = pixel(LEFT_EYE_LM)
    right_x, right_y = pixel(RIGHT_EYE_LM)
    inter_ocular_distance = math.hypot(right_x - left_x, right_y - left_y)
    if not inter_ocular_distance > 0:
        raise ValueError("inter-ocular distance is zero")

    features = []
    for index in LIP_LANDMARKS:
        lip_x, lip_y = pixel(index)
        features.append((lip_x - nose_x) / inter_ocular_distance)
        features.append((lip_y - nose_y) / inter_ocular_distance)
    return features


def extract_face_blendshapes(face_blendshapes):
    """12 scores in BLENDSHAPE_NAMES order.

    Accepts MediaPipe categories (`.category_name`, `.score`), {"name", "score"} dicts (the
    run_face_landmarker.py JSONL), or a {name: score} mapping.
    """
    if isinstance(face_blendshapes, Mapping):
        scores = {name: float(score) for name, score in face_blendshapes.items()}
    else:
        scores = {}
        for category in face_blendshapes:
            if isinstance(category, Mapping):
                scores[category["name"]] = float(category["score"])
            else:
                scores[category.category_name] = float(category.score)
    missing = [name for name in BLENDSHAPE_NAMES if name not in scores]
    if missing:
        raise ValueError(f"missing blendshapes: {missing}")
    return [scores[name] for name in BLENDSHAPE_NAMES]


def extract_head_ypr(facial_transformation_matrix):
    """yaw, pitch, roll (radians) from the 4x4 matrix's rotation, R = Ry(yaw) Rx(pitch) Rz(roll).

    Takes the matrix row-major (`matrix[row][col]`), as MediaPipe Python returns it and as
    iOS `TransformMatrix.value(atRow:column:)` reads it. Only the rotation is used; with
    face crops the translation is in crop space and meaningless.
    """
    def r(row, col):
        return float(facial_transformation_matrix[row][col])

    yaw = math.atan2(r(0, 2), r(2, 2))
    pitch = math.asin(max(-1.0, min(1.0, -r(1, 2))))
    roll = math.atan2(r(1, 0), r(1, 1))
    return [yaw, pitch, roll]


def extract_full_feature_vec(
    face_landmarks,
    face_blendshapes,
    facial_transformation_matrix,
    image_width,
    image_height,
    loudness,
):
    """The full 96-value vector: lips (80), blendshapes (12), head pose (3), loudness (1)."""
    features = (
        extract_lip_features(face_landmarks, image_width, image_height)
        + extract_face_blendshapes(face_blendshapes)
        + extract_head_ypr(facial_transformation_matrix)
        + [float(loudness)]
    )
    assert len(features) == FEATURE_DIM
    return features


def face_features_or_none(
    face_landmarks, face_blendshapes, facial_transformation_matrix, image_width, image_height
):
    """The 95 face values, or None when this frame counts as missing landmarks.

    Missing means no mesh, no blendshapes/matrix, or a mesh the extractors reject. Mirrors
    `FeatureBuilder.faceFeatures(for:frameSize:)` on iOS; feed the result to FeatureHistory.
    """
    if not face_landmarks or face_blendshapes is None or facial_transformation_matrix is None:
        return None
    try:
        return extract_full_feature_vec(
            face_landmarks,
            face_blendshapes,
            facial_transformation_matrix,
            image_width,
            image_height,
            0.0,
        )[: FEATURE_DIM - LOUDNESS_DIM]
    except ValueError:
        return None


class FeatureHistory:
    """One face's last WINDOW_FRAMES vectors, applying the missing-landmarks rule.

    Call `push` once per frame the face is tracked. Pass `face_features` (the first 95 values,
    or a full 96-vector whose loudness is ignored) when the frame has landmarks, or None when
    it doesn't. A frame where the face isn't tracked at all should drop the history (in
    training: a gap in the AVA track), which is the same as `reset`.
    """

    def __init__(self):
        self._frames = deque(maxlen=WINDOW_FRAMES)
        self._last_good = None
        self._held = 0

    def push(self, face_features, loudness):
        if face_features is not None:
            face_part = [float(v) for v in face_features[: FEATURE_DIM - LOUDNESS_DIM]]
            if len(face_part) != FEATURE_DIM - LOUDNESS_DIM:
                raise ValueError(f"need {FEATURE_DIM - LOUDNESS_DIM} face features")
            self._last_good = face_part
            self._held = 0
        elif self._last_good is not None and self._held < MAX_HELD_FRAMES:
            self._held += 1
        else:
            self.reset()
            return
        self._frames.append(self._last_good + [float(loudness)])

    def reset(self):
        self._frames.clear()
        self._last_good = None
        self._held = 0

    @property
    def is_full(self):
        return len(self._frames) == WINDOW_FRAMES

    def window(self):
        """[WINDOW_FRAMES][FEATURE_DIM], oldest first, or None until 15 frames are buffered."""
        return [list(frame) for frame in self._frames] if self.is_full else None


def windows_from_track(frames: Sequence):
    """Applies the rule over one face track: frames are (face_features or None, loudness).

    Returns one entry per frame: the 15-frame window ending there, or None. Training builds
    its stride-1 windows with this so it sees exactly what the phone's model sees.
    """
    history = FeatureHistory()
    out = []
    for face_features, loudness in frames:
        history.push(face_features, loudness)
        out.append(history.window())
    return out
