"""Text-only meeting sync for the development dashboard. Never accepts audio."""

import json
import os
import sqlite3
from datetime import datetime
from hmac import compare_digest
from pathlib import Path
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator

router = APIRouter()
Seconds = Annotated[float, Field(ge=0, allow_inf_nan=False)]


class Record(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Versions(Record):
    asr: str
    asd: str | None = None
    tone: str | None = None


class Probabilities(Record):
    anger: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)] | None = None
    disgust: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)] | None = None
    fear: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)] | None = None
    happy: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)] | None = None
    neutral: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)] | None = None
    sad: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)] | None = None


class Scores(Record):
    arousal: Annotated[float, Field(allow_inf_nan=False)] | None = None
    valence: Annotated[float, Field(allow_inf_nan=False)] | None = None
    dominance: Annotated[float, Field(allow_inf_nan=False)] | None = None


class SoundEvent(Record):
    id: UUID
    label: str
    t: Seconds
    confidence: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]
    model_version: str


class Caption(Record):
    caption_id: UUID
    text: str
    speaker_id: str = Field(pattern=r"^(unknown|f[1-9][0-9]*)$")
    tone_tag: str | None
    tone_probs: Probabilities | None = None
    tone_scores: Scores | None = None
    t_start: Seconds
    t_end: Seconds
    model_versions: Versions


class Meeting(Record):
    id: UUID
    started_at: datetime
    duration: Seconds
    captions: list[Caption]
    title: str | None = Field(default=None, max_length=120)
    sound_events: list[SoundEvent] = Field(default_factory=list)
    deleted_at: datetime | None = None

    @model_validator(mode="after")
    def valid_timings(self):
        if (
            self.started_at.tzinfo is None
            or any(c.t_end < c.t_start or c.t_end > self.duration for c in self.captions)
            or len({c.caption_id for c in self.captions}) != len(self.captions)
        ):
            raise ValueError("Invalid meeting timings or duplicate captions")
        if any(event.t > self.duration for event in self.sound_events):
            raise ValueError("Sound event outside meeting")
        if len({event.id for event in self.sound_events}) != len(self.sound_events):
            raise ValueError("Duplicate sound event")
        if self.deleted_at is not None:
            if self.deleted_at.tzinfo is None:
                raise ValueError("Deletion timestamp needs timezone")
            self.title = None
            self.captions = []
            self.sound_events = []
            self.duration = 0
        return self


class Export(Record):
    export_version: Literal["1", "2"]
    exported_at: datetime
    app_version: str | None = None
    sessions: list[Meeting]


def authorize(authorization: str | None):
    token = os.getenv("TONE_TOKEN", "")
    if (os.getenv("DEPLOY_MODE", "local") != "local" and not token) or (
        token and not compare_digest((authorization or "").encode(), f"Bearer {token}".encode())
    ):
        raise HTTPException(401, "Authentication required")


def database():
    path = Path(os.getenv("MEETINGS_DB", "data/meetings.sqlite3"))
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path)
    connection.execute(
        "CREATE TABLE IF NOT EXISTS meetings (id TEXT PRIMARY KEY, body TEXT NOT NULL)"
    )
    return connection


@router.post("/api/meetings")
def save_meetings(export: Export, authorization: str | None = Header(default=None)):
    authorize(authorization)
    connection = database()
    try:
        with connection:
            connection.execute("BEGIN IMMEDIATE")
            for meeting in export.sessions:
                existing = connection.execute(
                    "SELECT body FROM meetings WHERE id = ?", (str(meeting.id),)
                ).fetchone()
                # A delayed/offline upload must never resurrect a deleted meeting.
                if existing and json.loads(existing[0]).get("deleted_at"):
                    continue
                body = meeting.model_dump(mode="json", exclude_none=True)
                for caption in body["captions"]:
                    caption.setdefault("tone_tag", None)
                connection.execute(
                    "INSERT INTO meetings VALUES (?, ?) "
                    "ON CONFLICT(id) DO UPDATE SET body=excluded.body",
                    (str(meeting.id), json.dumps(body)),
                )
    finally:
        connection.close()
    return {"saved": len(export.sessions)}


@router.get("/api/meetings")
def load_meetings(authorization: str | None = Header(default=None)):
    authorize(authorization)
    connection = database()
    try:
        sessions = []
        for row in connection.execute("SELECT body FROM meetings"):
            # Normalize older database rows that encoded absent version fields as null.
            body = Meeting.model_validate_json(row[0]).model_dump(mode="json", exclude_none=True)
            for caption in body["captions"]:
                caption.setdefault("tone_tag", None)
            sessions.append(body)
    finally:
        connection.close()
    sessions = [meeting for meeting in sessions if not meeting.get("deleted_at")]
    return {
        "export_version": "2",
        "exported_at": datetime.now().astimezone().isoformat(),
        "sessions": sorted(
            sessions, key=lambda s: datetime.fromisoformat(s["started_at"]), reverse=True
        ),
    }
