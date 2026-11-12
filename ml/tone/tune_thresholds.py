# argparse handles command-line arguments.
# csv reads the baseline scores and human labels.
# Path handles file paths across operating systems.
import argparse
import csv
from itertools import product
from pathlib import Path

# Import the current thresholds for comparison with tuned thresholds.
from ml.tone.backend import (
    CALM_AROUSAL_MAX,
    CALM_AROUSAL_MIN,
    CALM_VALENCE_THRESHOLD,
    EXCITED_AROUSAL_THRESHOLD,
    EXCITED_VALENCE_THRESHOLD,
    UPSET_AROUSAL_THRESHOLD,
    UPSET_VALENCE_THRESHOLD,
)

# Split by speaker so recordings from the same person
# never appear in both tuning and held-out evaluation.
TUNING_SPEAKERS = {"speaker1", "speaker4"}
HELD_OUT_SPEAKERS = {"speaker2", "speaker3"}

# Human labels correspond to these expected model outputs.
EXPECTED_TAGS = {
    "calm": "calm",
    "excited": "excited",
    "neutral": None,
    "upset": "upset",
}

# Require at least 80% precision when selecting thresholds.
MIN_PRECISION = 0.80

# Candidate score boundaries to test during the grid search.
THRESHOLD_VALUES = [round(i / 100, 2) for i in range(5, 96, 2)]

#Load in and match the data
def load_dataset(results_path: Path, labels_path: Path) -> list[dict]:
    """Load model scores and match them with human-assigned labels."""

    #Read the human labels and index them by audio filename.
    with labels_path.open(newline="", encoding="utf-8-sig") as csvfile:
        reader = csv.DictReader(csvfile)
        labels = {
            row["file"].strip(): {
                "human_label": row["human_label"].strip().lower(),
                "group": (
                    row.get("group", "").strip().lower().replace("_", "-")
                ),
            }
            for row in reader
        }

        #Store each recording with its speaker, human label, and model scores.
        dataset = []

        with results_path.open(newline="", encoding="utf-8-sig") as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                filename = row["file"].strip()

                #Match this recording to its human-assigned label.
                if filename not in labels:
                    raise ValueError(f"Missing human label for {filename}")
                label_info = labels[filename]
                human_label = label_info["human_label"]

                if human_label not in EXPECTED_TAGS:
                    raise ValueError(
                        f"Unexpected human label {human_label!r} "
                        f"for {filename}"
                    )
                # Read the model's scores and speaker identifier.
                dataset.append(
                    {
                        "file": filename,
                        "speaker": row["speaker"].strip().lower(),
                        "human_label": labels[filename],
                        "expected_tag": EXPECTED_TAGS[human_label],
                        "group": label_info["group"],
                        "arousal": float(row["arousal"]),
                        "valence": float(row["valence"]),
                    }
                )
    # Make sure every human-labeled recording has a matching result.
    result_files = {clip["file"] for clip in dataset}
    missing = set(labels) - result_files

    if missing:
        raise ValueError(
            f"{len(missing)} labeled recordings have no matching results."
        )
    return dataset


#Add the threshold classification function
def predict_tag(arousal: float, valence: float, thresholds: dict) -> str | None:
    """Assign an emotion tag using the supplied threshold values."""

    # Check whether the recording meets the excited criteria.
    if (
        arousal > thresholds["excited_arousal"]
        and valence > thresholds["excited_valence"]
    ):
        return "excited"

    # Check whether the recording meets the upset criteria.
    elif (
        arousal > thresholds["upset_arousal"]
        and valence < thresholds["upset_valence"]
    ):
        return "upset"

    # Check whether the recording meets the calm criteria.
    elif (
        thresholds["calm_arousal_min"] < arousal
        < thresholds["calm_arousal_max"]
        and valence > thresholds["calm_valence"]
    ):
        return "calm"

    # Leave the recording untagged if no rule matches.
    return None

#Evaluation function
def evaluate_thresholds(dataset: list[dict], thresholds: dict) -> dict:
    """Calculate precision and coverage for each predicted tag."""

    # Include None as a category so we can evaluate untagged clips too.
    tags = ["excited", "upset", "calm", None]
    metrics = {}

    for tag in tags:
        # Find all recordings that received this predicted tag.
        predicted = [
            clip for clip in dataset
            if predict_tag(
                clip["arousal"],
                clip["valence"],
                thresholds,
            ) == tag
        ]

        # Count how many predictions match the human-assigned emotion.
        correct = sum(
            clip["expected_tag"] == tag
            for clip in predicted
        )

        total = len(predicted)

        # Precision measures how often a predicted tag is correct.
        precision = correct / total if total else None

        # Coverage measures the percentage of all clips receiving this tag.
        coverage = total / len(dataset) if dataset else 0

        metrics[tag if tag is not None else "none"] = {
            "predicted": total,
            "correct": correct,
            "precision": precision,
            "coverage": coverage,
        }

    return metrics

