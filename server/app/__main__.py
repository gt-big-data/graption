"""Run with python -m app --verbose; leave uvicorn frame logging at INFO."""

import argparse

import uvicorn

from app.main import create_app


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Run the Graption tone server.")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0).")
    parser.add_argument("--port", type=int, default=8000, help="Listen port (default: 8000).")
    parser.add_argument(
        "--verbose", action="store_true", help="Log connection events, requests, and metrics."
    )
    args = parser.parse_args(argv)
    uvicorn.run(create_app(verbose=args.verbose), host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
