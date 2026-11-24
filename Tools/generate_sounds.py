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


def band_pass(samples, center, q):
    """Biquad band-pass filter (constant peak gain)."""
    w0 = 2 * math.pi * center / RATE
    alpha = math.sin(w0) / (2 * q)
    b0, b1, b2 = alpha, 0, -alpha
    a0, a1, a2 = 1 + alpha, -2 * math.cos(w0), 1 - alpha
    out, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for x in samples:
        y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        out.append(y)
        x2, x1, y2, y1 = x1, x, y1, y
    return out


def quack(rng, base=230.0, length=0.26, drop=0.25, repeats=1):
    """A nasal duck quack: a buzzy sawtooth shaped by two 'formant' band-passes."""
    out = []
    for r in range(repeats):
        n = int(RATE * length)
        phase = 0.0
        source = []
        for i in range(n):
            t = i / RATE
            p = t / length
            freq = base * (1.1 - drop * p) * (1 + 0.02 * math.sin(2 * math.pi * 28 * t))
            phase = (phase + freq / RATE) % 1.0
            saw = 2 * phase - 1
            envelope = min(1, t / 0.015) * (1 - p) ** 0.6
            source.append((saw + rng.uniform(-0.15, 0.15)) * envelope)
        voiced = [a + b * 0.7 for a, b in zip(band_pass(source, 1050, 4), band_pass(source, 2600, 6))]
        out.extend(voiced)
        out.extend([0.0] * int(RATE * 0.04))
        base *= 0.85
    return bitcrush(out, 96)


def roar(rng, length=1.3):
    """A bear's roar: a growling, wobbling low sawtooth buried in rumbling noise."""
    n = int(RATE * length)
    noise = low_pass([rng.uniform(-1, 1) for _ in range(n)], 700)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        p = t / length
        freq = 95 + 45 * math.sin(math.pi * min(p * 1.4, 1)) + 6 * math.sin(2 * math.pi * 7 * t)
        phase = (phase + freq / RATE) % 1.0
        saw = 2 * phase - 1
        envelope = min(1, t / 0.12) * (1 - p) ** 0.8 * (1 + 0.3 * math.sin(2 * math.pi * 23 * t))
        out.append((saw * 0.8 + noise[i] * 2.2) * envelope)
    mixed = [a * 0.6 + b for a, b in zip(low_pass(out, 900), band_pass(out, 420, 0.8))]
    return bitcrush(mixed, 64)


def wind(rng, length=7.0):
    """An eerie, gusting wind: rushing filtered noise that swells and fades, with a faint howl."""
    n = int(RATE * length)
    noise = [rng.uniform(-1, 1) for _ in range(n)]
    rush = low_pass(high_pass(noise, 180), 1400)
    hiss = band_pass(noise, 2400, 2.5)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        gust = 0.55 + 0.45 * math.sin(2 * math.pi * 0.23 * t) * math.sin(2 * math.pi * 0.11 * t + 1)
        fade = min(1, t / 1.2) * min(1, (length - t) / 1.5)
        freq = 420 + 140 * math.sin(2 * math.pi * 0.17 * t) + 30 * math.sin(2 * math.pi * 0.9 * t)
        phase += 2 * math.pi * freq / RATE
        howl = math.sin(phase) * 0.10 * (0.4 + 0.6 * gust)
        out.append((rush[i] * 2.4 * gust + hiss[i] * 0.6 * gust + howl) * fade)
    return out


def ufo_arrive(rng, length=2.2):
    """A wobbling, theremin-like descending whine over a swelling whoosh."""
    n = int(RATE * length)
    whoosh = low_pass([rng.uniform(-1, 1) for _ in range(n)], 900)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        p = t / length
        freq = 980 - 520 * p + 45 * math.sin(2 * math.pi * 6 * t)
        phase += 2 * math.pi * freq / RATE
        tone = math.sin(phase) * 0.7 + math.sin(2 * phase) * 0.18
        envelope = min(1, t / 0.25) * (1 - p) ** 0.5
        out.append(tone * envelope + whoosh[i] * 1.4 * math.sin(math.pi * p))
    return bitcrush(out, 96)


