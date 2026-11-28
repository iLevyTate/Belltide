#!/usr/bin/env python3
"""Synthesizes Belltide's chime sounds.

The chimes are generated from scratch (additive and FM synthesis of decaying
partials, with a synthetic stereo reverb), so the app ships no third-party
audio. Run from the repository root after changing a sound:

    python3 tool/generate_chimes.py

Requires numpy. When ffmpeg is on PATH the sounds are written as Ogg Vorbis
(small and low-latency in SoundPool); otherwise they are written as WAV.

Output:
  android/app/src/main/res/raw/chime_<id>.(ogg|wav)
  android/app/src/main/kotlin/.../service/ChimeCatalog.kt  (ids and lengths)

When you add or rename a sound, also update lib/src/model/chime_sound.dart;
test/model_test.dart fails if the two lists drift apart.
"""

import os
import shutil
import subprocess
import sys
import tempfile
import wave
import zlib

import numpy as np

# 32 kHz stereo keeps a sound under SoundPool's limit for longer: SoundPool decodes
# each sample into a 1 MB buffer and silently drops whatever does not fit.
RATE = 32000
MAX_SECONDS = 7.5
MAX_PCM_BYTES = 1_000_000

# Sounds are matched by loudness, not peak, so a pure tone is not louder than a bell.
TARGET_LOUDNESS_DB = -15.0
PEAK_CEILING = 0.89

OUT_DIR = os.path.join("android", "app", "src", "main", "res", "raw")
CATALOG = os.path.join(
    "android", "app", "src", "main", "kotlin",
    "io", "github", "ilevytate", "belltide", "service", "ChimeCatalog.kt",
)


def timeline(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def spectrum_filter(signal, lo=None, hi=None, order=2):
    """Zero-phase high-pass at lo and low-pass at hi (Hz), done in the frequency domain."""
    spec = np.fft.rfft(signal)
    freqs = np.maximum(np.fft.rfftfreq(len(signal), 1 / RATE), 1e-9)
    gain = np.ones_like(freqs)
    if lo:
        gain /= np.sqrt(1 + (lo / freqs) ** (2 * order))
    if hi:
        gain /= np.sqrt(1 + (freqs / hi) ** (2 * order))
    return np.fft.irfft(spec * gain, len(signal))


def ring(rng, freq, spec, seconds, beat=0.0, depth=0.4):
    """Stereo sum of exponentially decaying sines.

    spec is a list of (ratio, amplitude, decay_seconds). With beat > 0 every
    partial gets a quieter twin a few hertz away, like the two halves of a
    mode in a real bell or bowl; the pair beats slowly, and because the twin
    leans to one side the beating drifts across the stereo field.
    """
    t = timeline(seconds)
    out = np.zeros((2, len(t)))
    for i, (ratio, amp, decay) in enumerate(spec):
        f = freq * ratio
        if f > 0.45 * RATE:
            continue
        env = amp * np.exp(-t / decay)
        main = env * np.sin(2 * np.pi * f * t)
        if beat:
            offset = beat * (0.7 + 0.45 * i)
            twin = depth * env * np.sin(2 * np.pi * (f + offset) * t + rng.uniform(0, 2 * np.pi))
            lean = 0.6 if i % 2 == 0 else -0.6
            out[0] += (main + (1 + lean) * twin) / (1 + depth)
            out[1] += (main + (1 - lean) * twin) / (1 + depth)
        else:
            out += main
    return out


def strike(rng, lo, hi, decay_ms, level):
    """The noise of a mallet hit: a band of noise that dies away in milliseconds."""
    t = timeline(max(0.03, decay_ms / 1000 * 10))
    noise = spectrum_filter(rng.standard_normal(len(t)), lo, hi)
    noise *= 0.33 / np.std(noise)
    return level * noise * np.exp(-t / (decay_ms / 1000))


def attack(signal, ms):
    n = max(1, int(RATE * ms / 1000))
    signal = signal.copy()
    signal[..., :n] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, n))
    return signal


