"""Application metadata logs only: never attach frames, headers, or exceptions."""

import json
import logging
import os
from dataclasses import dataclass, field
from datetime import UTC, datetime
from logging.handlers import RotatingFileHandler
from pathlib import Path
from time import perf_counter
from uuid import uuid4

logger = logging.getLogger("graption.server")


@dataclass
class ConnectionMetrics:
    model_version: str
    connection_id: str = field(default_factory=lambda: str(uuid4()))
    started_at: float = field(default_factory=perf_counter)
    received_messages: int = 0
    tone_requests: int = 0
    caption_logs: int = 0
    rejected_requests: int = 0
    bytes_received: int = 0
    bytes_sent: int = 0
    inference_ms: float = 0
    send_ms: float = 0

    def emit(self, event: str, **metadata: object) -> None:
        record(
            logging.DEBUG,
            event,
            self.model_version,
            connection_id=self.connection_id,
            **metadata,
        )

    def summarize(self, close_code: int | None) -> None:
        self.emit(
            "connection_closed",
            close_code=close_code,
            duration_ms=round((perf_counter() - self.started_at) * 1000, 3),
            received_messages=self.received_messages,
            tone_requests=self.tone_requests,
            caption_logs=self.caption_logs,
            rejected_requests=self.rejected_requests,
            bytes_received=self.bytes_received,
            bytes_sent=self.bytes_sent,
            inference_ms=round(self.inference_ms, 3),
            send_ms=round(self.send_ms, 3),
        )


class MetadataFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        return json.dumps(
            {
                "timestamp": datetime.fromtimestamp(record.created, UTC).isoformat(),
                "level": record.levelname,
                "event": getattr(record, "event", "server_log"),
                "message": record.getMessage(),
                **getattr(record, "metadata", {}),
            },
            ensure_ascii=True,
        )


def record(level: int, event: str, model_version: str, **metadata: object) -> None:
    logger.log(
        level,
        event,
        extra={"event": event, "metadata": {"model_version": model_version, **metadata}},
    )


def configure_logging(*, verbose: bool = False) -> list[logging.Handler]:
    log_dir = Path(os.getenv("TONE_LOG_DIR", str(Path(__file__).resolve().parents[2] / "logs")))
    log_dir.mkdir(parents=True, exist_ok=True)
    run_id = datetime.now(UTC).strftime("%Y%m%dT%H%M%S.%fZ") + "-" + uuid4().hex
    log_path = log_dir / f"server-{run_id}.jsonl"
    log_path.touch(exist_ok=False)
    handlers: list[logging.Handler] = [
        logging.StreamHandler(),
        RotatingFileHandler(log_path, maxBytes=5 * 1024 * 1024, backupCount=3, encoding="utf-8"),
    ]
    for handler in handlers:
        handler.setFormatter(MetadataFormatter())
        logger.addHandler(handler)
    logger.setLevel(logging.DEBUG if verbose else logging.INFO)
    return handlers


def close_logging(handlers: list[logging.Handler]) -> None:
    for handler in handlers:
        logger.removeHandler(handler)
        handler.close()
