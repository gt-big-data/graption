"""Replaceable tone backend; the skeleton never infers a tag."""

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class TonePrediction:
    tag: str | None
    probs: dict[str, float]
    model_version: str


class ToneBackend(Protocol):
    async def predict(self, audio: bytes, sample_rate: int) -> TonePrediction:
        """Infer from PCM16 mono little-endian audio without persisting it."""
        ...


class MockToneBackend:
    async def predict(self, audio: bytes, sample_rate: int) -> TonePrediction:
        # Zero probabilities signal that this stub made no prediction.
        return TonePrediction(
            tag=None,
            probs=dict.fromkeys(("anger", "disgust", "fear", "happy", "neutral", "sad"), 0.0),
            model_version="tone-stub-v1",
        )
