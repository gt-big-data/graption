
import argparse
import shutil
import subprocess
from pathlib import Path

#Audio formats accepted by the conversion script
SUPPORTED_FORMATS = {".m4a", ".mp3"}


def convert_audio(input_dir: Path, output_dir: Path):
    #Check that the input path exists and is a directory
    if not input_dir.exists():
        raise FileNotFoundError(
            f"Input directory does not exist: {input_dir}"
        )

    if not input_dir.is_dir():
        raise NotADirectoryError(
            f"Input path is not a directory: {input_dir}"
        )

    #Locate FFmped, which handles converting the original recordings to WAV
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError(
            "FFmpeg was not found. Install FFmpeg and add it to PATH."
        )

    #Collect supported audio files and sort them for consistent processing
    audio_files = sorted(
        path for path in input_dir.iterdir()
        if path.is_file()
        and path.suffix.lower() in SUPPORTED_FORMATS
    )

    #Stop if the input folder doesn't contain any supported recordings
    if not audio_files:
        raise FileNotFoundError(
            f"No supported audio files found in {input_dir}. "
            "Expected .m4a or .mp3 files."
        )

    #Create the output folder if it doesn't already exist
    output_dir.mkdir(parents=True, exist_ok=True)

    #Track successful conversions, skipped files, and failures
    converted = 0
    skipped = 0
    failed = 0

    for audio_file in audio_files:
        #Keep the original filename while changing its extension to WAV
        output_file = output_dir / f"{audio_file.stem}.wav"

        #Skip the recordings that already have a converted WAV file
        if output_file.exists():
            print(f"Already converted, skipping: {audio_file.name}")
            skipped += 1
            continue

        #Build the FFmpeg command to convert recording to 16-bit PCM WAV
        command = [
            ffmpeg,
            "-n",
            "-i", str(audio_file),
            "-vn",
            "-c:a", "pcm_s16le",
            str(output_file),
        ]

        #Run FFmpeg w/o displaying progress output
        #Record error output so that failed conversiosn can be reported
        try:
            subprocess.run(
                command,
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            #Print out the failure and corresponding error message
            print(f"Converted: {audio_file.name}")
            converted += 1

        except subprocess.CalledProcessError as error:
            print(f"Failed: {audio_file.name}")
            print(error.stderr)
            failed += 1

    #Print a summary of the conversion results
    print("\nConversion summary")
    print(f"Newly converted: {converted}")
    print(f"Already existed: {skipped}")
    print(f"Failed: {failed}")
    print(f"WAV output folder: {output_dir}")

    #Report an error if any recordings can't be converted
    if failed:
        raise RuntimeError(f"{failed} audio file(s) failed to convert.")


def main():
    #Defines command-line args for input/output folders
    parser = argparse.ArgumentParser(
        description="Convert new tone test recordings to WAV."
    )
    parser.add_argument(
        "--input",
        default="ml/tone/test_audio",
        help="Folder containing original audio recordings.",
    )
    parser.add_argument(
        "--output",
        default="ml/tone/test_audio_wav",
        help="Folder for converted WAV recordings.",
    )
    args = parser.parse_args()

    #Run the conversion using the supplied paths or default directories
    convert_audio(Path(args.input), Path(args.output))


if __name__ == "__main__":
    main()
