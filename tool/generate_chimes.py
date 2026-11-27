#!/usr/bin/env python3
"""Synthesizes Belltide's chime sounds.

The chimes are generated from scratch (additive synthesis of decaying
partials), so the app ships no third-party audio. Run from the repository
root after changing a sound:

    python3 tool/generate_chimes.py

Requires numpy. When ffmpeg is on PATH the sounds are written as Ogg Vorbis
(small and low-latency in SoundPool); otherwise they are written as WAV.
Output goes to android/app/src/main/res/raw/chime_<id>.(ogg|wav).
"""

import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 44100
OUT_DIR = os.path.join("android", "app", "src", "main", "res", "raw")
rng = np.random.default_rng(7)


def timeline(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def partials(freq, spec, seconds, detune=0.0):
    """Sum of exponentially decaying sines.

    spec is a list of (ratio, amplitude, decay_seconds). With detune > 0 each
    partial is split into two slightly mistuned sines, which gives the slow
    beating of a bowl or a large bell.
    """
    t = timeline(seconds)
    out = np.zeros_like(t)
    for ratio, amp, decay in spec:
        env = amp * np.exp(-t / decay)
        f = freq * ratio
        if detune:
            out += 0.5 * env * np.sin(2 * np.pi * f * (1 - detune) * t)
            out += 0.5 * env * np.sin(2 * np.pi * f * (1 + detune) * t + 0.7)
        else:
            out += env * np.sin(2 * np.pi * f * t)
    return out


def attack(signal, ms):
    n = max(1, int(RATE * ms / 1000))
    ramp = np.ones_like(signal)
    ramp[:n] = np.linspace(0.0, 1.0, n)
    return signal * ramp


def fade_tail(signal, ms=60):
    n = int(RATE * ms / 1000)
    signal = signal.copy()
    signal[-n:] *= np.linspace(1.0, 0.0, n)
    return signal


def strike_noise(seconds, level, decay_ms, smooth=8):
    t = timeline(seconds)
    noise = rng.standard_normal(len(t))
    kernel = np.ones(smooth) / smooth
    noise = np.convolve(noise, kernel, mode="same")
    return level * noise * np.exp(-t / (decay_ms / 1000))


def place(total_seconds, *parts):
    """Mixes (offset_seconds, signal) pairs into one buffer."""
    out = np.zeros(int(RATE * total_seconds))
    for offset, sig in parts:
        start = int(RATE * offset)
        end = min(len(out), start + len(sig))
        out[start:end] += sig[: end - start]
    return out


BELL_SPEC = [
    (0.5, 0.20, 2.2),
    (1.0, 1.00, 1.8),
    (1.19, 0.30, 1.1),
    (1.5, 0.22, 0.9),
    (2.0, 0.42, 0.8),
    (2.74, 0.18, 0.55),
    (3.0, 0.12, 0.45),
    (4.07, 0.08, 0.3),
    (5.4, 0.05, 0.2),
]


def bell(freq=659.25, seconds=2.6):
    body = partials(freq, BELL_SPEC, seconds, detune=0.0015)
    return attack(body + strike_noise(seconds, 0.15, 6), 2)


def sound_bell():
    return bell()


def sound_bowl():
    seconds = 4.5
    spec = [
        (1.0, 1.00, 3.2),
        (2.76, 0.65, 2.4),
        (5.40, 0.30, 1.4),
        (8.93, 0.12, 0.8),
    ]
    body = partials(293.66, spec, seconds, detune=0.004)
    return attack(body + strike_noise(seconds, 0.08, 10, smooth=20), 8)


def sound_chime():
    seconds = 2.2
    spec = [
        (1.0, 1.00, 1.5),
        (2.756, 0.45, 0.7),
        (5.404, 0.22, 0.35),
        (8.933, 0.08, 0.2),
    ]
    body = partials(1318.5, spec, seconds, detune=0.001)
    return attack(body + strike_noise(seconds, 0.12, 3, smooth=3), 1)


def sound_double():
    one = bell(880.0, 1.9)
    return place(2.1, (0.0, one), (0.2, 0.8 * one))


def sound_wood():
    seconds = 0.35
    spec = [
        (1.0, 1.00, 0.045),
        (1.58, 0.55, 0.03),
        (2.41, 0.30, 0.02),
    ]
    body = partials(820.0, spec, seconds)
    return attack(body + strike_noise(seconds, 0.35, 4, smooth=4), 0.5)


def sound_gong():
    seconds = 5.0
    spec = [
        (1.0, 0.70, 3.5),
        (1.48, 0.55, 3.0),
        (1.98, 0.80, 2.8),
        (2.44, 0.50, 2.2),
        (2.91, 0.65, 1.9),
        (3.62, 0.40, 1.4),
        (4.33, 0.30, 1.1),
        (5.10, 0.18, 0.8),
    ]
    body = partials(196.0, spec, seconds, detune=0.003)
    swell = 1.0 - 0.35 * np.exp(-timeline(seconds) / 0.15)
    return attack(body * swell + strike_noise(seconds, 0.12, 25, smooth=30), 15)


def sound_rise():
    notes = [1046.5, 1318.5, 1568.0]
    parts = [(i * 0.16, bell(f, 2.2) * (0.85 + 0.1 * i)) for i, f in enumerate(notes)]
    return place(2.6, *parts)


def sound_beep():
    seconds = 0.22
    t = timeline(seconds)
    tone = np.sin(2 * np.pi * 880 * t) + 0.15 * np.sin(2 * np.pi * 1760 * t)
    env = np.ones_like(t)
    n = int(RATE * 0.01)
    env[:n] = np.linspace(0, 1, n)
    env[-n:] = np.linspace(1, 0, n)
    beep = tone * env
    return place(0.5, (0.0, beep), (0.27, beep))


SOUNDS = {
    "bell": (sound_bell, 0.90),
    "bowl": (sound_bowl, 0.90),
    "chime": (sound_chime, 0.80),
    "double": (sound_double, 0.90),
    "wood": (sound_wood, 0.90),
    "gong": (sound_gong, 0.90),
    "rise": (sound_rise, 0.85),
    "beep": (sound_beep, 0.55),
}


def normalize(signal, peak):
    signal = fade_tail(signal)
    return signal / np.max(np.abs(signal)) * peak


def write_wav(path, signal):
    pcm = np.clip(signal, -1.0, 1.0)
    pcm = (pcm * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())


def main():
    if not os.path.isdir(os.path.join("android", "app")):
        sys.exit("Run this from the repository root.")
    os.makedirs(OUT_DIR, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    with tempfile.TemporaryDirectory() as tmp:
        for name, (make, peak) in SOUNDS.items():
            signal = normalize(make(), peak)
            for ext in ("ogg", "wav"):
                stale = os.path.join(OUT_DIR, f"chime_{name}.{ext}")
                if os.path.exists(stale):
                    os.remove(stale)
            if ffmpeg:
                wav = os.path.join(tmp, f"{name}.wav")
                write_wav(wav, signal)
                out = os.path.join(OUT_DIR, f"chime_{name}.ogg")
                subprocess.run(
                    [ffmpeg, "-loglevel", "error", "-y", "-i", wav,
                     "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1", out],
                    check=True,
                )
            else:
                out = os.path.join(OUT_DIR, f"chime_{name}.wav")
                write_wav(out, signal)
            print(f"{out}  {len(signal) / RATE:.2f}s")


if __name__ == "__main__":
    main()
