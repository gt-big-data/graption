"""Real-time test for Graption's current 95 facial features.

Place this file in ml/common/ next to features.py and face_landmarker.task.
Run from any working directory with:
    python path/to/ml/common/test_features_live.py

Press Esc to exit.
"""

import time
from pathlib import Path

import cv2
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

from features import (
    extract_lip_features,
    extract_face_blendshapes,
    extract_head_ypr,
)


MODEL_PATH = Path(__file__).with_name("face_landmarker.task")


def main():
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Could not find the MediaPipe model at: {MODEL_PATH}\n"
            "Place face_landmarker.task in the same folder as this script, "
            "or update MODEL_PATH."
        )

    options = vision.FaceLandmarkerOptions(
        base_options=python.BaseOptions(
            model_asset_path=str(MODEL_PATH)
        ),
        running_mode=vision.RunningMode.VIDEO,
        output_face_blendshapes=True,
        output_facial_transformation_matrixes=True,
    )

    cam = cv2.VideoCapture(0)
    if not cam.isOpened():
        raise RuntimeError(
            "Could not open webcam. Check that it is connected and not "
            "being used by another application."
        )

    timestamp_ms = 0
    last_timestamp_ms = 0

    try:
        with vision.FaceLandmarker.create_from_options(options) as landmarker:
            while True:
                success, frame = cam.read()
                if not success:
                    print("Could not read a frame from the webcam.")
                    break

                # Mirror the preview, like a selfie camera.
                frame = cv2.flip(frame, 1)
                height, width = frame.shape[:2]

                rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                mp_image = mp.Image(
                    image_format=mp.ImageFormat.SRGB,
                    data=rgb_frame,
                )

                # VIDEO mode requires strictly increasing timestamps.
                timestamp_ms = max(
                    time.monotonic_ns() // 1_000_000,
                    last_timestamp_ms + 1,
                )
                last_timestamp_ms = timestamp_ms

                result = landmarker.detect_for_video(mp_image, timestamp_ms)

                if result.face_landmarks:
                    face_landmarks = result.face_landmarks[0]

                    try:
                        lip_features = extract_lip_features(
                            face_landmarks,
                            image_width=width,
                            image_height=height
                        )

                        if not result.face_blendshapes:
                            raise ValueError(
                                "MediaPipe returned no blendshape results."
                            )

                        blendshape_features = extract_face_blendshapes(
                            result.face_blendshapes[0]
                        )

                        head_pose_features = extract_head_ypr(
                            result.facial_transformation_matrixes[0]
                        )

                        total_features = (
                            lip_features
                            + blendshape_features
                            + head_pose_features
                        )

                        # Display feature counts.
                        lines = [
                            (f"Lip features: {len(lip_features)} / 80", 30),
                            (
                                f"Blendshapes: {len(blendshape_features)} / 12",
                                60,
                            ),
                            (
                                "Head pose (rad): "
                                f"Y {head_pose_features[0]:.2f}  "
                                f"P {head_pose_features[1]:.2f}  "
                                f"R {head_pose_features[2]:.2f}",
                                90,
                            ),
                            (
                                f"Total: {len(total_features)} / 96 "
                                "(95 until loudness is added)",
                                120,
                            ),
                        ]

                        for text, y in lines:
                            cv2.putText(
                                frame,
                                text,
                                (20, y),
                                cv2.FONT_HERSHEY_SIMPLEX,
                                0.58,
                                (0, 255, 0),
                                2,
                                cv2.LINE_AA,
                            )

                        # Print a compact summary approximately once per second.
                        if not hasattr(main, "_last_print_time"):
                            main._last_print_time = 0.0

                        now = time.monotonic()
                        if now - main._last_print_time >= 1.0:
                            print(
                                f"features={len(total_features)} "
                                f"yaw={head_pose_features[0]:.3f}, "
                                f"pitch={head_pose_features[1]:.3f}, "
                                f"roll={head_pose_features[2]:.3f}"
                            )
                            main._last_print_time = now

                    except (ValueError, KeyError, IndexError, cv2.error) as error:
                        cv2.putText(
                            frame,
                            f"Feature error: {str(error)[:75]}",
                            (20, 30),
                            cv2.FONT_HERSHEY_SIMPLEX,
                            0.5,
                            (0, 0, 255),
                            2,
                            cv2.LINE_AA,
                        )
                else:
                    cv2.putText(
                        frame,
                        "No face detected",
                        (20, 30),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.7,
                        (0, 0, 255),
                        2,
                        cv2.LINE_AA,
                    )

                cv2.imshow("Graption - Live Feature Test", frame)

                if cv2.waitKey(1) & 0xFF == 27:  # Esc
                    break

    finally:
        cam.release()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
