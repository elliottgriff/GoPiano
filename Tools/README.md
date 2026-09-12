# Tools

## samples.csv

The source of truth for the sampled piano: one row per sample, as
`rootNote,frequencyHz,filename`, sorted by root note.

`frequencyHz` is each sample's **measured** pitch, not the textbook frequency of
its root note. The recordings run a little sharp and vary between notes, and
DunneAudioKit's sampler retunes a sample by the ratio between the pitch you
declare and the pitch you ask for — so declaring the true frequency is what
makes the instrument play in tune.

Those frequencies were calibrated in a loop: render every note, measure what
actually came out, fold the error back into the declared frequency, repeat.
Across the sampled range (MIDI 21-84) the played pitch lands within a few cents.

`GoPiano/SampleMap.swift` is generated from this file — regenerate it with:

    ./Tools/build-samplemap.py

## Sample provenance

The samples are the "jobro" piano set from freesound.org (keys 1-27 and 41-64,
where MIDI note = key number + 20) plus a separately recorded chromatic octave
covering MIDI 48-60. Keys 85-88 were excluded: their pitch could not be measured
reliably, since at the 11 kHz source rate those notes sit near the Nyquist limit.

Note MIDI 80 has no sample of its own and is pitched from its neighbours.
