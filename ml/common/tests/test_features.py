import json

import pytest

from ml.common import features as F
from ml.common import make_fixtures


def test_layout_is_locked():
    assert (F.LIP_DIM, F.BLENDSHAPE_DIM, F.HEAD_POSE_DIM, F.LOUDNESS_DIM) == (80, 12, 3, 1)
    assert F.FEATURE_DIM == 96
    assert len(set(F.LIP_LANDMARKS)) == 40


# Same structure, floats equal to within 1e-12. Not exact: libm (asin, atan2, hypot) can differ
# in the last bit between macOS and the Linux CI runner.
def _assert_close(actual, expected, path="fixture"):
    if isinstance(expected, float) or isinstance(actual, float):
        assert actual == pytest.approx(expected, rel=1e-12, abs=1e-12), path
    elif isinstance(expected, dict):
        assert isinstance(actual, dict) and actual.keys() == expected.keys(), path
        for key in expected:
            _assert_close(actual[key], expected[key], f"{path}.{key}")
    elif isinstance(expected, list):
        assert isinstance(actual, list) and len(actual) == len(expected), path
        for i, (a, e) in enumerate(zip(actual, expected, strict=True)):
            _assert_close(a, e, f"{path}[{i}]")
    else:
        assert actual == expected, path


def test_committed_fixtures_are_current():
    """Fails if features.py changed without `uv run python ml/common/make_fixtures.py`."""
    committed = json.loads(make_fixtures.FIXTURE_PATH.read_text())
    _assert_close(json.loads(make_fixtures.render()), committed)


def test_block_order_lips_blendshapes_pose_loudness():
    case = json.loads(make_fixtures.FIXTURE_PATH.read_text())["cases"][1]
    vec = case["expected"]
    scores = {b["name"]: b["score"] for b in case["blendshapes"]}
    assert vec[80:92] == [scores[n] for n in F.BLENDSHAPE_NAMES]
    assert vec[92:95] == pytest.approx([0.6, -0.3, 0.2], abs=1e-6)
    assert vec[95] == case["loudness"]


@pytest.mark.parametrize("ypr", [(0.0, 0.0, 0.0), (0.6, -0.3, 0.2), (-1.2, 0.7, 2.5)])
def test_head_pose_inverts_rotation(ypr):
    r = make_fixtures.rotation(*ypr)
    matrix = [row + [0.0] for row in r] + [[0, 0, 0, 1]]
    assert F.extract_head_ypr(matrix) == pytest.approx(list(ypr), abs=1e-12)


def test_lips_ignore_aspect_ratio():
    case = json.loads(make_fixtures.FIXTURE_PATH.read_text())["cases"][0]
    w, h = case["image_width"], case["image_height"]
    # The same face in pixels, re-normalized to a frame twice as wide.
    stretched = [[x / 2, y, z] for x, y, z in case["landmarks"]]
    a = F.extract_lip_features(case["landmarks"], w, h)
    b = F.extract_lip_features(stretched, 2 * w, h)
    assert a == pytest.approx(b, abs=1e-12)


def test_rejects_bad_input():
    with pytest.raises(ValueError):
        F.extract_lip_features([[0.5, 0.5]] * 468, 100, 100)
    with pytest.raises(ValueError):
        F.extract_lip_features([[0.5, 0.5]] * 478, 100, 100)  # eyes coincide
    with pytest.raises(ValueError):
        F.extract_face_blendshapes({"jawOpen": 0.1})


def test_missing_landmarks_rule():
    good = [1.0] * 95
    h = F.FeatureHistory()
    for _ in range(14):
        h.push(good, 0.0)
    h.push(None, 5.0)  # held: repeats face features, current loudness
    window = h.window()
    assert window is not None and window[-1] == good + [5.0]
    h.push(None, 0.0)
    assert h.is_full
    h.push(None, 0.0)  # third consecutive miss: start over
    assert h.window() is None and not h.is_full
    h.push(None, 0.0)  # nothing to hold yet
    assert h.window() is None


def test_never_holds_before_first_good_frame():
    assert F.windows_from_track([(None, 0.0)] * 20) == [None] * 20


def test_face_features_or_none():
    case = json.loads(make_fixtures.FIXTURE_PATH.read_text())["cases"][0]
    args = (case["landmarks"], case["blendshapes"], case["facial_transformation_matrix"])
    size = (case["image_width"], case["image_height"])
    assert F.face_features_or_none(*args, *size) == pytest.approx(case["expected"][:95], abs=1e-12)
    assert F.face_features_or_none([], case["blendshapes"], args[2], *size) is None
    assert F.face_features_or_none(args[0], None, args[2], *size) is None
    assert F.face_features_or_none(args[0], [], args[2], *size) is None


def test_real_faces_fixture():
    """Real MediaPipe output (capture_faces.py): Python still computes the saved numbers."""
    real = json.loads((make_fixtures.FIXTURE_PATH.parent / "real_faces_v1.json").read_text())
    assert real["labels"] == F.feature_labels()
    assert real["faces"]
    for face in real["faces"]:
        vec = F.extract_full_feature_vec(
            face["landmarks"], face["blendshapes"], face["facial_transformation_matrix"],
            real["image_width"], real["image_height"], real["loudness"],
        )
        assert vec == pytest.approx(face["expected"], abs=1e-12)


def test_doc_position_map_matches_code():
    """docs/GRAPTION_CONTEXT.md §6 lists every feature position; keep it in sync."""
    doc = (make_fixtures.FIXTURE_PATH.parents[3] / "docs/GRAPTION_CONTEXT.md").read_text()
    assert f"**Feature position map (`{F.FEATURE_SPEC_VERSION}`).**" in doc
    for k, landmark in enumerate(F.LIP_LANDMARKS):
        assert f"| {2 * k}, {2 * k + 1} | {landmark} |" in doc, f"lip point {landmark}"
    for i, name in enumerate(F.BLENDSHAPE_NAMES):
        assert f"{80 + i} `{name}`" in doc, name
    assert "92 yaw, 93 pitch, 94 roll" in doc
    assert "nose tip = **1**" in doc and "**468** and **473**" in doc
