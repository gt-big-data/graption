"""Run the synthetic P5 transcripts through a locally running Ollama model."""

import argparse
import json
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="llama3.2:3b")
    parser.add_argument("--output", type=Path, default=Path("data/summary-prototype.json"))
    args = parser.parse_args()
    meetings = json.loads((Path(__file__).parent / "fixtures/meetings.json").read_text())
    results = []
    for meeting in meetings:
        payload = {
            "model": args.model,
            "stream": False,
            "options": {"temperature": 0},
            "prompt": (
                "Summarize this meeting with decisions, action items (owner and deadline if "
                "stated), and open questions. Do not invent facts. If none, say none.\n\n"
                + meeting["transcript"]
            ),
        }
        request = Request(
            "http://127.0.0.1:11434/api/generate",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        try:
            with urlopen(request, timeout=300) as response:
                reply = json.load(response)
            summary = reply["response"]
            if not isinstance(summary, str) or not summary.strip():
                raise ValueError("Model returned an empty summary")
        except (URLError, ValueError, KeyError) as error:
            parser.exit(1, f"Ollama failed for {meeting['id']}: {error}\n")
        results.append({"id": meeting["id"], "model": args.model, "summary": summary})
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(results, indent=2) + "\n")
    print(f"Saved {len(results)} summaries to {args.output}")


if __name__ == "__main__":
    main()