def search_tag_thresholds(dataset: list[dict], tag: str, base_thresholds: dict) -> dict | None:
    """Find thresholds that maximize coverage while maintaining 80% precision."""

    #Store the best threshold combination found
    #None = no combination has met the precision req yet
    best_thresholds = None
    #Tracks how many clips the best combo correctly targets
    best_coverage = 0
    best_precision = 0

    # Test every possible combination of candidate boundaries.
    #Excited and upset each use 2 boundaries: arousal and valence
    #Calm uses three boundaries: min arousal, max arousal, min valence
    if tag == "excited":
        candidates = product(THRESHOLD_VALUES, repeat=2)
    elif tag == "upset":
        candidates = product(THRESHOLD_VALUES, repeat=2)
    elif tag == "calm":
        candidates = product(THRESHOLD_VALUES, repeat=3)
    else:
        #Stop if the function receives an unsupported emotion
        raise ValueError(f"Unsupported tag: {tag}")

    #evaluate each possible combo of threshold vals
    for values in candidates:

        # Build the threshold configuration for this emotion.
        if tag == "excited":
            candidate = {
                "excited_arousal": values[0],
                "excited_valence": values[1],
            }
        elif tag == "upset":
            candidate = {
                "upset_arousal": values[0],
                "upset_valence": values[1],
            }
        else:
            candidate = {
                "calm_arousal_min": values[0],
                "calm_arousal_max": values[1],
                "calm_valence": values[2],
            }

        #A calm arousal range only makes sense when its min is smaller than max
        if tag == "calm" and values[0] >= values[1]:
            continue

        #Combine the canddiate with current thresholds
        thresholds = base_thresholds.copy()
        thresholds.update(candidate)

        #Apply the actual classifier, including its rule priority
        predicted = [
            clip for clip in dataset
            if predict_tag(
                clip["arousal"],
                clip["valence"],
                thresholds,
            ) == tag
        ]
        # Ignore threshold combinations that do not predict any clips.
        if not predicted:
            continue

        #Count how many predicted clips actually have this emotion
        #according to the human-assigned labels.
        correct = sum(
            clip["expected_tag"] == tag
            for clip in predicted
        )

        #Precision = correct predictions / all predictions.
        #Coverage = percentage of the dataset receiving this tag
        precision = correct / len(predicted)
        #Only consider combinations that meet our minimum precision goal
        #Among those, prefer the combination that identifies the most clips
        if precision >= MIN_PRECISION and (
            len(predicted) > best_coverage
            or (
                len(predicted) == best_coverage
                and precision > best_precision
            )
        ):
            #Save combo bc its current best option
            best_thresholds = thresholds = candidate.copy()
            best_coverage = len(predicted)
            best_precision = precision

    #Return best qualifying thresholds
    #If none met the precision req, then return None.
    return best_thresholds

def tune_thresholds(dataset: list[dict]) -> tuple[dict, dict]:
    """Find the best qualifying thresholds for each emotion."""

    #Start with the existing thresholds that the model uses
    #Will be used if no new thresholds meet the intended precision goal.
    tuned_thresholds = get_current_thresholds()

    #Store the search result for each emotion
    #None value no threshold combo met the 80% requirement
    selected_thresholds = {}

    # Search for the best thresholds separately for each emotion.
    for tag in ["excited", "upset", "calm"]:

        # Find the highest-coverage threshold combination
        # that still meets the minimum precision requirement.
        best = search_tag_thresholds(dataset, tag, tuned_thresholds,)

        # Record the result so we can report which emotions
        # did or did not have qualifying threshold combinations.
        selected_thresholds[tag] = best

        # Replace the current thresholds only when a qualifying
        # alternative was found.
        if best is not None:
            tuned_thresholds.update(best)

    # Return both the combined thresholds and individual search results.
    return tuned_thresholds, selected_thresholds


