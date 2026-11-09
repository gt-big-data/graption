"""Replaceable tone backend; the skeleton never infers a tag."""

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class TonePrediction:
    tag: str | None
    probs: dict[str, float]  | None
    scores: dict[str, float] | None
    model_version: str


class ToneBackend(Protocol):
    model_version: str

    async def predict(self, audio: bytes, sample_rate: int) -> TonePrediction:
        """Infer from PCM16 mono little-endian audio without persisting it."""
        ...


class MockToneBackend:
    model_version = "tone-stub-v1"

    async def predict(self, audio: bytes, sample_rate: int) -> TonePrediction:
        # Zero probabilities signal that this stub made no prediction.
        return TonePrediction(
            tag=None,
            probs= {
                "anger": 0.0,
                "disgust": 0.0,
                "fear": 0.0,
                "happy": 0.0,
                "neutral": 0.0,
                "sad": 0.0,
            },
            scores = None,
            model_version=self.model_version,
        )
