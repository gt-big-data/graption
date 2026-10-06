"""Local development entry point: uv run uvicorn app.main:app."""

from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

from app.tone import MockToneBackend
from app.ws import router

app = FastAPI(title="Graption tone server")
app.state.tone_backend = MockToneBackend()
app.include_router(router)


@app.get("/health", response_class=PlainTextResponse)
async def health() -> str:
    return "ok"
