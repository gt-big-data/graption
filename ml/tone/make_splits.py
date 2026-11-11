"""Create reproducible, actor-disjoint CREMA-D splits from VideoDemographics.csv."""

import argparse
import csv
import json
import random
from pathlib import Path

DEFAULT_OUTPUT = Path(__file__).parent / "splits" / "crema_d_actors.json"


def make_splits(metadata: Path, seed: int = 42) -> dict[str, list[int]]:
    """Reserve seven actors of each sex for each holdout; train on the rest."""
    groups: dict[str, list[int]] = {"Male": [], "Female": []}
    seen: set[int] = set()
    with metadata.open(newline="", encoding="utf-8-sig") as source:
        for row in csv.DictReader(source):
            actor = int(row["ActorID"])
            sex = row["Sex"].strip()
            if actor in seen:
                raise ValueError(f"Duplicate actor: {actor}")
            if sex not in groups:
                raise ValueError(f"Unexpected Sex value for actor {actor}: {sex!r}")
            seen.add(actor)
            groups[sex].append(actor)
    if seen != set(range(1001, 1092)):
        raise ValueError("Metadata must contain exactly actors 1001 through 1091.")
    if len(groups["Male"]) != 48 or len(groups["Female"]) != 43:
        raise ValueError("Expected CREMA-D demographics: 48 male and 43 female actors.")

    rng = random.Random(seed)
    splits: dict[str, list[int]] = {"train": [], "val": [], "test": []}
    for actors in groups.values():
        actors.sort()  # CSV row order must not affect the result.
        rng.shuffle(actors)
        splits["val"].extend(actors[:7])
        splits["test"].extend(actors[7:14])
        splits["train"].extend(actors[14:])
    return {name: sorted(actors) for name, actors in splits.items()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demographics", type=Path, default=Path("data/VideoDemographics.csv"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    splits = make_splits(args.demographics, args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(splits, indent=2) + "\n", encoding="utf-8")
    print(f"Seed {args.seed}: " + ", ".join(f"{k}={len(v)}" for k, v in splits.items()))
    print(f"Saved {args.out}")


if __name__ == "__main__":
    main()
