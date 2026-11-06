"""Runs real MediaPipe on a photo the way the app does and saves the faces as a parity fixture.

    uv run --no-project --python 3.12 --with mediapipe python ml/common/capture_faces.py

(MediaPipe isn't a workspace dependency yet, so it comes from a throwaway env.)

Defaults: the repo's live-video placeholder photo and the app's face_landmarker.task. Writes:
  - ml/common/fixtures/real_faces_v1.json: raw MediaPipe output per face (landmarks,
    blendshapes, matrix) plus the 96 numbers Python computes from it. FeatureBuilderTests
    feeds the same raw output to the Swift FeatureBuilder and requires the same numbers.
  - an overlay PNG (path printed) showing which landmarks the features use, numbered by
    feature index.

Pipeline, matching the app's `faceCrops` mode (GRAPTION_CONTEXT.md §6):
  1. Find faces. The app uses Apple Vision boxes; here, MediaPipe on overlapping tiles stands
     in (its bundled detector misses small faces on the full frame, which is why the app crops).
  2. For each face: a square crop 2.2x the face size, shifted to stay inside the frame,
     resized to 256x256, MediaPipe IMAGE mode with numFaces = 2, keep the mesh whose nose is
     nearest the crop center, map landmarks back to full-frame normalized coordinates.
"""

import argparse
import json
import math
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))
from ml.common import features as F  # noqa: E402

DEFAULT_IMAGE = (
    REPO / "apps/ios/Packages/GraptionUI/Sources/GraptionUI/Resources/Media.xcassets"
    "/LiveVideoPlaceholder.imageset/live-video-placeholder.jpg"
)
DEFAULT_MODEL = REPO / "apps/ios/Graption/face_landmarker.task"
FIXTURE_PATH = REPO / "ml/common/fixtures/real_faces_v1.json"
CROP_SCALE = 2.2  # FaceCaptureEngine.cropScale
CROP_SIDE = 256  # FaceCaptureEngine.cropSide


def landmarker(model, num_faces):
    options = mp.tasks.vision.FaceLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(model)),
        running_mode=mp.tasks.vision.RunningMode.IMAGE,
        num_faces=num_faces,
        min_face_detection_confidence=0.5,
        min_face_presence_confidence=0.5,
        output_face_blendshapes=True,
        output_facial_transformation_matrixes=True,
    )
    return mp.tasks.vision.FaceLandmarker.create_from_options(options)


def run(detector, rgb, x0, y0, side):
    """MediaPipe on the square [x0, x0+side) x [y0, y0+side), resized to CROP_SIDE."""
    crop = cv2.resize(rgb[y0 : y0 + side, x0 : x0 + side], (CROP_SIDE, CROP_SIDE),
                      interpolation=cv2.INTER_LINEAR)
    return detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=crop.copy()))


def find_face_boxes(detector, rgb):
    """Rough face boxes (pixels) from MediaPipe on overlapping tiles."""
    height, width = rgb.shape[:2]
    boxes = []
    for side in (240, 360, 520):
        step = side // 3
        for y0 in range(0, max(height - side, 0) + 1, step):
            for x0 in range(0, max(width - side, 0) + 1, step):
                for face in run(detector, rgb, x0, y0, side).face_landmarks:
                    xs = [x0 + p.x * side for p in face]
                    ys = [y0 + p.y * side for p in face]
                    box = (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))
                    cx, cy = box[0] + box[2] / 2, box[1] + box[3] / 2
                    # Skip faces cut by the tile edge, and repeats of a face already found.
                    if min(xs) < x0 + 2 or min(ys) < y0 + 2:
                        continue
                    if max(xs) > x0 + side - 2 or max(ys) > y0 + side - 2:
                        continue
                    if any(math.hypot(cx - (b[0] + b[2] / 2), cy - (b[1] + b[3] / 2))
                           < max(b[2], b[3]) / 2 for b in boxes):
                        continue
                    boxes.append(box)
    return sorted(boxes, key=lambda b: b[0])


