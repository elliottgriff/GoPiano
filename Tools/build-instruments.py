#!/usr/bin/env python3
"""Builds the electric piano and guitar samples from their source packs.

    ./Tools/build-instruments.py <Wurlitzer EP200 folder> <meta-steel-guitar folder>

The Wurlitzer folder is "Wurlitzer EP200" from sfzinstruments/GregSullivan.E-Pianos
(CC BY 3.0); the guitar folder is meta-steel-guitar from the
facebookincubator/Meta-open-sound OGG release (CC0). See Tools/README.md.

For each instrument this picks one sample per root from the pack's own SFZ map,
converts it to 22.05 kHz mono with afconvert, trims the silence before the
note and fades the tail, measures its real pitch, and matches its loudness to
the piano. It writes the WAVs into GoPiano/Samples and a CSV beside this
script, which build-samplemap.py turns into Swift.
"""

import aifc
import array
import math
import os
import re
import statistics
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(HERE, os.pardir, "GoPiano", "Samples")
RATE = 22050


def nominal(note):
    return 440.0 * 2 ** ((note - 69) / 12)


def decode(path):
    """Mono 16-bit at RATE, as floats in -1...1."""
    # AIFF, as afconvert's mono WAVs use the extensible header Python's
    # wave module can't read.
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "x.aiff")
        subprocess.run(["afconvert", "-f", "AIFF", "-d", "BEI16@%d" % RATE, "-c", "1", path, out],
                       check=True, capture_output=True)
        with aifc.open(out) as a:
            data = array.array("h", a.readframes(a.getnframes()))
    data.byteswap()
    return [x / 32768 for x in data]


def trim(signal, length, fade):
    peak = max(abs(x) for x in signal) or 1
    start = next(i for i, x in enumerate(signal) if abs(x) > peak * 0.02)
    start = max(0, start - int(0.004 * RATE))
    signal = signal[start:start + int(length * RATE)]
    fade_frames = int(fade * RATE)
    for i in range(fade_frames):
        index = len(signal) - fade_frames + i
        if index >= 0:
            signal[index] *= 0.5 * (1 + math.cos(math.pi * i / fade_frames))
    return signal


def pitch(signal, expected):
    """The fundamental near `expected`, by autocorrelation over the sustain,
    refined with a parabola through the peak."""
    window = signal[int(0.12 * RATE):int(0.12 * RATE) + int(0.25 * RATE)]
    best_lag, best = None, -1e9
    low = int(RATE / (expected * 2 ** (60 / 1200)))
    high = int(RATE / (expected * 2 ** (-60 / 1200))) + 1
    scores = {}
    for lag in range(max(2, low - 1), high + 2):
        score = sum(window[i] * window[i + lag] for i in range(len(window) - lag))
        scores[lag] = score
        if low <= lag <= high and score > best:
            best, best_lag = score, lag
    a, b, c = scores[best_lag - 1], scores[best_lag], scores[best_lag + 1]
    shift = 0.5 * (a - c) / (a - 2 * b + c) if (a - 2 * b + c) else 0
    return RATE / (best_lag + shift)


def write(signal, name):
    with wave.open(os.path.join(SAMPLES, name), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(array.array("h", (max(-32767, min(32767, int(x * 32767))) for x in signal)).tobytes())


def loudness(signal):
    head = signal[:int(0.5 * RATE)]
    return math.sqrt(sum(x * x for x in head) / len(head))


def piano_loudness():
    levels = []
    for name in sorted(os.listdir(SAMPLES)):
        if name.startswith("piano_"):
            levels.append(loudness(decode(os.path.join(SAMPLES, name))))
    return statistics.median(levels)


def regions(sfz, group_test):
    """(key or keycenter, sample, tune cents, volume dB) for the regions in
    the groups `group_test` accepts."""
    found, current, in_header = [], {}, False
    for line in open(sfz):
        line = line.split("//")[0]
        stripped = line.strip()
        if stripped.startswith("<group>") or stripped.startswith("<master>"):
            current, in_header = dict(re.findall(r"(\w+)=(\S+)", line)), True
            continue
        if in_header and not stripped.startswith("<"):
            # A group's settings can run over the lines after its header.
            current.update(re.findall(r"(\w+)=(\S+)", line))
            continue
        in_header = False
        if "<region>" in line and group_test(current):
            fields = dict(re.findall(r"(\w+)=(\S+)", line))
            root = int(fields.get("pitch_keycenter", fields.get("key", 0)))
            found.append((root, fields["sample"], float(fields.get("tune", 0)),
                          float(fields.get("volume", 0))))
    return found


def build(name, prefix, picks, folder, length, fade, target, lift=1.0):
    rows, processed = [], []
    for root, sample, tune, volume in sorted(set(picks)):
        signal = decode(os.path.join(folder, sample))
        signal = trim(signal, length, fade)
        gain = 10 ** (volume / 20)
        signal = [x * gain for x in signal]
        # The SFZ's tune is the correction it plays the sample with, so the
        # recording sits that many cents the other way.
        expected = nominal(root) * 2 ** (-tune / 1200)
        measured = pitch(signal, expected)
        cents = 1200 * math.log2(measured / expected)
        frequency = measured if abs(cents) < 40 else expected
        processed.append((root, signal, frequency, cents))
    scale = lift * target / statistics.median(loudness(s) for _, s, _, _ in processed)
    peak = max(max(abs(x) for x in s) for _, s, _, _ in processed) * scale
    if peak > 0.95:
        scale *= 0.95 / peak
    for root, signal, frequency, cents in processed:
        file = "%s_%03d.wav" % (prefix, root)
        write([x * scale for x in signal], file)
        rows.append((root, round(frequency, 2), file))
        print("%s %3d %8.2f Hz (%+.0f cents from expected)" % (name, root, frequency, cents))
    with open(os.path.join(HERE, "%s.csv" % name), "w") as handle:
        handle.write("# root,frequencyHz,filename - generated by build-instruments.py\n")
        for row in rows:
            handle.write("%d,%s,%s\n" % row)


def main():
    wurlitzer, guitar = sys.argv[1], sys.argv[2]
    target = piano_loudness()

    # Wurlitzer: the forte layer, a sample every five or six semitones.
    picks = regions(os.path.join(wurlitzer, "Wurlitzer EP200.sfz"),
                    lambda group: group.get("group_label") == "f")
    picks = [(root, sample.replace("$EXT", "flac"), tune, volume) for root, sample, tune, volume in picks]
    build("electric-piano", "epiano", picks, os.path.join(wurlitzer, "Samples"),
          length=4.0, fade=0.6, target=target)

    # Steel guitar: channel 1's first-position map, middle layer, every semitone.
    picks = []
    in_channel_one = False
    for line in open(os.path.join(guitar, "meta-steel-guitar.sfz")):
        if line.startswith("<master>"):
            in_channel_one = "lochan=1 hichan=1" in line
        if not in_channel_one:
            continue
        if line.startswith("<group>"):
            middle = "lovel=49" in line
        elif line.startswith("<region>") and middle:
            fields = dict(re.findall(r"(\w+)=(\S+)", line))
            picks.append((int(fields["key"]), fields["sample"], 0.0, 0.0))
    # A plucked note's energy is all in its first instant, so matched on
    # average loudness it still sounded quieter than the piano: lifted 3 dB.
    build("guitar", "guitar", picks, os.path.join(guitar, "ogg"),
          length=3.5, fade=0.5, target=target, lift=1.41)


if __name__ == "__main__":
    main()