def release(signal, start=0.6):
    """Eases the last part of a sound to silence so it never ends on a cut."""
    n = signal.shape[-1]
    first = int(n * start)
    signal = signal.copy()
    signal[..., first:] *= np.cos(np.linspace(0.0, np.pi / 2, n - first)) ** 2
    return signal


def pan(mono, position=0.0):
    """Places a mono signal between left (-1) and right (+1)."""
    angle = (position + 1) * np.pi / 4
    return np.sqrt(2) * np.stack([np.cos(angle) * mono, np.sin(angle) * mono])


def mix(seconds, *parts):
    """Mixes (offset_seconds, signal) pairs into one stereo buffer."""
    out = np.zeros((2, int(RATE * seconds)))
    for offset, sig in parts:
        if sig.ndim == 1:
            sig = np.stack([sig, sig])
        start = int(RATE * offset)
        end = min(out.shape[1], start + sig.shape[1])
        out[:, start:end] += sig[:, : end - start]
    return out


_impulse_responses = {}


def impulse_response(rt60):
    """A synthetic room: decaying noise, different in each ear, darker as it fades."""
    if rt60 in _impulse_responses:
        return _impulse_responses[rt60]
    rng = np.random.default_rng(11)
    t = timeline(rt60 * 1.15)
    tail = np.zeros((2, len(t)))
    for ch in range(2):
        noise = rng.standard_normal(len(t))
        low = spectrum_filter(noise, hi=500)
        mid = spectrum_filter(noise, lo=500, hi=4000)
        high = spectrum_filter(noise, lo=4000)
        tail[ch] = (
            low * np.exp(-6.91 * t / rt60)
            + mid * np.exp(-6.91 * t / (0.8 * rt60))
            + 0.7 * high * np.exp(-6.91 * t / (0.4 * rt60))
        ) * (1 - np.exp(-t / 0.012))
    tail /= np.sqrt(np.sum(tail**2, axis=1, keepdims=True))
    ir = np.concatenate([np.zeros((2, int(RATE * 0.012))), tail], axis=1)
    _impulse_responses[rt60] = ir
    return ir


def reverb(stereo, rt60, wet):
    ir = impulse_response(rt60)
    n = stereo.shape[1] + ir.shape[1] - 1
    size = 1 << (n - 1).bit_length()
    spec = np.fft.rfft(stereo.mean(axis=0), size)
    out = np.zeros((2, n))
    out[:, : stereo.shape[1]] = stereo
    for ch in range(2):
        out[ch] += wet * np.fft.irfft(spec * np.fft.rfft(ir[ch], size), size)[:n]
    return out


# (ratio, amplitude, decay) for a cast bell: hum, prime, tierce, quint, nominal
# and the higher partials that give the strike its brightness.
BELL = [
    (0.5, 0.25, 1.25),
    (1.0, 1.00, 1.00),
    (1.2, 0.32, 0.80),
    (1.5, 0.18, 0.65),
    (2.0, 0.48, 0.60),
    (2.5, 0.12, 0.42),
    (2.67, 0.13, 0.40),
    (3.01, 0.11, 0.33),
    (4.1, 0.07, 0.24),
    (5.43, 0.045, 0.17),
    (6.8, 0.025, 0.12),
]

# A bar free at both ends: tubular chimes and wind chimes.
BAR = [(1.0, 1.00, 1.0), (2.756, 0.45, 0.48), (5.404, 0.2, 0.24), (8.933, 0.07, 0.13)]


def scaled(spec, sustain):
    return [(ratio, amp, decay * sustain) for ratio, amp, decay in spec]


