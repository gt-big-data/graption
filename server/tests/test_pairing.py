import json
import stat

from fastapi.testclient import TestClient

from app import pairing
from app.main import create_app


def test_pairing_issues_code_only_on_mac_and_persists_credential(monkeypatch, tmp_path):
    monkeypatch.setenv("MEETINGS_DB", str(tmp_path / "meetings.sqlite3"))
    monkeypatch.setenv("GRAPTION_PAIR_URL", "ws://demo-mac.local:8000")
    monkeypatch.setenv("DEPLOY_MODE", "local")
    monkeypatch.delenv("TONE_TOKEN", raising=False)
    app = create_app()
    mac = TestClient(app, base_url="http://localhost:8000", client=("127.0.0.1", 1234))
    ipad = TestClient(app, base_url="http://demo-mac.local:8000", client=("192.168.1.5", 1234))
    captured = []
    make_qr = pairing.segno.make_qr

    def capture_qr(payload, **kwargs):
        captured.append(json.loads(payload))
        return make_qr(payload, **kwargs)

    monkeypatch.setattr(pairing.segno, "make_qr", capture_qr)
    assert mac.get("/api/pairing").status_code == 404
    assert ipad.post("/api/pairing").status_code == 403
    assert ipad.get("/api/pairing").status_code == 403
    assert mac.post("/api/pairing", headers={"Origin": "http://elsewhere"}).status_code == 403
    assert mac.post("/api/pairing", headers={"X-Forwarded-For": "192.168.1.5"}).status_code == 403
    response = mac.post("/api/pairing", headers={"Origin": "http://localhost:8000"})
    assert response.status_code == 200
    assert response.headers["Cache-Control"] == "no-store"
    token = response.json()["token"]
    assert "<svg" in response.json()["qr"]
    assert token not in json.dumps(captured)
    assert captured[0]["url"] == "ws://demo-mac.local:8000"
    code = {"code": captured[0]["code"]}
    assert ipad.post("/api/pairing/connect", json=code).json()["token"] == token
    assert ipad.post("/api/pairing/connect", json=code).status_code == 401
    restored = mac.get("/api/pairing")
    assert restored.json() == {"token": token}
    assert restored.headers["Cache-Control"] == "no-store"
    assert mac.get("/api/pairing", headers={"Origin": "http://elsewhere"}).status_code == 403

    later = TestClient(create_app())
    headers = {"Authorization": f"Bearer {token}"}
    assert later.get("/api/meetings").status_code == 401
    assert later.get("/api/meetings", headers=headers).status_code == 200
    assert stat.S_IMODE(pairing.credential_file().stat().st_mode) == 0o600

    monkeypatch.setattr(pairing, "monotonic", lambda: 0)
    assert mac.post("/api/pairing").json()["token"] == token
    monkeypatch.setattr(pairing, "monotonic", lambda: pairing.PAIRING_LIFETIME + 1)
    assert ipad.post("/api/pairing/connect", json={"code": captured[1]["code"]}).status_code == 401
