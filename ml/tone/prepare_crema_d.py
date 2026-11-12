"""Prepare a speaker-independent CREMA-D subset for tone evaluation."""

import argparse
import csv
import random
import shutil
from collections import defaultdict
from pathlib import Path

#Map CREMA-D emotion codes to Graption's human labels.
EMOTION_LABELS = {
    "HAP": "excited",
    "ANG": "upset",
    "NEU": "neutral",
}

#Use a fixed seed so that selection is reproducible.
RANDOM_SEED = 42

def load_crema_files(source_dir: Path) -> dict:
    """Group selected CREMA-D recordings by actor and emotion."""

    #Store each actor's recordings separately so we can split by speaker.
    actor_files = defaultdict(lambda: defaultdict(list))

    #Look through original dataset for the WAV recordings
    for audio_file in source_dir.glob("*.wav"):
        #CREMA-D filenames follow: ACTOR_UTTERANCE_EMOTION_INTENSITY.wav
        parts = audio_file.stem.split("_")

        #Skip filenames that do not match the expected structure.
        if len(parts) != 4:
            continue

        actor_id, _, emotion, _ = parts

        #Keep only happy, angry, and neutral emotions.
        if emotion not in EMOTION_LABELS:
            continue

        #Group each recording under its actor and emotion
        actor_files[actor_id][emotion].append(audio_file)

    return actor_files

#91 actors, 45 assigned to tuning, 46 to held-out
#no actor appears in both groups
def split_actors(actor_files: dict) -> tuple[set, set]:
    """Split actors into tuning and held-out groups."""

    #Sort actor IDs so the split is reproducible.
    actors = sorted(actor_files.keys())

    #Shuffle actors using a fixed seed for consistency
    random.Random(RANDOM_SEED).shuffle(actors)

    #Assign approximately half of the actors to each group
    midpoint = len(actors) // 2
    tuning_actors = set(actors[:midpoint])
    held_out_actors = set(actors[midpoint:])

    return tuning_actors, held_out_actors

#Select 50 clips per emotion for tuning
#Selects 50 clips per emotion for held out evaluation
#produces 300 recordings total
def select_recordings (
        actor_files: dict,
        tuning_actors: set,
        held_out_actors: set,
        clips_per_emotion: int = 100,
) -> list:
    """Select a subset of recordings for each actor and emotion."""

    selected_files = []

    #Process tuning and held-out groups independently of each other
    for group_name, actors in [
        ("tuning", tuning_actors),
        ("held-out", held_out_actors),
    ]:
        #Select recordings from each emotion separately
        for emotion in EMOTION_LABELS:
            candidates = []

            #Gather recordings belonging to actors in this group.
            for actor_id in sorted(actors):
                candidates.extend(actor_files[actor_id][emotion])

            #Shuffle candidates so that selection isn't based on filename order
            random.Random(
                f"{RANDOM_SEED}_{group_name}_{emotion}"
            ).shuffle(candidates)

            #Divide the target evenly between the two groups.
            target = clips_per_emotion // 2

            #Select the requested number of recordings.
            chosen = candidates[:target]

            #Store the selected recordings and their metadata.
            for audio_file in chosen:
                parts = audio_file.stem.split("_")
                actor_id = parts[0]

                selected_files.append({
                    "source": audio_file,
                    "actor": actor_id,
                    "emotion": emotion,
                    "human_label": EMOTION_LABELS[emotion],
                    "group": group_name,
                })

                #Stop if the group doesn't have enough recordings
                if len(chosen) < target:
                    raise ValueError(
                        f"Not enough {emotion} recordings for {group_name}: "
                        f"needed {target}, found {len(chosen)}"
                    )
    return selected_files


#Need to copy and rename the recordings to match baseline.py
def prepare_output(selected_files: list, output_dir: Path) -> None:
    """Copy selected recordings and create the labels CSV."""

    #Create the output folder if it doesn't exist already
    output_dir.mkdir(parents=True, exist_ok=True)

    labels_path = output_dir / "labels.csv"
    labels = []

    #Track how many clips have been copied for each actor and emotion
    clip_counts = defaultdict(int)

    for item in selected_files:
        actor_id = item["actor"]
        emotion = item["emotion"]
        human_label = item["human_label"]

        # Convert the emotion to the filename prefix expected by baseline.py.
        filename_label = human_label if human_label != "neutral" else "none"

        # Create a unique clip number for this actor and emotion.
        clip_counts[(actor_id, emotion)] += 1
        clip_number = clip_counts[(actor_id, emotion)]

        # Match the label_speaker_number.wav format used by baseline.py.
        new_filename = (
            f"{filename_label}_speaker_{actor_id}_{clip_number:02d}.wav"
        )

        # Copy the original WAV without modifying the source dataset.
        shutil.copy2(item["source"], output_dir / new_filename)

        # Save the original emotion and mapped Graption label.
        labels.append({
            "file": new_filename,
            "speaker": f"speaker_{actor_id}",
            "intended_label": human_label,
            "human_label": human_label,
            "group": item["group"],
        })

    # Write the labels and actor split information to a CSV.
    with open(labels_path, "w", newline="", encoding="utf-8") as csvfile:
        fieldnames = [
            "file",
            "speaker",
            "intended_label",
            "human_label",
            "group",
        ]

        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(labels)

    print(f"Copied {len(labels)} recordings to {output_dir}")
    print(f"Created labels file: {labels_path}")



def main():
    """Run the CREMA-D subset preparation process."""

    # Read the dataset and output locations from command-line arguments.
    parser = argparse.ArgumentParser(
        description="Prepare a balanced CREMA-D subset for Graption."
    )
    parser.add_argument(
        "--source",
        required=True,
        help="Folder containing the original CREMA-D WAV files.",
    )
    parser.add_argument(
        "--output",
        required=True,
        help="Folder where the selected recordings will be copied.",
    )

    args = parser.parse_args()
    source_dir = Path(args.source)
    output_dir = Path(args.output)

    # Check that the original dataset folder exists.
    if not source_dir.is_dir():
        parser.error(f"Source directory does not exist: {source_dir}")

    # Load recordings and separate actors into two groups.
    actor_files = load_crema_files(source_dir)
    tuning_actors, held_out_actors = split_actors(actor_files)

    # Select the same number of recordings per emotion and group.
    selected_files = select_recordings(
        actor_files,
        tuning_actors,
        held_out_actors,
    )

    # Copy the selected audio and generate its labels CSV.
    prepare_output(selected_files, output_dir)

    # Report the actor and recording counts for each group.
    print(f"Tuning actors: {len(tuning_actors)}")
    print(f"Held-out actors: {len(held_out_actors)}")


if __name__ == "__main__":
    main()