def bell_voice(rng, freq, sustain=1.0):
    seconds = 3.5 * 1.25 * sustain
    body = ring(rng, freq, scaled(BELL, sustain), seconds, beat=0.9, depth=0.22)
    hit = strike(rng, 1500, 9000, 5, 0.10)
    return release(attack(mix(seconds, (0, body), (0, hit)), 1.5))


def bar_voice(rng, freq, sustain=1.0, position=0.0):
    seconds = 3.2 * sustain
    body = ring(rng, freq, scaled(BAR, sustain), seconds, beat=0.5, depth=0.15)
    hit = pan(strike(rng, 2500, 11000, 3, 0.09), position)
    lean = np.array([[1 - 0.5 * position], [1 + 0.5 * position]])
    return release(attack(mix(seconds, (0, body * lean), (0, hit)), 1))


def sound_bell(rng):
    return bell_voice(rng, 659.25)


def sound_double(rng):
    one = bell_voice(rng, 880.0, sustain=0.8)
    return mix(3.8, (0.0, one), (0.22, 0.8 * one))


def sound_rise(rng):
    notes = [1046.5, 1318.5, 1568.0]
    parts = [(i * 0.16, (0.85 + 0.08 * i) * bell_voice(rng, f, 0.75)) for i, f in enumerate(notes)]
    return mix(3.7, *parts)


def sound_fall(rng):
    notes = [1568.0, 1318.5, 1046.5]
    parts = [(i * 0.16, (0.85 + 0.08 * i) * bell_voice(rng, f, 0.75)) for i, f in enumerate(notes)]
    return mix(3.7, *parts)


def sound_temple(rng):
    seconds = 6.6
    spec = [
        (0.5, 0.35, 2.0),
        (1.0, 1.00, 1.9),
        (1.19, 0.30, 1.5),
        (1.5, 0.25, 1.3),
        (2.0, 0.70, 1.4),
        (2.52, 0.30, 1.0),
        (3.0, 0.40, 0.9),
        (4.0, 0.22, 0.7),
        (5.2, 0.12, 0.5),
        (6.5, 0.06, 0.35),
    ]
    body = ring(rng, 220.0, spec, seconds, beat=1.3, depth=0.4)
    hit = strike(rng, 200, 1500, 18, 0.14)
    return release(attack(mix(seconds, (0, body), (0, hit)), 6))


def sound_bowl(rng):
    seconds = 6.4
    spec = [(1.0, 1.00, 2.0), (2.71, 0.60, 1.6), (5.15, 0.28, 1.0), (8.1, 0.10, 0.55)]
    body = ring(rng, 293.66, spec, seconds, beat=1.6, depth=0.4)
    hit = strike(rng, 300, 3000, 10, 0.07)
    return release(attack(mix(seconds, (0, body), (0, hit)), 8))


def sound_crystal(rng):
    seconds = 6.6
    spec = [(1.0, 1.00, 2.1), (2.0, 0.05, 1.2), (2.83, 0.12, 1.1), (5.2, 0.04, 0.6)]
    body = ring(rng, 440.0, spec, seconds, beat=0.7, depth=0.25)
    return release(attack(body, 60))


def sound_gong(rng):
    seconds = 6.6
    t = timeline(seconds)
    spec = [
        (1.0, 0.70, 2.0),
        (1.48, 0.55, 1.8),
        (1.98, 0.80, 1.7),
        (2.44, 0.50, 1.4),
        (2.91, 0.65, 1.2),
        (3.62, 0.40, 1.0),
        (4.33, 0.30, 0.8),
        (5.10, 0.18, 0.6),
    ]
    body = ring(rng, 196.0, spec, seconds, beat=1.1, depth=0.35)
    # After the strike, energy spreads into a wash of high partials: the shimmer
    # of a gong. Each one swells in before it decays, the higher the later.
    shimmer = np.zeros((2, len(t)))
    for _ in range(30):
        ratio = rng.uniform(3.0, 22.0)
        amp = 0.32 * rng.uniform(0.4, 1.0) / ratio**0.6
        swell = 0.05 + 0.5 * ratio / 22
        decay = 0.3 + 2.4 / (1 + ratio / 6)
        partial = amp * (1 - np.exp(-t / swell)) * np.exp(-t / decay)
        partial = partial * np.sin(2 * np.pi * 196.0 * ratio * t + rng.uniform(0, 2 * np.pi))
        shimmer += pan(partial, rng.uniform(-0.8, 0.8))
    hit = strike(rng, 80, 600, 30, 0.12)
    return release(attack(mix(seconds, (0, body), (0, shimmer), (0, hit)), 12))


