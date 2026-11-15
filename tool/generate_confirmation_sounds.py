#!/usr/bin/env python3
"""Regenerate Butlerly's original, redistributable UI confirmation chimes.

These tones are synthesized independently from mathematical oscillators.
No QuietCog recordings or sample-pack assets are used. Do not replace these
tracked WAV files with third-party samples in the public repository.
"""
from __future__ import annotations

import argparse
import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44_100
# (start seconds, frequency Hz, amplitude, decay seconds)
SOUNDS = {
    "item_created.wav": (
        1.30,
        (
            (0.00, 523.25, 0.25, 0.28),
            (0.15, 659.26, 0.23, 0.31),
            (0.31, 783.99, 0.21, 0.34),
            (0.49, 1046.50, 0.18, 0.37),
        ),
    ),
    "item_updated.wav": (
        1.10,
        (
            (0.00, 659.26, 0.23, 0.30),
            (0.24, 880.00, 0.18, 0.36),
        ),
    ),
}


def make_sound(destination: Path, duration: float, notes: tuple) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    pcm = bytearray()
    count = round(duration * SAMPLE_RATE)
    for sample in range(count):
        t = sample / SAMPLE_RATE
        fade = min(1.0, (duration - t) * 28.0)
        value = 0.0
        for start, frequency, amplitude, decay in notes:
            age = t - start
            if age < 0:
                continue
            attack = 1.0 - math.exp(-180.0 * age)
            envelope = attack * math.exp(-age / decay) * fade
            phase = 2.0 * math.pi * frequency * age
            timbre = (
                math.sin(phase)
                + 0.15 * math.sin(phase * 2.0)
                + 0.05 * math.sin(phase * 3.0)
            )
            value += amplitude * envelope * timbre
        pcm.extend(struct.pack("<h", round(32767 * max(-1.0, min(1.0, value)))))

    with wave.open(str(destination), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "apps/butlerly/assets/audio",
    )
    args = parser.parse_args()
    for filename, (duration, notes) in SOUNDS.items():
        target = args.output_dir / filename
        make_sound(target, duration, notes)
        print(f"{filename}: {duration:.2f}s, mono, 44.1kHz, 16-bit PCM")


if __name__ == "__main__":
    main()