def ufo_beam(rng, length=3.0):
    """The tractor beam: a rising, pulsing electronic warble with a shimmering arpeggio."""
    n = int(RATE * length)
    out = []
    phase = arp_phase = 0.0
    arp = [600, 800, 1000, 1200, 1000, 800]
    for i in range(n):
        t = i / RATE
        p = t / length
        freq = 300 + 400 * p
        phase += 2 * math.pi * freq / RATE
        pulse = 1 if math.sin(2 * math.pi * 14 * t) > 0 else 0.35
        ring = math.sin(2 * math.pi * 47 * t)
        arp_freq = arp[int(t / 0.08) % len(arp)] * (1 + 0.4 * p)
        arp_phase += 2 * math.pi * arp_freq / RATE
        envelope = min(1, t / 0.15) * min(1, (length - t) / 0.4)
        out.append((math.sin(phase) * ring * 0.7 * pulse + math.sin(arp_phase) * 0.25) * envelope)
    return bitcrush(out, 80)


def tone_blip(freq, length=0.16, square=True):
    """A short, clean console blip."""
    n = int(RATE * length)
    out = []
    for i in range(n):
        t = i / RATE
        wave_ = math.sin(2 * math.pi * freq * t)
        if square:
            wave_ = math.tanh(4 * wave_)
        out.append(wave_ * min(1, t / 0.005) * (1 - t / length) ** 1.5)
    return bitcrush(out, 64)


def arpeggio(freqs, step=0.09, tail=0.25):
    """Notes played in quick succession, the last one ringing out."""
    out = []
    for k, f in enumerate(freqs):
        out.extend(tone_blip(f, step + (tail if k == len(freqs) - 1 else 0)))
    return out


def buzz(length=0.45):
    """A low, rough error buzz."""
    n = int(RATE * length)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        phase = (phase + 110 / RATE) % 1.0
        saw = 2 * phase - 1
        out.append((saw + 0.6 * (1 if math.sin(2 * math.pi * 55 * t) > 0 else -1)) * min(1, t / 0.01) * (1 - t / length))
    return bitcrush(out, 32)


def alarm(length=2.4):
    """A two-tone lockdown siren."""
    n = int(RATE * length)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        freq = 880 if int(t / 0.3) % 2 == 0 else 620
        phase += 2 * math.pi * freq / RATE
        out.append(math.tanh(3 * math.sin(phase)) * min(1, t / 0.02) * min(1, (length - t) / 0.2))
    return bitcrush(out, 48)


def gurgle(rng, length=1.6):
    """A rumbling stomach: a low growl with bubbly, falling bloops."""
    n = int(RATE * length)
    rumble = low_pass([rng.uniform(-1, 1) for _ in range(n)], 160)
    out = [rumble[i] * 3.0 * math.sin(math.pi * i / n) for i in range(n)]
    for _ in range(9):
        start = int(rng.uniform(0.05, length - 0.3) * RATE)
        dur = rng.uniform(0.08, 0.18)
        f0 = rng.uniform(140, 260)
        phase = 0.0
        for k in range(int(dur * RATE)):
            t = k / RATE
            phase += 2 * math.pi * f0 * (1 - 0.5 * t / dur) / RATE
            if start + k < n:
                out[start + k] += math.sin(phase) * math.sin(math.pi * t / dur) * 0.9
    return low_pass(out, 900)


def gibberish(rng, length=3.0):
    """Alien chatter: quick warbly syllables with shifting vowel formants."""
    out = []
    while len(out) < RATE * length:
        dur = rng.uniform(0.09, 0.2)
        pitch = rng.uniform(320, 720)
        f1, f2 = rng.choice([(700, 1200), (400, 2200), (300, 900), (600, 1800), (500, 2600)])
        source = []
        phase = 0.0
        for k in range(int(dur * RATE)):
            t = k / RATE
            freq = pitch * (1 + 0.25 * math.sin(2 * math.pi * 18 * t)) * (1 + 0.3 * (t / dur) * rng.choice([-1, 1]))
            phase = (phase + freq / RATE) % 1.0
            source.append((2 * phase - 1) * math.sin(math.pi * t / dur))
        out.extend(a + b * 0.8 for a, b in zip(band_pass(source, f1, 5), band_pass(source, f2, 7)))
        out.extend([0.0] * int(rng.uniform(0.02, 0.09) * RATE))
    return bitcrush(out, 72)