def sound_tingsha(rng):
    seconds = 4.4
    spec = [(1.0, 1.00, 1.4), (2.26, 0.35, 0.8), (3.9, 0.15, 0.45)]
    # Two small cymbals tuned a few hertz apart, one in each ear.
    first = ring(rng, 2637.0, spec, seconds).mean(axis=0)
    second = ring(rng, 2644.0, spec, seconds).mean(axis=0)
    hit = strike(rng, 4000, 12000, 2, 0.12)
    cymbals = mix(seconds, (0, pan(first, -0.5)), (0.003, pan(second, 0.5)), (0, hit))
    return release(attack(cymbals, 0.7))


def sound_chime(rng):
    return bar_voice(rng, 1318.5, sustain=1.1)


def sound_wind(rng):
    # A handful of tubes from one pentatonic scale, knocked at uneven moments.
    notes = [1318.5, 1568.0, 1046.5, 1760.0, 1174.7, 1568.0, 1318.5, 2093.0]
    onsets = [0.0, 0.17, 0.46, 0.61, 0.98, 1.37, 1.52, 1.95]
    parts = []
    for freq, onset in zip(notes, onsets):
        level = rng.uniform(0.45, 1.0)
        parts.append((onset, level * bar_voice(rng, freq, 0.9, rng.uniform(-0.7, 0.7))))
    return mix(5.0, *parts)


def sound_glass(rng):
    seconds = 1.9
    spec = [(1.0, 1.00, 0.6), (2.32, 0.40, 0.33), (4.25, 0.18, 0.2), (6.63, 0.06, 0.12)]
    body = ring(rng, 2093.0, spec, seconds, beat=0.6, depth=0.15)
    hit = strike(rng, 3000, 12000, 1.5, 0.14)
    return release(attack(mix(seconds, (0, body), (0, hit)), 0.5))


def sound_wood(rng):
    seconds = 0.35
    spec = [(1.0, 1.00, 0.045), (1.58, 0.55, 0.03), (2.41, 0.30, 0.02)]
    body = ring(rng, 820.0, spec, seconds)
    hit = strike(rng, 900, 7000, 4, 0.35)
    return release(attack(mix(seconds, (0, body), (0, hit)), 0.5), 0.8)


def marimba_note(rng, freq):
    seconds = 1.5
    spec = [(1.0, 1.00, 0.45), (4.0, 0.28, 0.16), (10.0, 0.07, 0.05)]
    body = ring(rng, freq, spec, seconds)
    hit = strike(rng, 200, 2500, 6, 0.16)
    return release(attack(mix(seconds, (0, body), (0, hit)), 1))


def sound_marimba(rng):
    return mix(1.7, (0.0, 0.9 * marimba_note(rng, 392.0)), (0.19, marimba_note(rng, 523.25)))


def kalimba_note(rng, freq):
    seconds = 2.2
    # A tine clamped at one end, plus the knock of the wooden box under it.
    spec = [(1.0, 1.00, 0.7), (2.0, 0.12, 0.4), (6.27, 0.22, 0.12), (17.55, 0.06, 0.04)]
    body = ring(rng, freq, spec, seconds)
    box = strike(rng, 150, 900, 12, 0.18)
    return release(attack(mix(seconds, (0, body), (0, box)), 1))


