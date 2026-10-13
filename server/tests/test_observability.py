"""Verify bounded log files and cleanup across server restarts."""

import logging
from logging.handlers import RotatingFileHandler

from app.observability import close_logging, configure_logging, logger, record


def test_rotation_and_handler_cleanup(monkeypatch, tmp_path):
    monkeypatch.setenv("TONE_LOG_DIR", str(tmp_path))
    original_handlers = list(logger.handlers)
    handlers = configure_logging(verbose=True)
    try:
        file_handler = next(
            handler for handler in handlers if isinstance(handler, RotatingFileHandler)
        )
        assert file_handler.maxBytes == 5 * 1024 * 1024
        assert file_handler.backupCount == 3
        file_handler.maxBytes = 300
        for _ in range(12):
            record(logging.DEBUG, "rotation_test", "tone-stub-v1")
        assert list(tmp_path.glob("server-*.jsonl.1"))
        assert len(list(tmp_path.glob("server-*.jsonl*"))) <= 4
    finally:
        close_logging(handlers)
    assert logger.handlers == original_handlers