def get_current_thresholds() -> dict:
    """Return the thresholds currently used by the model."""

    # Keep the production thresholds together in one dictionary.
    # This lets us evaluate the existing model and compare it
    # against the thresholds selected by our grid search.
    return {
        "excited_arousal": EXCITED_AROUSAL_THRESHOLD,
        "excited_valence": EXCITED_VALENCE_THRESHOLD,
        "upset_arousal": UPSET_AROUSAL_THRESHOLD,
        "upset_valence": UPSET_VALENCE_THRESHOLD,
        "calm_arousal_min": CALM_AROUSAL_MIN,
        "calm_arousal_max": CALM_AROUSAL_MAX,
        "calm_valence": CALM_VALENCE_THRESHOLD,
    }


def print_metrics(metrics: dict, dataset_name: str) -> None:
    """Print precision and coverage for each predicted emotion."""

    # Print a heading so we know which dataset these results represent.
    print(f"\n{dataset_name} Results")
    print("-" * 65)

    # Display the metrics for each possible model output.
    for tag, values in metrics.items():

        # Convert None into a readable label for untagged recordings.
        display_tag = tag if tag != "none" else "untagged"

        # Show the number of predictions and how many were correct.
        print(
            f"{display_tag:10} | "
            f"Predicted: {values['predicted']:2} | "
            f"Correct: {values['correct']:2}"
        )

        # Precision is undefined when the model makes no predictions.
        if values["precision"] is None:
            precision_text = "N/A"
        else:
            precision_text = f"{values['precision']:.1%}"

        # Coverage shows what percentage of the dataset received this output.
        print(
            f"{'':10} | "
            f"Precision: {precision_text:>6} | "
            f"Coverage: {values['coverage']:.1%}"
        )

    print("-" * 65)


def main() -> None:
    """Run threshold tuning and evaluate the results on held-out speakers."""

    # Set up command-line arguments for the baseline results and human labels.
    parser = argparse.ArgumentParser(
        description="Tune emotion thresholds using speaker-separated data."
    )
    parser.add_argument("results", type=Path, help="Path to baseline results CSV.")
    parser.add_argument(
        "--labels",
        type=Path,
        required=True,
        help="Path to the CSV containing human-assigned labels.",
    )

    args = parser.parse_args()

    # Load the model scores and match each recording with its human label.
    dataset = load_dataset(args.results, args.labels)

    # Use the prepared group labels when they are available.
    if any(clip["group"] for clip in dataset):
        tuning_dataset = [
            clip for clip in dataset
            if clip["group"] == "tuning"
        ]
        held_out_dataset = [
            clip for clip in dataset
            if clip["group"] == "held-out"
        ]

        split_name = "CREMA-D actor groups"

    else:
        # Keep the original speaker split for A5.1.
        tuning_dataset = [
            clip for clip in dataset
            if clip["speaker"] in TUNING_SPEAKERS
        ]
        held_out_dataset = [
            clip for clip in dataset
            if clip["speaker"] in HELD_OUT_SPEAKERS
        ]

        split_name = "A5.1 speakers"

    # Make sure both datasets contain recordings before continuing.
    if not tuning_dataset or not held_out_dataset:
        raise ValueError("The tuning or held-out dataset is empty.")

    # Display the split sizes and the method used to separate speakers.
    print(f"Split method: {split_name}")
    print(f"Total recordings: {len(dataset)}")
    print(f"Tuning recordings: {len(tuning_dataset)}")
    print(f"Held-out recordings: {len(held_out_dataset)}")

    # Search for thresholds using only the tuning speakers.
    tuned_thresholds, selected_thresholds = tune_thresholds(
        tuning_dataset
    )

    # Report which emotions had a qualifying threshold combination.
    print("\nSelected Thresholds")
    print("-" * 65)

    for tag, thresholds in selected_thresholds.items():
        if thresholds is None:
            print(f"{tag}: No combination met the precision requirement.")
        else:
            print(f"{tag}: {thresholds}")

    #Evaluate the tuned thresholds on the same speakers used to select them.
    tuning_metrics = evaluate_thresholds(
        tuning_dataset,
        tuned_thresholds,
    )

    #Report tuning performance before evaluating unseen speakers.
    print_metrics(tuning_metrics, "Tuned Thresholds: Tuning")

    # Evaluate the existing thresholds on the held-out speakers.
    current_metrics = evaluate_thresholds(
        held_out_dataset,
        get_current_thresholds(),
    )

    # Evaluate the tuned thresholds on the exact same held-out recordings.
    tuned_metrics = evaluate_thresholds(
        held_out_dataset,
        tuned_thresholds,
    )

    # Compare the two sets of results using the same evaluation metrics.
    print_metrics(current_metrics, "Current Thresholds: Held-Out")
    print_metrics(tuned_metrics, "Tuned Thresholds: Held-Out")

# Run main() when this file is executed directly as a Python module.
if __name__ == "__main__":
    main()
