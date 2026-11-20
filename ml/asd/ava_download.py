"""Download AVA-ActiveSpeaker videos and cut them down to the labeled window.

For each of the 153 videos (120 train + 33 val) this script:
  1. downloads the full movie,
  2. keeps only seconds 900-1800 (the only labeled part) at 15 fps, scaled to at most 720p,
  3. saves the audio of that window as a separate 16 kHz mono WAV,
  4. deletes the full movie.

Outputs (all under ``data/ava/``, which is gitignored; never commit them)::

    labels/{train,val}/<video_id>-activespeaker.csv
    {train,val}/videos/<video_id>.mp4
    {train,val}/audio/<video_id>.wav
    failed_<shard>.txt                      videos that failed (id <TAB> reason)

Usage::

    uv run python ml/asd/ava_download.py --shard 1/4      # one quarter of the videos
    uv run python ml/asd/ava_download.py --dry-run        # list what would be done
    uv run python ml/asd/ava_download.py --only <video_id> [--only <video_id> ...]

Needs ``ffmpeg`` and ``ffprobe`` on PATH (``brew install ffmpeg``). Re-running skips videos
whose outputs already exist, so an interrupted run can simply be restarted.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

S3 = "https://s3.amazonaws.com/ava-dataset"
FILE_NAMES_URL = f"{S3}/annotations/ava_file_names_trainval_v2.1.txt"
LABEL_TARBALLS = {
    "train": f"{S3}/annotations/ava_activespeaker_train_v1.0.tar.bz2",
    "val": f"{S3}/annotations/ava_activespeaker_val_v1.0.tar.bz2",
}
VIDEO_URL = f"{S3}/trainval/{{filename}}"
CSV_SUFFIX = "-activespeaker.csv"

CLIP_START_S = 900  # only minutes 15-30 of each movie are labeled
CLIP_LEN_S = 900
FPS = 15
MAX_W, MAX_H = 1280, 720
AUDIO_HZ = 16_000
DOWNLOAD_RETRIES = 4
MIN_CLIP_S = CLIP_LEN_S - 5  # sanity check on the cut video's duration

DEFAULT_OUT = Path(__file__).resolve().parents[2] / "data" / "ava"


# ---------------------------------------------------------------------------
# Video list
# ---------------------------------------------------------------------------


def _http_get(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=60) as resp, dest.open("wb") as f:
        shutil.copyfileobj(resp, f)


def ensure_labels(out: Path) -> None:
    """Make sure ``out/labels/{train,val}`` hold the per-video CSVs (small tarballs)."""
    for split, url in LABEL_TARBALLS.items():
        dest = out / "labels" / split
        if any(dest.glob(f"*{CSV_SUFFIX}")):
            continue
        print(f"Downloading {split} labels ...", flush=True)
        with tempfile.TemporaryDirectory() as tmp:
            tarball = Path(tmp) / "labels.tar.bz2"
            _http_get(url, tarball)
            extract_dir = Path(tmp) / "x"
            with tarfile.open(tarball) as tar:
                tar.extractall(extract_dir, filter="data")  # refuses unsafe paths
            dest.mkdir(parents=True, exist_ok=True)
            for csv in extract_dir.rglob(f"*{CSV_SUFFIX}"):
                shutil.copy2(csv, dest / csv.name)


def load_file_names(out: Path) -> dict[str, str]:
    """Map video id -> remote filename (``<id>.mp4`` or ``<id>.mkv``)."""
    path = out / "ava_file_names_trainval_v2.1.txt"
    if not path.exists():
        _http_get(FILE_NAMES_URL, path)
    names = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            names[line.rsplit(".", 1)[0]] = line
    return names


def probe_remote_filename(vid: str) -> str:
    """Find the extension of a video missing from the file-name list (8 of the 153 are).

    The official list omits them, but they exist under ``trainval/`` as .mp4 or .mkv.
    """
    for ext in ("mp4", "mkv"):
        req = urllib.request.Request(VIDEO_URL.format(filename=f"{vid}.{ext}"), method="HEAD")
        try:
            urllib.request.urlopen(req, timeout=30).close()
            return f"{vid}.{ext}"
        except urllib.error.HTTPError as e:
            if e.code not in (403, 404):
                raise
    raise SystemExit(f"{vid} has labels but no .mp4/.mkv was found under trainval/")


def list_videos(out: Path) -> list[tuple[str, str, str]]:
    """Return sorted ``(video_id, split, remote_filename)`` for every labeled video."""
    ensure_labels(out)
    names = load_file_names(out)
    videos = []
    for split in LABEL_TARBALLS:
        for csv in sorted((out / "labels" / split).glob(f"*{CSV_SUFFIX}")):
            vid = csv.name[: -len(CSV_SUFFIX)]
            videos.append((vid, split, names.get(vid) or probe_remote_filename(vid)))
    return sorted(videos)


def parse_shard(spec: str) -> tuple[int, int]:
    try:
        k, n = (int(x) for x in spec.split("/"))
    except ValueError:
        raise argparse.ArgumentTypeError(f"--shard must look like 1/4, got {spec!r}") from None
    if not 1 <= k <= n:
        raise argparse.ArgumentTypeError(f"--shard K/N needs 1 <= K <= N, got {spec!r}")
    return k, n


def select_shard(items: list, shard: tuple[int, int]) -> list:
    """Every N-th item starting at K-1: shards are disjoint and together cover everything."""
    k, n = shard
    return items[k - 1 :: n]


# ---------------------------------------------------------------------------
# Per-video work
# ---------------------------------------------------------------------------


def download(url: str, dest: Path) -> None:
    """Download ``url`` to ``dest`` (via ``dest.part``), resuming and retrying on errors."""
    part = dest.with_name(dest.name + ".part")
    part.parent.mkdir(parents=True, exist_ok=True)
    last_err: Exception | None = None
    for attempt in range(1, DOWNLOAD_RETRIES + 1):
        try:
            have = part.stat().st_size if part.exists() else 0
            req = urllib.request.Request(url, headers={"Range": f"bytes={have}-"} if have else {})
            try:
                resp = urllib.request.urlopen(req, timeout=60)
            except urllib.error.HTTPError as e:
                if e.code == 416:  # already fully downloaded
                    part.replace(dest)
                    return
                raise
            with resp:
                resumed = resp.status == 206
                with part.open("ab" if resumed else "wb") as f:
                    shutil.copyfileobj(resp, f, length=1 << 20)
            part.replace(dest)
            return
        except (urllib.error.URLError, OSError, TimeoutError) as e:
            last_err = e
            if isinstance(e, urllib.error.HTTPError) and e.code in (403, 404):
                break  # retrying will not help
            time.sleep(2**attempt)
    raise RuntimeError(f"download failed: {last_err}")


def ffmpeg_cut_command(src: Path, video_tmp: Path, audio_tmp: Path) -> list[str]:
    """One ffmpeg pass: 15 fps <=720p video (no audio) plus a 16 kHz mono WAV.

    ``-ss`` comes after ``-i`` (output option) so the cut is frame accurate. Paths must be
    absolute: some AVA ids start with ``-``.
    """
    window = ["-ss", str(CLIP_START_S), "-t", str(CLIP_LEN_S)]
    scale = (
        f"fps={FPS},scale=w='min({MAX_W},iw)':h='min({MAX_H},ih)'"
        ":force_original_aspect_ratio=decrease:force_divisible_by=2"
    )
    return [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(src),
        *window, "-an", "-vf", scale,
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-pix_fmt", "yuv420p",
        "-movflags", "+faststart", "-f", "mp4", str(video_tmp),
        *window, "-vn", "-ac", "1", "-ar", str(AUDIO_HZ), "-c:a", "pcm_s16le",
        "-f", "wav", str(audio_tmp),
    ]  # fmt: skip


def probe(path: Path) -> dict:
    cmd = [
        "ffprobe", "-v", "error", "-show_entries",
        "format=duration:stream=codec_type,width,height,sample_rate,channels",
        "-of", "json", str(path),
    ]  # fmt: skip
    return json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)


def verify(video: Path, audio: Path) -> None:
    v, a = probe(video), probe(audio)
    dur = float(v["format"]["duration"])
    if dur < MIN_CLIP_S:
        raise RuntimeError(f"cut video is only {dur:.1f}s (movie shorter than 1800s?)")
    s = next(s for s in v["streams"] if s["codec_type"] == "video")
    if s["height"] > MAX_H or s["width"] > MAX_W:
        raise RuntimeError(f"cut video is {s['width']}x{s['height']}, above 720p")
    s = a["streams"][0]
    if int(s["sample_rate"]) != AUDIO_HZ or int(s["channels"]) != 1:
        raise RuntimeError(f"wav is {s['sample_rate']} Hz x{s['channels']}, expected 16k mono")


def process(vid: str, split: str, filename: str, out: Path) -> None:
    video_out = out / split / "videos" / f"{vid}.mp4"
    audio_out = out / split / "audio" / f"{vid}.wav"
    video_out.parent.mkdir(parents=True, exist_ok=True)
    audio_out.parent.mkdir(parents=True, exist_ok=True)
    full = out / "_tmp" / filename
    video_tmp = video_out.with_name(video_out.name + ".part")
    audio_tmp = audio_out.with_name(audio_out.name + ".part")
    try:
        download(VIDEO_URL.format(filename=filename), full)
        cmd = ffmpeg_cut_command(full.resolve(), video_tmp.resolve(), audio_tmp.resolve())
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError(f"ffmpeg failed: {proc.stderr.strip()[-500:]}")
        verify(video_tmp, audio_tmp)
        video_tmp.replace(video_out)
        audio_tmp.replace(audio_out)
    finally:
        # Always drop the full movie and any half-written outputs.
        for p in (full, full.with_name(full.name + ".part"), video_tmp, audio_tmp):
            p.unlink(missing_ok=True)


def is_done(vid: str, split: str, out: Path) -> bool:
    return (out / split / "videos" / f"{vid}.mp4").exists() and (
        out / split / "audio" / f"{vid}.wav"
    ).exists()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--shard", type=parse_shard, help="K/N: handle the K-th of N equal parts")
    ap.add_argument("--only", action="append", metavar="VIDEO_ID", help="only this id (repeatable)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT, help="output dir (default data/ava)")
    ap.add_argument("--dry-run", action="store_true", help="list what would be done and exit")
    args = ap.parse_args(argv)

    if not args.dry_run and not (shutil.which("ffmpeg") and shutil.which("ffprobe")):
        print("ffmpeg/ffprobe not on PATH. Install with: brew install ffmpeg", file=sys.stderr)
        return 2

    out: Path = args.out
    videos = list_videos(out)
    print(f"{len(videos)} labeled videos total")
    if args.shard:
        videos = select_shard(videos, args.shard)
    if args.only:
        unknown = set(args.only) - {v[0] for v in videos}
        if unknown:
            print(f"Unknown ids (or not in this shard): {sorted(unknown)}", file=sys.stderr)
            return 2
        videos = [v for v in videos if v[0] in args.only]
    tag = f"{args.shard[0]}of{args.shard[1]}" if args.shard else "all"
    print(f"This run: {len(videos)} videos (shard {tag})")

    failed: list[tuple[str, str]] = []
    for i, (vid, split, filename) in enumerate(videos, 1):
        prefix = f"[{i}/{len(videos)}] {split}/{vid}"
        if is_done(vid, split, out):
            print(f"{prefix}: already done, skipping")
            continue
        if args.dry_run:
            print(f"{prefix}: would download {filename}")
            continue
        print(f"{prefix}: downloading + cutting ...", flush=True)
        t0 = time.time()
        try:
            process(vid, split, filename, out)
            print(f"{prefix}: ok ({time.time() - t0:.0f}s)")
        except Exception as e:  # keep going; report at the end
            reason = " ".join(str(e).split())
            print(f"{prefix}: FAILED: {reason}", file=sys.stderr)
            failed.append((vid, reason))

    shutil.rmtree(out / "_tmp", ignore_errors=True)
    if failed:
        fail_file = out / f"failed_{tag}.txt"
        fail_file.write_text("".join(f"{v}\t{r}\n" for v, r in failed))
        print(f"\n{len(failed)} FAILED (listed in {fail_file}); rerun to retry:", file=sys.stderr)
        for v, r in failed:
            print(f"  {v}: {r}", file=sys.stderr)
        return 1
    print("\nAll done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
