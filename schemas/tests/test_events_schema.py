"""Validate example payloads (docs/GRAPTION_CONTEXT.md section 5) against events.schema.json."""

import copy
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker

SCHEMA_PATH = Path(__file__).resolve().parents[1] / "events.schema.json"
SCHEMA = json.loads(SCHEMA_PATH.read_text())
VALIDATOR = Draft202012Validator(SCHEMA, format_checker=FormatChecker())

BASE = {"session_id": "s-test", "schema_version": "1.1"}
CAPTION_ID = "3f1c2a9e-8b7d-4c6e-9a01-2b3c4d5e6f70"

CAPTION = {
    **BASE,
    "type": "caption",
    "caption_id": CAPTION_ID,
    "t_start": 11.2,
    "t_end": 13.8,
    "text": "Did someone ring the doorbell?!",
    "speaker_id": "f2",
    "model_versions": {"asr": "whisperkit-base.en", "asd": "asd-v3"},
}

EXAMPLES = {
    "speaker_scores": {
        **BASE,
        "type": "speaker_scores",
        "t": 12.40,
        "faces": [{"face_id": "f2", "p": 0.94, "bbox": [0.1, 0.2, 0.3, 0.4]}],
    },
    "caption": CAPTION,
    "caption_unknown_speaker": {**CAPTION, "speaker_id": "unknown"},
    "sound_event": {
        **BASE,
        "type": "sound_event",
        "t": 12.9,
        "label": "doorbell",
        "confidence": 0.87,
    },
    "tone_request": {
        **BASE,
        "type": "tone_request",
        "caption_id": CAPTION_ID,
        "t_start": 11.2,
        "t_end": 13.8,
        "sample_rate": 16000,
        "audio_b64": "AAABAAIA",
    },
    "caption_log": {**BASE, "type": "caption_log", "caption": CAPTION, "tone_tag": "excited"},
    "caption_log_no_tone": {**BASE, "type": "caption_log", "caption": CAPTION, "tone_tag": None},
    "session_error": {
        **BASE,
        "type": "session_error",
        "code": "invalid_json",
        "message": "Invalid JSON at line 1, column 1: Expecting value",
        "request": "not json",
        "request_encoding": "text",
        "model_version": "tone-stub-v1",
    },
    "tone_result": {
        **BASE,
        "type": "tone_result",
        "caption_id": CAPTION_ID,
        "tag": "happy",
        "probs": {
            "anger": 0.05,
            "disgust": 0.02,
            "fear": 0.03,
            "happy": 0.72,
            "neutral": 0.15,
            "sad": 0.03,
        },
        "model_version": "tone-head-v2",
        "latency_ms": {"recv_to_send": 180},
    },
}


def test_schema_is_valid_draft_2020_12():
    Draft202012Validator.check_schema(SCHEMA)


@pytest.mark.parametrize("name", EXAMPLES)
def test_example_is_valid(name):
    errors = list(VALIDATOR.iter_errors(EXAMPLES[name]))
    assert not errors, [e.message for e in errors]


def _broken(name, mutate):
    event = copy.deepcopy(EXAMPLES[name])
    mutate(event)
    return event


@pytest.mark.parametrize(
    "event",
    [
        _broken("caption", lambda e: e.pop("session_id")),
        _broken("caption", lambda e: e.update(schema_version="2.0")),
        _broken("caption", lambda e: e.update(speaker_id="bob")),
        _broken("caption", lambda e: e.update(caption_id="not-a-uuid")),
        _broken("speaker_scores", lambda e: e["faces"][0].update(p=1.5)),
        _broken("speaker_scores", lambda e: e["faces"][0].update(bbox=[0, 0, 1])),
        _broken("tone_result", lambda e: e["probs"].pop("sad")),
        _broken("tone_request", lambda e: e.update(extra_field=1)),
        _broken("session_error", lambda e: e.pop("request")),
        _broken("session_error", lambda e: e.update(request_encoding="unknown")),
        _broken("tone_request", lambda e: e.update(schema_version="1.0")),
        {**BASE, "type": "not_an_event"},
    ],
)
def test_invalid_events_are_rejected(event):
    assert not VALIDATOR.is_valid(event)
