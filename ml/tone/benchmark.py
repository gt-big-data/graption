
"""Benchmark tone model inference and total prediction latency."""

import argparse
import statistics
import time
from pathlib import Path

import torch

from ml.tone.backend import AudeeringBackend
from ml.tone.baseline import load_audio


def benchmark_backend(
    backend,
    audio,
    sample_rate,
    warmup_runs=5,
    benchmark_runs=30,
):
    """Measure inference-only and total prediction latency."""

    #Print the hardware and benchmark configuration for reference
    print(f"\nDevice: {backend.device}")
    print(f"PyTorch version: {torch.__version__}")
    print(f"Warm-up runs: {warmup_runs}")
    print(f"Benchmark runs: {benchmark_runs}")

    # Warm up the model before collecting measurements.
    #Helps reduce impact of initial model execution overhead
    for _ in range(warmup_runs):
        backend.predict(audio, sample_rate)

    inference_latencies = []
    total_latencies = []

    # Collect repeated measurements (both latency measurements).
    for _ in range(benchmark_runs):
        #Start timing the complete backend prediction
        start = time.perf_counter()

        result = backend.predict(audio, sample_rate)

        #Calculate total prediction time in ms
        total_ms = (time.perf_counter() - start) * 1000

        inference_latencies.append(result["latency_ms"])
        total_latencies.append(total_ms)

    #summary of model's forward-pass latency across all measured runs
    print("\nInference latency (model forward pass):")
    print(f"Average: {statistics.mean(inference_latencies):.2f} ms")
    print(f"Median:  {statistics.median(inference_latencies):.2f} ms")
    print(f"Minimum: {min(inference_latencies):.2f} ms")
    print(f"Maximum: {max(inference_latencies):.2f} ms")

    #summary of total prediction latency, including preprocessing and
    #other operations performed inside backend.predict()
    print("\nTotal prediction latency (backend.predict):")
    print(f"Average: {statistics.mean(total_latencies):.2f} ms")
    print(f"Median:  {statistics.median(total_latencies):.2f} ms")
    print(f"Minimum: {min(total_latencies):.2f} ms")
    print(f"Maximum: {max(total_latencies):.2f} ms")


def main():
    #Define command-line args for audio file and benchmark settings
    parser = argparse.ArgumentParser(
        description="Benchmark tone model latency."
    )

    parser.add_argument(
        "audio_file",
        help="Path to a WAV or MP3 audio file.",
    )

    #Allow number of warmup and measured predictiosn to be customized
    parser.add_argument(
        "--warmup",
        type=int,
        default=5,
        help="Number of warm-up predictions (default: 5).",
    )

    parser.add_argument(
        "--runs",
        type=int,
        default=30,
        help="Number of measured predictions (default: 30).",
    )

    #allow automatic device selection or an explicit hardware override
    parser.add_argument(
        "--device",
        choices=["auto", "cpu", "cuda", "mps"],
        default = "auto",
        help = "Inference device (default: automatic selection).",
    )

    args = parser.parse_args()

    audio_file = Path(args.audio_file)

    #Validate audio file path and supported format before benchmarking
    if not audio_file.exists() or not audio_file.is_file():
        parser.error(f"Audio file does not exist: {audio_file}")

    if audio_file.suffix.lower() not in {".wav", ".mp3"}:
        parser.error("Audio file must be WAV or MP3.")

    #Ensure benchmark configuration contains valid run counts
    if args.warmup < 0:
        parser.error("Warm-up runs cannot be negative.")

    if args.runs < 1:
        parser.error("Benchmark runs must be at least 1.")

    # Load audio once so disk loading is excluded from prediction timing.
    audio, sample_rate = load_audio(audio_file)

    print(f"Audio file: {audio_file.name}")
    print(f"Sample rate: {sample_rate} Hz")

    # Load the model once and reuse it for all measurements.
    backend = AudeeringBackend(device=args.device)

    #Run the benchmark using selected device and configured run counts
    benchmark_backend(
        backend,
        audio,
        sample_rate,
        warmup_runs=args.warmup,
        benchmark_runs=args.runs,
    )


if __name__ == "__main__":
    main()
