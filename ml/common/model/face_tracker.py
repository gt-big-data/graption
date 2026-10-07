import cv2 as cv
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

model_path = r'C:\Users\sanja\OneDrive\Desktop\Graption\graption\ml\common\face_landmarker.task'

BaseOptions = python.BaseOptions
FaceLandmarker = vision.FaceLandmarker
FaceLandmarkerOptions = vision.FaceLandmarkerOptions
FaceLandmarkerResult = vision.FaceLandmarkerResult
VisionRunningMode = vision.RunningMode

# Create a face landmarker instance with the live stream mode:
def print_result(
    result: FaceLandmarkerResult,
    output_image: mp.Image,
    timestamp_ms: int
):
    if result.face_landmarks:
        landmarks = result.face_landmarks[0]

        print(f"Number of landmarks: {len(landmarks)}")
#def print_result(result: FaceLandmarkerResult, output_image: mp.Image, timestamp_ms: int):
#    print('face landmarker result: {}'.format(result))

options = FaceLandmarkerOptions(
    base_options=BaseOptions(model_asset_path=model_path),
    running_mode=VisionRunningMode.LIVE_STREAM,
    result_callback=print_result)

# Start Live Webcam via OpenCV
cam = cv.VideoCapture(0)

timestamp_ms = 0

with FaceLandmarker.create_from_options(options) as landmarker:
  # The landmarker is initialized. Use it here.
  # ...

  while cam.isOpened():
    print("Loop running")

    success, frame = cam.read()
    print("Camera read:", success)

    if not success:
      print("No camera found")
      break

    frame = cv.flip(frame, 1)

    # Convert the frame received from OpenCV to a MediaPipe’s Image object.
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=frame)

    timestamp_ms += 1

    landmarker.detect_async(mp_image, timestamp_ms)

    cv.imshow("Face Landmarker", frame)

    # Click Escape Key to Quit
    if cv.waitKey(1) & 0xFF == 27:
        break

cam.release()
cv.destroyAllWindows()