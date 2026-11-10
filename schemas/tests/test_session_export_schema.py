"""Validate saved-session exports against session_export.schema.json."""

import copy
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker

SCHEMAS_DIR = Path(__file__).resolve().parents[1]
SCHEMA_PATH = SCHEMAS_DIR / "session_export.schema.json"
EXAMPLE_PATH = SCHEMAS_DIR / "fixtures" / "session_export.example.json"

SCHEMA = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
EXAMPLE = json.loads(EXAMPLE_PATH.read_text(encoding="utf-8"))
VALIDATOR = Draft202012Validator(SCHEMA, format_checker=FormatChecker())


def test_schema_is_valid_draft_2020_12():
    Draft202012Validator.check_schema(SCHEMA)


def test_example_is_valid():
    errors = list(VALIDATOR.iter_errors(EXAMPLE))
    assert not errors, [error.message for error in errors]


def test_example_contains_required_cases():
    assert len(EXAMPLE["sessions"]) == 2
    captions = [
        caption
        for session in EXAMPLE["sessions"]
        for caption in session["captions"]
    ]
    assert any(caption["speaker_id"] == "unknown" for caption in captions)
    assert any(caption["tone_tag"] is None for caption in captions)
    assert any(isinstance(caption["tone_tag"], str) for caption in captions)


def test_app_version_is_optional():
    export = copy.deepcopy(EXAMPLE)
    export.pop("app_version", None)
    assert VALIDATOR.is_valid(export)


def test_asr_only_model_versions_are_valid():
    export = copy.deepcopy(EXAMPLE)
    for session in export["sessions"]:
        for caption in session["captions"]:
            caption["model_versions"] = {"asr": "fake-asr-v1"}
    assert VALIDATOR.is_valid(export)


@pytest.mark.parametrize(
    "path",
    [
        (),
        ("sessions", 0),
        ("sessions", 0, "captions", 0),
        ("sessions", 0, "captions", 0, "model_versions"),
    ],
    ids=["export", "session", "caption", "model_versions"],
)
@pytest.mark.parametrize("field", ["audio_b64", "raw_events"])
def test_extra_fields_are_rejected(path, field):
    export = copy.deepcopy(EXAMPLE)
    target = export
    for key in path:
        target = target[key]
    target[field] = "not allowed"
    assert not VALIDATOR.is_valid(export)


@pytest.mark.parametrize("version", ["2", 1])
def test_wrong_export_version_is_rejected(version):
    export = copy.deepcopy(EXAMPLE)
    export["export_version"] = version
    assert not VALIDATOR.is_valid(export)


@pytest.mark.parametrize(
    "field",
    [
        "caption_id",
        "text",
        "speaker_id",
        "tone_tag",
        "t_start",
        "t_end",
        "model_versions",
    ],
)
def test_missing_caption_field_is_rejected(field):
    export = copy.deepcopy(EXAMPLE)
    del export["sessions"][0]["captions"][0][field]
    assert not VALIDATOR.is_valid(export)