def squeaky_fart(rng, length=0.7):
    """A high-pitched, squeaky raspberry."""
    n = int(RATE * length)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        p = t / length
        freq = 420 + 380 * math.sin(math.pi * p) + 60 * math.sin(2 * math.pi * 23 * t)
        phase = (phase + freq / RATE) % 1.0
        rasp = 0.55 + 0.45 * math.sin(2 * math.pi * 41 * t)
        tone = (1 if phase < 0.3 else -0.6) * rasp + rng.uniform(-0.25, 0.25)
        out.append(tone * min(1, t / 0.02) * (1 - p) ** 0.4)
    return bitcrush(low_pass(out, 3800), 48)


def glass_shatter(rng, length=1.0):
    """Breaking glass: a sharp crack and thud, then a shower of tinkling shards."""
    n = int(RATE * length)
    out = [0.0] * n
    crack = high_pass([rng.uniform(-1, 1) for _ in range(int(RATE * 0.06))], 2500)
    for i, v in enumerate(crack):
        out[i] += v * 1.6 * (1 - i / len(crack))
    for i in range(int(RATE * 0.12)):
        t = i / RATE
        out[i] += math.sin(2 * math.pi * 90 * t) * math.exp(-t / 0.03) * 0.8      # thud
    for _ in range(34):
        start = int(rng.uniform(0.01, length * 0.75) * RATE)
        freq = rng.uniform(2200, 6500)
        decay = rng.uniform(0.02, 0.08)
        amp = rng.uniform(0.2, 0.6)
        for k in range(int(decay * 5 * RATE)):
            if start + k < n:
                t = k / RATE
                out[start + k] += math.sin(2 * math.pi * freq * t) * math.exp(-t / decay) * amp
    return out


def alien_scream(rng, length=1.4):
    """A comical, warbly alien shriek that rises, wobbles, and trails off."""
    n = int(RATE * length)
    source = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        p = t / length
        freq = (1150 + 450 * math.sin(math.pi * min(p * 1.6, 1)) - 500 * max(0, p - 0.6)) * (1 + 0.09 * math.sin(2 * math.pi * 13 * t))
        phase = (phase + freq / RATE) % 1.0
        source.append((2 * phase - 1) * min(1, t / 0.04) * (1 - p) ** 0.5 * (0.75 + 0.25 * math.sin(2 * math.pi * 7 * t)))
    voiced = [a + b * 0.8 for a, b in zip(band_pass(source, 1800, 3), band_pass(source, 3200, 4))]
    return bitcrush(voiced, 64)


def bone_rattle(rng, length=0.9):
    """Dry, clattering bones."""
    n = int(RATE * length)
    out = [0.0] * n
    for _ in range(16):
        start = int(rng.uniform(0, length - 0.06) * RATE)
        burst = band_pass([rng.uniform(-1, 1) for _ in range(int(RATE * 0.03))], rng.uniform(1400, 2600), 6)
        for k, v in enumerate(burst):
            if start + k < n:
                out[start + k] += v * (1 - k / len(burst)) * rng.uniform(0.5, 1)
    return out


def whistle(rng, length=3.2):
    """A carefree whistled tune: a pure tone with a little breath and vibrato, note to note."""
    notes = [784, 988, 1175, 988, 784, 880, 988, 784, 659, 784]
    durations = [0.28, 0.28, 0.42, 0.22, 0.32, 0.26, 0.42, 0.3, 0.26, 0.44]
    out = []
    phase = 0.0
    for freq, dur in zip(notes, durations):
        n = int(RATE * dur)
        for i in range(n):
            t = i / RATE
            f = freq * (1 + 0.012 * math.sin(2 * math.pi * 6 * t)) * (0.97 + 0.03 * min(1, t / 0.03))
            phase += 2 * math.pi * f / RATE
            envelope = min(1, t / 0.03) * min(1, (dur - t) / 0.05)
            out.append((math.sin(phase) + rng.uniform(-0.06, 0.06)) * envelope)
        out.extend([0.0] * int(RATE * 0.03))
    return out


def water_splash(rng, length=0.7):
    """A small plop into water: a quick watery burst and a couple of rising bubble bloops."""
    n = int(RATE * length)
    noise = band_pass([rng.uniform(-1, 1) for _ in range(n)], 900, 1.2)
    out = [noise[i] * math.exp(-(i / RATE) / 0.08) * 1.4 for i in range(n)]
    for start, f0 in ((0.0, 300), (0.12, 520), (0.26, 680)):
        phase = 0.0
        for k in range(int(0.12 * RATE)):
            t = k / RATE
            phase += 2 * math.pi * f0 * (1 + 2.5 * t / 0.12) / RATE
            i = int(start * RATE) + k
            if i < n:
                out[i] += math.sin(phase) * math.sin(math.pi * t / 0.12) * 0.7
    return out


