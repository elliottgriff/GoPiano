#!/usr/bin/env python3
"""Regenerates GoPiano/SampleMap.swift from Tools/samples.csv."""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "samples.csv")
DST = os.path.join(HERE, os.pardir, "GoPiano", "SampleMap.swift")

rows = []
with open(SRC) as handle:
    for line in handle:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        root, frequency, name = line.split(",")
        rows.append((int(root), float(frequency), name))

if not rows:
    sys.exit("no rows in %s" % SRC)
rows.sort()

body = "\n".join(
    '        Entry(root: %d, frequency: %s, file: "%s"),' % (root, frequency, name)
    for root, frequency, name in rows
)

with open(DST, "w") as handle:
    handle.write('''//
//  SampleMap.swift
//  GoPiano
//
//  GENERATED - do not edit by hand. Run Tools/build-samplemap.py instead.
//
//  `frequency` is each sample's real measured pitch, not the textbook pitch of
//  its root note. The samples were recorded slightly sharp and vary a little,
//  and handing the sampler the true frequency is what lets it retune each one
//  to concert pitch. See Tools/README.md.
//

struct SampleMap {
    struct Entry {
        let root: Int
        let frequency: Float
        let file: String
    }

    /// Sorted by root note, which `Conductor` relies on when it derives key ranges.
    static let entries: [Entry] = [
%s
    ]

    static let lowestSampledNote = %d
    static let highestSampledNote = %d
}
''' % (body, rows[0][0], rows[-1][0]))

print("wrote %s (%d entries, roots %d-%d)" % (DST, len(rows), rows[0][0], rows[-1][0]))
