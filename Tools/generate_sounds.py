#!/usr/bin/env python3
"""
Dove Hunt sound-effect generator.

Synthesizes the companion app's retro sound effects as 16-bit mono WAV files and writes
them into doveHunt/Sounds/ (bundled with the app target automatically).

Usage (from the repo root):
    python3 -I Tools/generate_sounds.py

Pure standard library. Every sound is seeded, so output is stable between runs.
"""

import math
import os
import random
import struct
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT_DIR = os.path.join(ROOT, "doveHunt", "Sounds")
RATE = 44_100


def write_wav(name, samples, peak=0.9):
    """Normalizes to `peak` and writes a 16-bit mono WAV."""
    top = max(1e-9, max(abs(s) for s in samples))
    data = b"".join(struct.pack("<h", int(max(-1, min(1, s / top * peak)) * 32767)) for s in samples)
    with wave.open(os.path.join(OUTPUT_DIR, f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(data)


def low_pass(samples, cutoff):
    """One-pole low-pass filter."""
    alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    out, y = [], 0.0
    for s in samples:
        y += alpha * (s - y)
        out.append(y)
    return out


def high_pass(samples, cutoff):
    lp = low_pass(samples, cutoff)
    return [s - l for s, l in zip(samples, lp)]


def bitcrush(samples, levels):
    """Quantizes amplitude for a touch of 8-bit grit."""
    return [round(s * levels) / levels for s in samples]


def gunshot(rng):
    """A punchy shotgun blast: a bright noise crack over a deep, falling boom."""
    n = int(RATE * 0.55)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    crack = low_pass(noise, 5200)
    body = low_pass(noise, 900)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        freq = 40 + 55 * math.exp(-t / 0.05)
        phase += 2 * math.pi * freq / RATE
        boom = math.sin(phase) * math.exp(-t / 0.13)
        out.append(
            crack[i] * math.exp(-t / 0.018) * 1.2
            + body[i] * math.exp(-t / 0.09) * 0.9
            + boom * 0.9
        )
    return bitcrush(out, 48)


def squawk(rng):
    """A harsh, falling bird squawk with a fluttering vibrato."""
    n = int(RATE * 0.34)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        progress = t / 0.34
        freq = 1350 - 650 * progress + 140 * math.sin(2 * math.pi * 33 * t)
        phase += 2 * math.pi * freq / RATE
        # Square-ish tone (rich in harmonics) blended with a little breath noise.
        tone = math.tanh(3.5 * math.sin(phase)) * 0.8 + math.sin(2 * phase) * 0.25
        breath = rng.uniform(-1, 1) * 0.18
        envelope = min(1, t / 0.012) * math.exp(-t / 0.16) * (1 - 0.35 * math.sin(2 * math.pi * 14 * t) ** 2)
        out.append((tone + breath) * envelope)
    return bitcrush(low_pass(out, 4200), 64)


def grass_step(rng, pitch):
    """A soft, crunchy rustle of boots in grass: a cluster of tiny filtered noise grains."""
    n = int(RATE * 0.16)
    out = [0.0] * n
    for _ in range(rng.randint(9, 14)):
        start = int(rng.uniform(0, 0.07) * RATE)
        length = int(rng.uniform(0.008, 0.02) * RATE)
        amp = rng.uniform(0.3, 1.0)
        for j in range(length):
            if start + j < n:
                out[start + j] += rng.uniform(-1, 1) * amp * (1 - j / length)
    shaped = high_pass(low_pass(out, 3600 * pitch), 700 * pitch)
    # A faint low thud from the heel.
    for i in range(n):
        t = i / RATE
        shaped[i] = shaped[i] * math.exp(-t / 0.05) + math.sin(2 * math.pi * 95 * t) * math.exp(-t / 0.02) * 0.25
    return shaped


def wood_step(rng, pitch):
    """A hollow knock of a boot on floorboards: a click over a short resonant thump."""
    n = int(RATE * 0.2)
    click_noise = [rng.uniform(-1, 1) for _ in range(n)]
    click = high_pass(click_noise, 1800)
    out = []
    for i in range(n):
        t = i / RATE
        thump = math.sin(2 * math.pi * 115 * pitch * t) * math.exp(-t / 0.045)
        ring = math.sin(2 * math.pi * 238 * pitch * t) * math.exp(-t / 0.03) * 0.45
        out.append(thump + ring + click[i] * math.exp(-t / 0.004) * 0.6)
    return low_pass(out, 3000)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    write_wav("gunshot", gunshot(random.Random("gunshot")), peak=0.95)
    write_wav("squawk", squawk(random.Random("squawk")), peak=0.8)
    for index, pitch in enumerate((1.0, 0.9, 1.12), start=1):
        write_wav(f"step_grass_{index}", grass_step(random.Random(f"grass-{index}"), pitch), peak=0.55)
        write_wav(f"step_wood_{index}", wood_step(random.Random(f"wood-{index}"), pitch), peak=0.6)
    print(f"Sounds written to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
