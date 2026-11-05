import math

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


# Placeholder for loudness value
loudness = 0.0

def extract_lip_features(face_landmarks, image_width, image_height):
    lip_feature_landmarks = []

    nose = face_landmarks[NOSE_TIP_LM]
    left_eye = face_landmarks[LEFT_EYE_LM]
    right_eye = face_landmarks[RIGHT_EYE_LM]

    # Convert to pixel coordinates to avoid aspect ratio issues
    nose_x = nose.x * image_width
    nose_y = nose.y * image_height

    left_eye_x = left_eye.x * image_width
    left_eye_y = left_eye.y * image_height

    right_eye_x = right_eye.x * image_width
    right_eye_y = right_eye.y * image_height

    inter_ocular_distance = math.hypot(right_eye_x - left_eye_x, right_eye_y - left_eye_y)

    for lm in LIP_LANDMARKS:

        lip = face_landmarks[lm]

        lip_x = lip.x * image_width
        lip_y = lip.y * image_height

        x_normal = (lip_x - nose_x) / inter_ocular_distance
        y_normal = (lip_y - nose_y) / inter_ocular_distance

        lip_feature_landmarks.append(x_normal)
        lip_feature_landmarks.append(y_normal)

    return lip_feature_landmarks

def extract_face_blendshapes(face_blendshapes):
    blendshape_scores = {}

    for category in face_blendshapes:
        blendshape_scores[category.category_name] = category.score

    face_blendshape_values = [blendshape_scores[name] for name in BLENDSHAPE_NAMES]

    return face_blendshape_values

def extract_head_ypr(facial_transformation_matrix):
    r = np.asarray(facial_transformation_matrix)[:3, :3]

    yaw = math.atan2(r[0, 2], r[2, 2])
    pitch = math.asin(max(-1.0, min(1.0, -r[1, 2])))
    roll = math.atan2(r[1, 0], r[1, 1])

    return [yaw, pitch, roll]

def extract_full_featureVec(
    face_landmarks,
    face_blendshapes,
    facial_transformation_matrix,
    image_width,
    image_height,
):
    lip_features = extract_lip_features(face_landmarks, image_width, image_height)
    head_ypr = extract_head_ypr(facial_transformation_matrix)
    blendshape_values = extract_face_blendshapes(face_blendshapes)

    # Full 96-value feature vector
    return lip_features + head_ypr + blendshape_values + [loudness]
