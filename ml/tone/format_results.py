import csv
from pathlib import Path

csv_path = Path("ml/tone/results.csv")

with csv_path.open(newline="", encoding="utf-8") as file:
    for row in csv.DictReader(file):
        tag = row["tag"] or "None"
        print(
            f'- `{row["file"]}`: '
            f'arousal={row["arousal"]}, '
            f'valence={row["valence"]}, '
            f'dominance={row["dominance"]}, '
            f'tag={tag}, '
            f'latency={float(row["latency_ms"]):.2f} ms'
        )
