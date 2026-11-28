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

## Electric piano and guitar

`electric-piano.csv` and `guitar.csv` are written by `build-instruments.py`,
which builds both sets from their source packs:

    ./Tools/build-instruments.py "<…>/Wurlitzer EP200" "<…>/meta-steel-guitar"

- **Electric piano:** the Wurlitzer EP200 from Greg Sullivan's E-Pianos
  (github.com/sfzinstruments/GregSullivan.E-Pianos), CC BY 3.0. The forte layer
  only: twelve samples, a root every five or six semitones from A1 to G#6.
- **Guitar:** the steel-string acoustic from Meta Open Sound
  (github.com/facebookincubator/Meta-open-sound, the OGG release), CC0. One
  sample per semitone from E2 to C6, each on the string the pack's own map
  plays it on in first position, middle velocity layer.

Each sample is converted to 22.05 kHz mono, trimmed to the start of the note,
cut to 4 s (electric piano) or 3.5 s (guitar) with a fade, and scaled so the
set's typical loudness matches the piano's. Its pitch is measured over the
sustain and that frequency declared, as for the piano, so the sampler retunes it
to concert pitch. The Wurlitzer measured within 4 cents of its map's own tuning;
the guitar runs a few cents sharp, as strings do.

The source packs aren't kept in the repository; download them again to rebuild.

## build-icon.swift

Draws the app icon - five keys under the felt, A lit in its note colour and
joined by a beam to its note above - in the three appearances iOS asks for:
`AppIcon.png`, `AppIcon-Dark.png` and `AppIcon-Tinted.png` (grey, which the
system colours). Colours and key proportions are the app's own, from
`KeyboardRenderer`. Regenerate the icon set with:

    swift Tools/build-icon.swift GoPiano/Assets.xcassets/AppIcon.appiconset \
        GoPiano/Assets.xcassets/Logo.imageset

The second folder gets `Logo.png`, the icon at 256 px, which the sheet music
PDF prints beside "Made with GoPiano" at the foot of each page.
