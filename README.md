# GoPiano

A playable multi-touch piano for iPhone and iPad: hold down chords, slide between
keys, record what you play, then watch it back on the keyboard or share it as a
video with the keys lighting up.

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

Two more things worth knowing about the sampler:

- The first MIDI event costs the best part of a second in lazy setup. That is
  spent at launch with a note-off, or it lands on the first key the player
  touches - delaying the sound, and the note written into a take with it.
- Do not call `silence()`. It calls `stopAllVoices()`, which sets a flag that
  only `restartVoices()` clears, so the sampler goes quiet permanently.

Touches are tracked by a `UIGestureRecognizer` rather than a `UIView`'s own
touch methods, because raw view touches get cancelled when an ancestor
recognizer claims the sequence.

Each sample also declares its own key range. The key map matches a note against
every sample whose range contains it and takes the first hit, so leaving the
ranges wide open makes one sample answer for the whole keyboard.

## Replay and video

Recording a take captures the notes as well as the audio: one span per note held
down, in `MelodyScore`. Tapping a melody plays it on the keyboard with the keys
lighting up, and **Share Video** renders it as an MP4 - the keyboard drawn frame
by frame from those spans, muxed with the melody's own audio.

Nothing is screen-captured, so an exported video has no status bar, no fingers
and no UI chrome. It is also framed to the notes that were actually played
rather than to whatever the octave controls happened to be set to.

`KeyboardRenderer` is the single drawing routine behind both the live keyboard
and the video, so the two cannot drift apart.

Melodies saved before this existed have no score: they still play and share as
audio, and **Share Video** is simply unavailable for them.

## Saving and sharing

Saved melodies are encoded to AAC in an `.m4a` container and kept in the app's
Documents folder. They survive relaunches, show up in the Files app under
GoPiano, and go straight to the share sheet from the melody list.

The recorder itself writes uncompressed float CAF, which runs to roughly 20 MB a
minute and which plenty of apps refuse to open, so saving converts. A minute of
playing lands around 1 MB.

## Sound

The piano is multi-sampled across MIDI 21-84 (A0 to C6) and pitched from the
nearest sample outside that. Tuning was calibrated against captured output;
across the sampled range the played pitch lands within a few cents of equal
temperament. `Tools/README.md` covers where the samples came from.