def sound_kalimba(rng):
    low = pan(kalimba_note(rng, 587.33).mean(axis=0), -0.3)
    high = pan(kalimba_note(rng, 880.0).mean(axis=0), 0.3)
    return mix(2.3, (0.0, low), (0.03, 0.85 * high))


def sound_beep(rng):
    seconds = 0.2
    t = timeline(seconds)
    tone = (
        np.sin(2 * np.pi * 880 * t)
        + 0.15 * np.sin(2 * np.pi * 1760 * t)
        + 0.05 * np.sin(2 * np.pi * 2640 * t)
    )
    edge = int(RATE * 0.012)
    env = np.ones_like(t)
    env[:edge] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, edge))
    env[-edge:] = env[:edge][::-1]
    beep = tone * env
    return mix(0.5, (0.0, beep), (0.27, beep))


def sound_soft(rng):
    seconds = 1.2
    t = timeline(seconds)
    tone = np.sin(2 * np.pi * 587.33 * t) + 0.12 * np.sin(2 * np.pi * 1174.66 * t)
    return release(attack(np.stack([tone, tone]) * np.exp(-t / 0.32), 12))


def sound_chord(rng):
    seconds = 3.8
    t = timeline(seconds)
    # An electric piano: each note is a sine bent by a second sine at the same
    # pitch (FM). The bend fades fast, so the note starts bright and turns round.
    notes = [349.23, 440.0, 523.25, 659.25]
    parts = []
    for i, freq in enumerate(notes):
        bend = 1.2 * np.exp(-t / 0.25) + 0.15
        note = np.sin(2 * np.pi * freq * t + bend * np.sin(2 * np.pi * freq * t))
        note = attack(note * np.exp(-t / 1.2), 4)
        parts.append((i * 0.035, pan(note, -0.45 + 0.3 * i)))
    chord = mix(seconds, *parts)
    # A slow drift from ear to ear.
    sway = 0.12 * np.sin(2 * np.pi * 1.2 * timeline(seconds))
    return release(chord * np.stack([1 + sway, 1 - sway]))


# id -> (generator, reverb seconds, reverb amount). Order is the order in the catalog.
SOUNDS = {
    "bell": (sound_bell, 1.4, 0.16),
    "double": (sound_double, 1.4, 0.16),
    "rise": (sound_rise, 1.4, 0.16),
    "fall": (sound_fall, 1.4, 0.16),
    "temple": (sound_temple, 2.0, 0.20),
    "bowl": (sound_bowl, 1.8, 0.18),
    "crystal": (sound_crystal, 2.0, 0.22),
    "gong": (sound_gong, 2.0, 0.20),
    "tingsha": (sound_tingsha, 1.4, 0.14),
    "chime": (sound_chime, 1.4, 0.16),
    "wind": (sound_wind, 1.4, 0.16),
    "glass": (sound_glass, 1.0, 0.14),
    "wood": (sound_wood, 0.4, 0.12),
    "marimba": (sound_marimba, 0.8, 0.13),
    "kalimba": (sound_kalimba, 0.8, 0.14),
    "beep": (sound_beep, 0.3, 0.05),
    "soft": (sound_soft, 1.0, 0.18),
    "chord": (sound_chord, 1.6, 0.18),
}


def a_weighted(signal):
    """Weights a signal the way the ear hears it: less bass, a little less top."""
    spec = np.fft.rfft(signal)
    f2 = np.fft.rfftfreq(len(signal), 1 / RATE) ** 2
    weight = (
        1.2589 * 12194.0**2 * f2**2
        / ((f2 + 20.6**2) * np.sqrt((f2 + 107.7**2) * (f2 + 737.9**2)) * (f2 + 12194.0**2))
    )
    return np.fft.irfft(spec * weight, len(signal))


