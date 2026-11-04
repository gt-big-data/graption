"""Validate the portable meeting export contract."""

import copy
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = json.loads((ROOT / "session_export.schema.json").read_text())
EXAMPLE = json.loads((ROOT / "fixtures/session_export.example.json").read_text())
VALIDATOR = Draft202012Validator(SCHEMA, format_checker=FormatChecker())


def test_example():
    Draft202012Validator.check_schema(SCHEMA)
    assert VALIDATOR.is_valid(EXAMPLE)


@pytest.mark.parametrize("change", ["audio", "version", "missing"])
def test_reject_invalid_exports(change):
    export = copy.deepcopy(EXAMPLE)
    if change == "audio":
        export["sessions"][0]["captions"][0]["audio_b64"] = "AA=="
    elif change == "version":
        export["export_version"] = "2"
    else:
        del export["sessions"][0]["captions"][0]["text"]
    assert not VALIDATOR.is_valid(export)