def gate_clank(rng, length=0.9):
    """A chain-link gate slamming shut: a sharp hit and a ringing, inharmonic metal rattle."""
    n = int(RATE * length)
    out = []
    partials = [(520, 0.9), (1230, 0.6), (2110, 0.45), (3380, 0.3)]
    for i in range(n):
        t = i / RATE
        ring = sum(math.sin(2 * math.pi * f * t) * a for f, a in partials) * math.exp(-t / 0.18)
        rattle = rng.uniform(-1, 1) * math.exp(-t / 0.05) * 1.2
        out.append(ring * (0.85 + 0.15 * math.sin(2 * math.pi * 31 * t)) + rattle)
    return out


def snore(rng, cycles=2):
    """Big, rattling snores: a fluttering, nasal inhale and a soft, breathy exhale."""
    out = []
    for _ in range(cycles):
        inhale = int(RATE * 1.5)
        noise = low_pass([rng.uniform(-1, 1) for _ in range(inhale)], 500)
        phase = 0.0
        for i in range(inhale):
            t = i / RATE
            p = t / 1.5
            phase += 2 * math.pi * (85 + 25 * p) / RATE
            flutter = 0.55 + 0.45 * math.sin(2 * math.pi * 28 * t)
            out.append((noise[i] * 2.5 + math.sin(phase) * 0.5) * flutter * math.sin(math.pi * p))
        exhale = int(RATE * 1.3)
        breath = band_pass([rng.uniform(-1, 1) for _ in range(exhale)], 1400, 1.5)
        for i in range(exhale):
            p = i / exhale
            out.append(breath[i] * 0.6 * math.sin(math.pi * p))
        out.extend([0.0] * int(RATE * 0.4))
    return out


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
    write_wav("quack", quack(random.Random("quack")), peak=0.8)
    write_wav("roar", roar(random.Random("roar")), peak=0.9)
    write_wav("alien_gibberish", gibberish(random.Random("gibberish")), peak=0.7)
    write_wav("glass_shatter", glass_shatter(random.Random("glass")), peak=0.8)
    write_wav("water_splash", water_splash(random.Random("splash")), peak=0.7)
    write_wav("gate_clank", gate_clank(random.Random("clank")), peak=0.75)
    write_wav("snore", snore(random.Random("snore")), peak=0.75)
    # whistle.wav is a recorded tune (converted from an MP3 download), not generated.
    write_wav("alien_scream", alien_scream(random.Random("scream")), peak=0.75)
    write_wav("bone_rattle", bone_rattle(random.Random("bones")), peak=0.75)
    # gurgle.wav and squeaky_fart.wav are recorded sounds (converted from MP3 downloads), not
    # generated, so they're left alone here.
    # The alien console: one tone per grid row, plus feedback sounds.
    for row, freq in enumerate((523, 659, 784, 1047)):
        write_wav(f"console_beep_{row}", tone_blip(freq), peak=0.6)
    write_wav("console_correct", arpeggio([784, 1047]), peak=0.6)
    write_wav("console_error", buzz(), peak=0.7)
    write_wav("console_alarm", alarm(), peak=0.6)
    write_wav("console_granted", arpeggio([523, 659, 784, 1047, 1319]), peak=0.65)
    write_wav("wind", wind(random.Random("wind")), peak=0.7)
    write_wav("ufo_arrive", ufo_arrive(random.Random("ufo-arrive")), peak=0.8)
    write_wav("ufo_beam", ufo_beam(random.Random("ufo-beam")), peak=0.75)
    write_wav("quack_down", quack(random.Random("quack-down"), base=190.0, length=0.3, drop=0.35, repeats=2), peak=0.8)
    for index, pitch in enumerate((1.0, 0.9, 1.12), start=1):
        write_wav(f"step_grass_{index}", grass_step(random.Random(f"grass-{index}"), pitch), peak=0.55)
        write_wav(f"step_wood_{index}", wood_step(random.Random(f"wood-{index}"), pitch), peak=0.6)
    print(f"Sounds written to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
