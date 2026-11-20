"""Render Graption's technology logos as print-size PNGs (Simple Icons, brand colors).

Usage: python3 poster/logos/make_logos.py <path to extracted simple-icons package>
Writes one transparent 1000x1000 PNG per logo plus a labeled letter-size sheet (300 dpi).
"""

import json
import subprocess
import sys
import tempfile
from pathlib import Path

OUT = Path(__file__).parent
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

GROUPS = [
    ("Languages", [("swift", "Swift"), ("python", "Python"), ("typescript", "TypeScript")]),
    ("iPhone app", [("xcode", "Xcode"), ("apple", "Core ML · Vision · SoundAnalysis · SwiftUI"),
                    ("mediapipe", "MediaPipe")]),
    ("Models & ML", [("pytorch", "PyTorch"), ("huggingface", "Hugging Face Transformers"),
                     ("scipy", "SciPy")]),
    ("Server & AI", [("fastapi", "FastAPI"), ("pydantic", "Pydantic"), ("sqlite", "SQLite"),
                     ("deepgram", "Deepgram"), ("openrouter", "OpenRouter"), ("claude", "Claude")]),
    ("Dashboard", [("react", "React"), ("vite", "Vite"), ("vitest", "Vitest"),
                   ("nodedotjs", "Node.js")]),
    ("Tooling", [("uv", "uv"), ("ruff", "Ruff"), ("pytest", "pytest"), ("github", "GitHub"),
                 ("githubactions", "GitHub Actions"), ("githubpages", "GitHub Pages"),
                 ("googledrive", "Google Drive")]),
]


def chrome_png(html: str, out: Path, width: int, height: int, scale: int = 1) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False) as page:
        page.write(html)
    subprocess.run(
        [CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
         "--default-background-color=00000000", f"--force-device-scale-factor={scale}",
         f"--window-size={width},{height}", f"--screenshot={out}", f"file://{page.name}"],
        check=True, capture_output=True,
    )
    Path(page.name).unlink()


def colored(svg: str, hex_color: str) -> str:
    return svg.replace("<svg ", f'<svg fill="#{hex_color}" ', 1)


def main(package: Path) -> None:
    data = json.loads((package / "data/simple-icons.json").read_text())
    icons = data if isinstance(data, list) else data["icons"]
    colors = {icon.get("slug") or icon["title"].lower(): icon["hex"] for icon in icons}
    for slug, *_ in (item for _, items in GROUPS for item in items):
        svg = colored((package / f"icons/{slug}.svg").read_text(), colors[slug])
        page = f"<html><body style='margin:0'><div style='width:1000px;height:1000px;padding:80px;box-sizing:border-box'>{svg.replace('<svg ', '<svg width=840 height=840 ', 1)}</div></body></html>"
        chrome_png(page, OUT / f"{slug}.png", 1000, 1000)

    sections = []
    for group, items in GROUPS:
        tiles = "".join(
            f"<div class=tile>{colored((package / f'icons/{slug}.svg').read_text(), colors[slug]).replace('<svg ', '<svg width=86 height=86 ', 1)}<span>{name}</span></div>"
            for slug, name in items
        )
        sections.append(f"<h2>{group}</h2><div class=grid>{tiles}</div>")
    sheet = f"""<html><head><style>
      body {{ margin:0; background:#fff; font-family:'Helvetica Neue',Arial,sans-serif; color:#1D3A3A }}
      .page {{ width:1275px; height:1650px; padding:70px 80px; box-sizing:border-box }}
      h1 {{ font-size:46px; margin:0 0 6px }} p.sub {{ font-size:20px; color:#52514e; margin:0 0 26px }}
      h2 {{ font-size:22px; margin:26px 0 12px; border-bottom:2px solid #E4DDD3; padding-bottom:6px }}
      .grid {{ display:grid; grid-template-columns:repeat(4,1fr); gap:18px 24px }}
      .tile {{ display:flex; flex-direction:column; align-items:center; gap:10px; text-align:center }}
      .tile span {{ font-size:17px; font-weight:600; line-height:1.25 }}
      p.foot {{ font-size:13px; color:#52514e; margin-top:30px }}
    </style></head><body><div class=page>
      <h1>Built with</h1><p class=sub>The technologies behind Graption</p>
      {''.join(sections)}
      <p class=foot>Also: WhisperKit (on-device Whisper), audEERING wav2vec2 emotion model, CREMA-D and AVA-ActiveSpeaker datasets.
      Logos are trademarks of their owners; icons from Simple Icons (CC0).</p>
    </div></body></html>"""
    chrome_png(sheet, OUT / "built_with_sheet.png", 1275, 1650, scale=2)


if __name__ == "__main__":
    main(Path(sys.argv[1]))
