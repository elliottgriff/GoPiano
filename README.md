# GoPiano

A playable multi-touch piano for iPhone and iPad: hold down chords, slide between
keys, record what you play and keep the takes.

<img width=455 src="https://user-images.githubusercontent.com/34309823/54627395-b6b69d80-4a49-11e9-973a-0c63cdde9e3a.PNG">
<img width=455 src="https://user-images.githubusercontent.com/34309823/54627396-b74f3400-4a49-11e9-892f-b3bc8b180982.PNG">

*(Screenshots are from version 1.x and predate the SwiftUI rewrite.)*

## Building

Open `GoPiano.xcodeproj` and run. Swift Package Manager pulls
[AudioKit](https://github.com/AudioKit/AudioKit) and
[DunneAudioKit](https://github.com/AudioKit/DunneAudioKit) on first build;
no other setup is needed.

Requires Xcode 16 or newer and iOS 17.

## How it works

- **`Conductor`** owns the audio graph: a multi-sampled piano into reverb, tapped
  by a recorder, plus a player for listening back.
- **`PianoLayout`** holds the key geometry and hit testing, so the same numbers
  decide what gets drawn and what a touch lands on.
- **`KeyboardView`** draws the keyboard with a SwiftUI `Canvas` and takes touches
  from **`TouchTracker`**, a small `UIView` bridge. SwiftUI gestures only track
  one finger, which is no use for a piano.
- **`SampleMap`** is generated from `Tools/samples.csv` — see `Tools/README.md`.

Two ordering constraints in the audio setup are load-bearing, and both are
commented at the call site in `Conductor.start()`:

1. The engine must be **started before** the samples are handed to the sampler.
   Its DSP only learns the real hardware sample rate once running, and swapping
   in sampler data re-initialises the core sampler with whatever rate it knows
   at that moment. Load first and every note plays about 1.5 semitones sharp.
2. Sampler parameters must be set **before** that swap, not after — the swap
   copies envelope settings across from the current sampler, and writes made
   straight after it are rejected.

Each sample also declares its own key range. The key map matches a note against
every sample whose range contains it and takes the first hit, so leaving the
ranges wide open makes one sample answer for the whole keyboard.

## Sound

The piano is multi-sampled across MIDI 21-84 (A0 to C6) and pitched from the
nearest sample outside that. Tuning was calibrated against captured output;
across the sampled range the played pitch lands within a few cents of equal
temperament. `Tools/README.md` covers where the samples came from.
