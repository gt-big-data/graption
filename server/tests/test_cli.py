"""Verify CLI verbosity enables application logs without enabling raw frame logs."""

import pytest

from app.__main__ import main


@pytest.mark.parametrize("args", [[], ["--verbose"], ["--host", "127.0.0.1", "--port", "9000"]])
def test_launcher_flags(monkeypatch, args):
    calls = []
    monkeypatch.setattr(
        "app.__main__.uvicorn.run", lambda *args, **kwargs: calls.append((args, kwargs))
    )
    main(args)
    assert len(calls) == 1
    (server_app,), options = calls[0]
    assert server_app.state.verbose is ("--verbose" in args)
    assert options == {
        "host": "127.0.0.1" if "--host" in args else "0.0.0.0",
        "port": 9000 if "--port" in args else 8000,
        "log_level": "info",
    }


def test_launcher_ignores_removed_environment_flag(monkeypatch):
    monkeypatch.setenv("TONE_VERBOSE", "true")
    calls = []
    monkeypatch.setattr("app.__main__.uvicorn.run", lambda app, **kwargs: calls.append(app))
    main([])
    assert calls[0].state.verbose is False
