#!/usr/bin/env python3
"""Regenerates GoPiano/SampleMap.swift from the instrument CSVs in Tools/."""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DST = os.path.join(HERE, os.pardir, "GoPiano", "SampleMap.swift")

# Each instrument's table: name in Swift, CSV beside this script.
INSTRUMENTS = [
    ("piano", "samples.csv"),
    ("electricPiano", "electric-piano.csv"),
    ("guitar", "guitar.csv"),
]


def read(name):
    rows = []
    with open(os.path.join(HERE, name)) as handle:
        for line in handle:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            root, frequency, file = line.split(",")
            rows.append((int(root), float(frequency), file))
    if not rows:
        sys.exit("no rows in %s" % name)
    return sorted(rows)


tables = [(swift, read(csv)) for swift, csv in INSTRUMENTS]
piano = tables[0][1]

blocks = []
for swift, rows in tables:
    body = "\n".join(
        '        Entry(root: %d, frequency: %s, file: "%s"),' % row for row in rows
    )
    blocks.append("    static let %s: [Entry] = [\n%s\n    ]" % (swift, body))

with open(DST, "w") as handle:
    handle.write('''//
//  SampleMap.swift
//  GoPiano
//
//  GENERATED - do not edit by hand. Run Tools/build-samplemap.py instead.
//
//  `frequency` is each sample's real measured pitch, not the textbook pitch of
//  its root note. The recordings run slightly sharp or flat and vary a little,
//  and handing the sampler the true frequency is what lets it retune each one
//  to concert pitch. See Tools/README.md.
//

struct SampleMap {
    struct Entry {
        let root: Int
        let frequency: Float
        let file: String
    }

    // Each sorted by root note, which `Conductor` relies on when it derives
    // key ranges.

%s

    static let lowestSampledNote = %d
    static let highestSampledNote = %d
}
''' % ("\n\n".join(blocks), piano[0][0], piano[-1][0]))

for swift, rows in tables:
    print("%s: %d entries, roots %d-%d" % (swift, len(rows), rows[0][0], rows[-1][0]))
print("wrote %s" % DST)