def app_crop_mesh(detector, rgb, box):
    """The app's faceCrops step for one box (FaceCaptureEngine.landmarks(around:in:))."""
    height, width = rgb.shape[:2]
    face_side = max(box[2], box[3])
    side = min(int(face_side * CROP_SCALE), width, height)
    origin_x = min(max(int(box[0] + box[2] / 2) - side // 2, 0), width - side)
    origin_y = min(max(int(box[1] + box[3] / 2) - side // 2, 0), height - side)
    result = run(detector, rgb, origin_x, origin_y, side)

    best = min(
        range(len(result.face_landmarks)),
        key=lambda i: math.hypot(result.face_landmarks[i][1].x - 0.5,
                                 result.face_landmarks[i][1].y - 0.5),
        default=None,
    )
    if best is None:
        return None
    nose = result.face_landmarks[best][1]
    if math.hypot(nose.x - 0.5, nose.y - 0.5) >= 0.25:
        return None

    def f32(v):  # the iPhone gets float32 from MediaPipe
        return float(np.float32(v))

    landmarks = [
        [f32((origin_x + p.x * side) / width), f32((origin_y + p.y * side) / height),
         f32(p.z * side / width)]
        for p in result.face_landmarks[best]
    ]
    blendshapes = [{"name": c.category_name, "score": f32(c.score)}
                   for c in result.face_blendshapes[best]]
    matrix = [[f32(v) for v in row] for row in result.facial_transformation_matrixes[best]]
    return {"crop": [origin_x, origin_y, side], "landmarks": landmarks,
            "blendshapes": blendshapes, "facial_transformation_matrix": matrix}


def draw_overlay(bgr, faces, path):
    """Zoomed mouth of each face with the lip points labeled by feature index."""
    panels = []
    height, width = bgr.shape[:2]
    for face in faces:
        lm = face["landmarks"]
        px = [(p[0] * width, p[1] * height) for p in lm]
        used = [px[i] for i in F.LIP_LANDMARKS + [F.NOSE_TIP_LM, F.LEFT_EYE_LM, F.RIGHT_EYE_LM]]
        x_min, x_max = min(p[0] for p in used), max(p[0] for p in used)
        y_min, y_max = min(p[1] for p in used), max(p[1] for p in used)
        pad = 0.25 * max(x_max - x_min, y_max - y_min)
        x0, y0 = max(int(x_min - pad), 0), max(int(y_min - pad), 0)
        x1, y1 = min(int(x_max + pad), width), min(int(y_max + pad), height)
        zoom = 700 / max(x1 - x0, y1 - y0)
        panel = cv2.resize(bgr[y0:y1, x0:x1], None, fx=zoom, fy=zoom,
                           interpolation=cv2.INTER_CUBIC)

        def at(p, x0=x0, y0=y0, zoom=zoom):
            return int((p[0] - x0) * zoom), int((p[1] - y0) * zoom)

        for idx, name, color in ((F.NOSE_TIP_LM, "nose (origin)", (0, 200, 255)),
                                 (F.LEFT_EYE_LM, "eye 468", (255, 160, 0)),
                                 (F.RIGHT_EYE_LM, "eye 473", (255, 160, 0))):
            cv2.circle(panel, at(px[idx]), 7, color, -1)
            cv2.putText(panel, name, (at(px[idx])[0] + 9, at(px[idx])[1] - 9),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
        cv2.line(panel, at(px[F.LEFT_EYE_LM]), at(px[F.RIGHT_EYE_LM]), (255, 160, 0), 2)
        for k, idx in enumerate(F.LIP_LANDMARKS):
            p = at(px[idx])
            cv2.circle(panel, p, 4, (60, 255, 60), -1)
            # Feature index of this point's x (y is the next index).
            cv2.putText(panel, str(2 * k), (p[0] + 4, p[1] - 4), cv2.FONT_HERSHEY_SIMPLEX,
                        0.38, (255, 255, 255), 1)
        cv2.putText(panel, face["name"], (10, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.9,
                    (255, 255, 255), 2)
        panels.append(panel)
    side = max(p.shape[0] for p in panels)
    panels = [cv2.copyMakeBorder(p, 0, side - p.shape[0], 0, 10, cv2.BORDER_CONSTANT)
              for p in panels]
    cv2.imwrite(str(path), cv2.hconcat(panels))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--image", type=Path, default=DEFAULT_IMAGE)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--output", type=Path, default=FIXTURE_PATH)
    parser.add_argument("--overlay", type=Path, default=Path("face_features_overlay.png"))
    args = parser.parse_args()

    bgr = cv2.imread(str(args.image))
    if bgr is None:
        raise SystemExit(f"can't read {args.image}")
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    height, width = rgb.shape[:2]

    with landmarker(args.model, 1) as finder:
        boxes = find_face_boxes(finder, rgb)
    with landmarker(args.model, 2) as detector:
        meshes = [app_crop_mesh(detector, rgb, box) for box in boxes]

    faces = []
    for mesh in meshes:
        if mesh is None:
            continue
        mesh["name"] = f"face{len(faces) + 1}"
        mesh["expected"] = F.extract_full_feature_vec(
            mesh["landmarks"], mesh["blendshapes"], mesh["facial_transformation_matrix"],
            width, height, 0.0,
        )
        faces.append(mesh)
    if not faces:
        raise SystemExit("no faces found")

    fixture = {
        "feature_spec_version": F.FEATURE_SPEC_VERSION,
        "source_image": str(args.image.resolve().relative_to(REPO)),
        "mediapipe_version": mp.__version__,
        "image_width": width,
        "image_height": height,
        "loudness": 0.0,
        "labels": F.feature_labels(),
        "faces": faces,
    }
    args.output.write_text(json.dumps(fixture, separators=(",", ":")) + "\n")
    draw_overlay(bgr, faces, args.overlay)
    print(f"{len(faces)} faces -> {args.output}\noverlay -> {args.overlay.resolve()}")
    labels = F.feature_labels()
    for face in faces:
        print(f"\n{face['name']} (crop x,y,side = {face['crop']})")
        for i in (0, 1, 80, 81, 92, 93, 94, 95):
            print(f"  [{i:2d}] {labels[i]:<22} {face['expected'][i]: .6f}")


if __name__ == "__main__":
    main()
