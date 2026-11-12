#argparse allows users to pass CSV file paths through the terminal
#csv reads the baseline results and human labels
#Path handles file paths across operating systems
import argparse
import csv
from pathlib import Path

#import matplotlib to create the scatter plot
import matplotlib.pyplot as plt

#Import the current thresholds so that the plot always reflects
#the actual thresholds being used by the tone backend
from ml.tone.backend import (
    CALM_AROUSAL_MAX,
    CALM_AROUSAL_MIN,
    CALM_VALENCE_THRESHOLD,
    EXCITED_AROUSAL_THRESHOLD,
    EXCITED_VALENCE_THRESHOLD,
    UPSET_AROUSAL_THRESHOLD,
    UPSET_VALENCE_THRESHOLD,
)

#Every human labeled emotion gets a consistent color in the plot
LABEL_COLORS = {
    "calm": "tab:blue",
    "excited": "tab:orange",
    "neutral": "tab:green",
    "upset": "tab:red",
}

#Load in the human labels
def load_labels(path: Path) -> dict[str, str]:
    """Load human labels indexed by audio filename"""

    #Open the labels CSV and read each row as a dictionary
    with path.open(newline="", encoding="utf-8-sig") as csvfile:
        reader = csv.DictReader(csvfile)

        #Make sure CSV contains the columns we need.
        required = {"file", "human_label"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(
                f"{path} must contain columns: file, human_label"
            )

        #Store each filename and its corresponding human-assigned label.
        labels = {}

        for row in reader:
            filename = row["file"].strip()
            human_label = row["human_label"].strip().lower()

            #Prevent duplicate filenames from silently overwriting labels.
            if filename in labels:
                raise ValueError(f"Duplicate filename in labels CSV: {filename}")

            labels[filename] = human_label

    return labels


#Load in the model's arousal and valence scores
def load_results(path: Path, labels: dict[str, str]) -> dict:
    """
    Load the model's arousal and valence scores and match each
    audio clip to its corresponding human-assigned emotional label.

    The baseline CSV contains the model's numerical scores.
    The labels dictionary contains the human-assigned labels.
    Combine using audio filename.
    """

    #Create an empty dictionary for each human emotion
    #Each emotion will store its arousal and valence scores separately
    data = {
        label: {"arousal": [], "valence": []}
        for label in LABEL_COLORS
    }

    #Open the baseline CSV and read each row as a dictionary
    with path.open(newline="", encoding="utf-8-sig") as csvfile:
        reader = csv.DictReader(csvfile)

        #Make sure CSV contains the columns we need.
        required = {"file", "arousal", "valence"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(
                f"{path} must contain columns: file, arousal, valence"
            )

        #Track filenames we've already processed.
        #This prevents duplicate clips from being counted twice
        seen = set()

        #Process each audio clip in the baseline results.
        for row in reader:
            filename = row["file"].strip()

            #A filename should only appear once in the results.
            if filename in seen:
                raise ValueError(
                    f"Duplicate filename in results CSV: {filename}"
                )
            seen.add(filename)

            #Find the human-assigned label for this audio clip.
            #Both CSV files use filenames to identify the same recording.
            if filename not in labels:
                raise ValueError(
                    f"No human label found for {filename}"
                )

            #Match the audio clip to its human-assigned label
            human_label = labels[filename]
            #Make sure the human label is one of the four
            #Emotion categories we expect in the A5.1 dataset
            if human_label not in data:
                raise ValueError(
                    f"Unexpected human label {human_label!r} "
                    f"for {filename}"
                )
            # Convert the model's numerical scores from CSV strings
            # into floating-point numbers so Matplotlib can plot them.
            try:
                arousal = float(row["arousal"])
                valence = float(row["valence"])
            except (TypeError, ValueError) as exc:
                raise ValueError(
                    f"Invalid scores for {filename}"
            ) from exc

            # Store both scores under the human-assigned emotion.
            # This is what allows us to color points by human label
            # instead of by the model's predicted tag.
            data[human_label]["arousal"].append(arousal)
            data[human_label]["valence"].append(valence)

    #Check that every filename in the human labels CSV
    #also appeared in model's baseline results
    missing = set(labels) - seen

    if missing:
        raise ValueError(
            f"{len(missing)} label entries have no matching results. "
            f"Example: {next(iter(missing))}"
        )
    return data


#Create the scatterplot
def create_plot(data: dict, output_path: Path) -> None:
    """Plot arousal vs. valence, grouped by human-assigned emotion."""

    #Create the figure and axes for the scatter plot.
    fig, ax = plt.subplots(figsize=(10, 8))

    #Plot each human emotion in its assigned color.
    for label, scores in data.items():
        if scores["arousal"]:
            ax.scatter(
                scores["arousal"],
                scores["valence"],
                label=f"{label} (n={len(scores['arousal'])})",
                color=LABEL_COLORS[label],
                alpha = 0.8,
                edgecolors="black",
                linewidths=0.5,
                s=65,
            )

    #Draw the current excited thresholds.
    ax.axvline(
        EXCITED_AROUSAL_THRESHOLD,
        color="darkorange",
        linestyle="--",
        label=f"Excited arousal = {EXCITED_AROUSAL_THRESHOLD}",
    )
    ax.axhline(
        EXCITED_VALENCE_THRESHOLD,
        color="darkorange",
        linestyle=":",
        label=f"Excited valence = {EXCITED_VALENCE_THRESHOLD}",
    )
    # Draw the current upset thresholds.
    ax.axvline(
        UPSET_AROUSAL_THRESHOLD,
        color="firebrick",
        linestyle="--",
        label=f"Upset arousal = {UPSET_AROUSAL_THRESHOLD}",
    )
    ax.axhline(
        UPSET_VALENCE_THRESHOLD,
        color="firebrick",
        linestyle=":",
        label=f"Upset valence = {UPSET_VALENCE_THRESHOLD}",
    )
     # Draw the current calm thresholds.
    ax.axvline(
        CALM_AROUSAL_MIN,
        color="royalblue",
        linestyle="-.",
        label=f"Calm arousal min = {CALM_AROUSAL_MIN}",
    )
    ax.axvline(
        CALM_AROUSAL_MAX,
        color="royalblue",
        linestyle="-.",
        label=f"Calm arousal max = {CALM_AROUSAL_MAX}",
    )
    ax.axhline(
        CALM_VALENCE_THRESHOLD,
        color="royalblue",
        linestyle=":",
        label=f"Calm valence = {CALM_VALENCE_THRESHOLD}",
    )
    # Add axis labels, a title, and limits for model scores between 0 and 1.
    ax.set(
        title="Human Labels: Arousal vs. Valence",
        xlabel="Arousal",
        ylabel="Valence",
        xlim=(0, 1),
        ylim=(0, 1),
    )

    # Add a grid and legend, then adjust spacing to prevent overlap.
    ax.grid(alpha=0.2)
    ax.legend(loc="best", fontsize="small")
    fig.tight_layout()

    # Create the output directory if it does not already exist.
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Save the plot as an image.
    fig.savefig(output_path, dpi=200)
    plt.show()

    print(f"Plot saved to {output_path}")

def main() -> None:
    """Load the A5.1 data and generate the score plot."""

    # Define the input CSV files and output image path.
    parser = argparse.ArgumentParser(
        description="Plot model scores by human-assigned emotion."
    )
    parser.add_argument("results", type=Path, help="Baseline results CSV")
    parser.add_argument(
        "--labels",
        type=Path,
        required=True,
        help="Human labels CSV",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("ml/tone/a5_1_score_plot.png"),
        help="Path for the saved plot",
    )
    args = parser.parse_args()

    # Match each model score to its human-assigned label.
    labels = load_labels(args.labels)
    data = load_results(args.results, labels)

    # Generate the scatter plot.
    create_plot(data, args.out)

    total_clips = sum(len(scores["arousal"]) for scores in data.values())
    print(f"Plotted {total_clips} clips across {len(labels)} labeled recordings.")

if __name__ == "__main__":
    main()
