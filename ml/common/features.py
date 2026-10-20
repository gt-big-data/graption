import math
import cv2
import numpy as np

LIP_LANDMARKS = [0, 13, 14, 17, 37, 39, 40, 61, 
                78, 80, 81, 82, 84, 87, 88, 91, 
                95, 146, 178, 181, 185, 191, 267,
                269, 270, 291, 308, 310, 311, 312, 
                314, 317, 318, 321, 324, 375, 402, 
                405, 409, 415]
NOSE_TIP_LM = 1
LEFT_EYE_LM = 468
RIGHT_EYE_LM = 473

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

# Landmarks to help determine Yaw, Pitch, and Roll
YPR_POSE_LANDMARKS = [
    1,    # Nose tip
    152,  # Chin
    33,   # Left eye outer corner
    263,  # Right eye outer corner
    61,   # Left mouth corner
    291   # Right mouth corner
]

# Generated from Chat-GPT. Necessary for cv2.solvePnP() so it has 2D image coordinated (from MediaPipe) and 3D model corodinates (to replicate real face)
# Approximation
FACE_MODEL_POINTS = np.array([
    (0.0, 0.0, 0.0),        # Nose tip
    (0.0, -330.0, -65.0),   # Chin
    (-225.0, 170.0, -135.0), # Left eye outer corner
    (225.0, 170.0, -135.0),  # Right eye outer corner
    (-150.0, -150.0, -125.0), # Left mouth corner
    (150.0, -150.0, -125.0),  # Right mouth corner
], dtype=np.float64)

def extract_lip_features(face_landmarks):
    lip_feature_landmarks = []

    nose = face_landmarks[NOSE_TIP_LM]
    left_eye = face_landmarks[LEFT_EYE_LM]
    right_eye = face_landmarks[RIGHT_EYE_LM]

    inter_ocular_distance = math.hypot(right_eye.x - left_eye.x, right_eye.y - left_eye.y)
    
    for lm in LIP_LANDMARKS:

        # Must normalize feature vector based on distance from camera as well
        # Equation: x_normal = (x_lip - x_nose) / inter_ocular_distance
        #           y_normal = (y_lip - y_nose) / inter_ocular_distance
        
        lip = face_landmarks[lm]
        x_normal = (lip.x - nose.x) / inter_ocular_distance
        y_normal = (lip.y - nose.y) / inter_ocular_distance
        
        lip_feature_landmarks.append(x_normal)
        lip_feature_landmarks.append(y_normal)
    
    return lip_feature_landmarks

def extract_face_blendshapes(face_blendshapes):
    blendshape_scores = {}

    for category in face_blendshapes:
        blendshape_scores[category.category_name] = category.score
    
    face_blendshape_values = [blendshape_scores[name] for name in BLENDSHAPE_NAMES]
    
    return face_blendshape_values

def extract_head_ypr(face_landmarks, image_width, image_height):
    points = []

    for i in YPR_POSE_LANDMARKS:
        x = face_landmarks[i].x * image_width
        y = face_landmarks[i].y * image_height
        points.append([x, y]) 

    image_points = np.array(points, dtype=np.float64)

    focal_length = image_width

    # Necessary for cv2.solvePnP()
    camera_matrix = np.array([
        [focal_length, 0, image_width / 2],
        [0, focal_length, image_height / 2],
        [0, 0, 1],
    ], dtype=np.float64)
    
    # Necessary for cv2.solvePnP()
    distortion_coefficients = np.zeros((4, 1), dtype=np.float64)

    success, rotation_vector, translation_vector = cv2.solvePnP(
        FACE_MODEL_POINTS, #6 assumed 3D facial points (approximation)
        image_points, # Corresponding 6 2D points from face detection (MediaPipe)
        camera_matrix, # Camera intrinsic matrix
        distortion_coefficients, # Distortion coefficients
    )

    rotation_matrix, _ = cv2.Rodrigues(rotation_vector)

    # Convert rotation matrix to Euler angles to radians
    angles_radians = cv2.RQDecomp3x3(rotation_matrix)[0] * np.pi / 180

    pitch, yaw, roll = angles_radians

    return [yaw, pitch, roll]