def loudness_db(stereo):
    """The loudest quarter second, A-weighted, in dB relative to full scale."""
    power = np.mean([a_weighted(ch) ** 2 for ch in stereo], axis=0)
    window = int(RATE * 0.25)
    total = np.cumsum(np.insert(power, 0, 0.0))
    if len(power) <= window:
        loudest = total[-1] / window
    else:
        loudest = np.max(total[window:] - total[:-window]) / window
    return 10 * np.log10(loudest)


def finish(stereo):
    """Trims the silent tail, caps the length and matches the loudness."""
    stereo = stereo - stereo.mean(axis=1, keepdims=True)
    level = np.max(np.abs(stereo), axis=0)
    audible = np.nonzero(level > level.max() * 10 ** (-66 / 20))[0]
    end = min(audible[-1] + int(RATE * 0.05), int(RATE * MAX_SECONDS), stereo.shape[1])
    stereo = stereo[:, :end].copy()
    fade = min(end, int(RATE * 0.08))
    stereo[:, -fade:] *= np.cos(np.linspace(0.0, np.pi / 2, fade)) ** 2
    gain = 10 ** ((TARGET_LOUDNESS_DB - loudness_db(stereo)) / 20)
    gain = min(gain, PEAK_CEILING / np.max(np.abs(stereo)))
    return stereo * gain


def render(name):
    make, rt60, wet = SOUNDS[name]
    # Each sound has its own seed, so changing one never changes the others.
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    return finish(reverb(make(rng), rt60, wet))


def write_wav(path, stereo):
    pcm = (np.clip(stereo, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.T.tobytes())


def write_catalog(durations):
    lines = [
        "// Generated by tool/generate_chimes.py. Do not edit by hand.",
        "package io.github.ilevytate.belltide.service",
        "",
        "import io.github.ilevytate.belltide.R",
        "",
        "/** A chime's sound file and how long it rings. */",
        "data class ChimeInfo(val resId: Int, val durationMs: Long)",
        "",
        "/** Every chime, by the id shared with the Flutter side (lib/src/model/chime_sound.dart). */",
        "val CHIME_CATALOG: Map<String, ChimeInfo> = mapOf(",
    ]
    for name, seconds in durations.items():
        lines.append(f'    "{name}" to ChimeInfo(R.raw.chime_{name}, {round(seconds * 1000)}),')
    lines.append(")")
    with open(CATALOG, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    if not os.path.isdir(os.path.join("android", "app")):
        sys.exit("Run this from the repository root.")
    os.makedirs(OUT_DIR, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    for stale in os.listdir(OUT_DIR):
        if stale.startswith("chime_") and stale.endswith((".ogg", ".wav")):
            os.remove(os.path.join(OUT_DIR, stale))
    durations = {}
    with tempfile.TemporaryDirectory() as tmp:
        for name in SOUNDS:
            stereo = render(name)
            seconds = stereo.shape[1] / RATE
            if stereo.size * 2 > MAX_PCM_BYTES:
                sys.exit(f"{name} is {seconds:.2f}s: too long for SoundPool's 1 MB buffer.")
            durations[name] = seconds
            if ffmpeg:
                wav = os.path.join(tmp, f"{name}.wav")
                write_wav(wav, stereo)
                out = os.path.join(OUT_DIR, f"chime_{name}.ogg")
                subprocess.run(
                    [ffmpeg, "-loglevel", "error", "-y", "-i", wav,
                     "-c:a", "libvorbis", "-q:a", "6", "-map_metadata", "-1", out],
                    check=True,
                )
            else:
                out = os.path.join(OUT_DIR, f"chime_{name}.wav")
                write_wav(out, stereo)
            peak = 20 * np.log10(np.max(np.abs(stereo)))
            print(f"{out}  {seconds:5.2f}s  peak {peak:6.1f} dB  loudness {loudness_db(stereo):6.1f} dB")
    write_catalog(durations)
    print(f"{CATALOG}  {len(durations)} sounds")


if __name__ == "__main__":
    main()
