import csv
import json

import pytest

from ml.tone.make_splits import DEFAULT_OUTPUT, make_splits


def write_metadata(path, rows):
    with path.open("w", newline="") as target:
        writer = csv.writer(target)
        writer.writerow(["ActorID", "Sex"])
        writer.writerows(rows)


def test_splits_cover_actors_without_leakage_and_balance_sexes(tmp_path):
    metadata = tmp_path / "demographics.csv"
    rows = [(actor, "Male" if actor < 1049 else "Female") for actor in range(1001, 1092)]
    write_metadata(metadata, rows)
    splits = make_splits(metadata)
    assert [len(splits[key]) for key in ("train", "val", "test")] == [63, 14, 14]
    flattened = [actor for actors in splits.values() for actor in actors]
    assert len(flattened) == len(set(flattened)) == 91
    assert set(flattened) == set(range(1001, 1092))
    for key in ("val", "test"):
        assert sum(actor < 1049 for actor in splits[key]) == 7
    assert make_splits(metadata) == splits
    write_metadata(metadata, reversed(rows))
    assert make_splits(metadata) == splits
    assert make_splits(metadata, seed=43) != splits


def test_rejects_missing_or_duplicate_actors(tmp_path):
    metadata = tmp_path / "demographics.csv"
    write_metadata(metadata, [(1001, "Male")])
    with pytest.raises(ValueError, match="exactly actors"):
        make_splits(metadata)
    write_metadata(metadata, [(1001, "Male"), (1001, "Female")])
    with pytest.raises(ValueError, match="Duplicate actor"):
        make_splits(metadata)


def test_committed_split_has_complete_disjoint_actor_groups():
    splits = json.loads(DEFAULT_OUTPUT.read_text())
    assert set(splits) == {"train", "val", "test"}
    actors = [actor for group in splits.values() for actor in group]
    assert len(actors) == len(set(actors)) == 91
    assert set(actors) == set(range(1001, 1092))
