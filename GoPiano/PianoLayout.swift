//
//  PianoLayout.swift
//  GoPiano
//
//  Key geometry and hit testing, kept separate from drawing so the same
//  numbers decide what is painted and what a touch lands on.
//

import CoreGraphics

/// MIDI note 24 is the C of octave 0 in the octave numbering the controls use,
/// so the default (octave 3) starts the keyboard at middle C.
let baseMIDINote = 24

struct PianoKey: Identifiable, Equatable {
    let note: UInt8
    let isBlack: Bool
    let frame: CGRect

    var id: UInt8 { note }
}

struct PianoLayout {
    /// Semitone offsets of the white keys within an octave.
    static let whiteSemitones = [0, 2, 4, 5, 7, 9, 11]
    /// Black keys, as (index of the white key they sit after, semitone).
    static let blackSemitones: [(after: Int, semitone: Int)] =
        [(0, 1), (1, 3), (3, 6), (4, 8), (5, 10)]

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    let firstOctave: Int
    let octaveCount: Int
    let size: CGSize

    /// A trailing C is included so the keyboard ends on a whole octave.
    var whiteKeyCount: Int { octaveCount * 7 + 1 }
    var whiteKeyWidth: CGFloat { size.width / CGFloat(whiteKeyCount) }
    var blackKeyWidth: CGFloat { whiteKeyWidth * 0.62 }
    var blackKeyHeight: CGFloat { keyLength * 0.62 }

    /// The longest a white key gets, as a multiple of its width. A real one is
    /// about six and a half times as long as it is wide; a little more is
    /// kinder to fingers. Without a limit, three octaves on a 13-inch iPad
    /// drew keys fifteen times longer than wide - sticks, not keys. On an iPad
    /// the height this frees holds the score (see ContentView.keyboardArea).
    static let longestKeyRatio: CGFloat = 7

    /// The limit for this layout. The video loosens it: a frame has no score
    /// to fill the space above, so its keys are allowed to run longer.
    var maxKeyRatio: CGFloat = PianoLayout.longestKeyRatio

    /// How long the keys are: the full height, unless that would stretch them
    /// past real proportions.
    var keyLength: CGFloat { min(size.height, whiteKeyWidth * maxKeyRatio) }

    /// Where the keys begin. When there is more height than the keys should
    /// have - an iPad, or a video frame of several octaves - they sit at the
    /// front, under the player's hands, and the space above is the case of the
    /// instrument. A phone's keyboard is never tall enough for this to apply.
    var keyTop: CGFloat { max(0, size.height - keyLength) }

    private func note(octave: Int, semitone: Int) -> UInt8 {
        let value = (firstOctave + octave) * 12 + semitone + baseMIDINote
        return UInt8(clamping: value)
    }

    var whiteKeys: [PianoKey] {
        var keys: [PianoKey] = []
        for index in 0..<whiteKeyCount {
            let octave = index / 7
            let semitone = Self.whiteSemitones[index % 7]
            let frame = CGRect(x: CGFloat(index) * whiteKeyWidth, y: keyTop,
                               width: whiteKeyWidth, height: keyLength)
            keys.append(PianoKey(note: note(octave: octave, semitone: semitone),
                                 isBlack: false, frame: frame))
        }
        return keys
    }

    var blackKeys: [PianoKey] {
        var keys: [PianoKey] = []
        for octave in 0..<octaveCount {
            for entry in Self.blackSemitones {
                // Straddle the boundary between two white keys.
                let boundary = CGFloat(octave * 7 + entry.after + 1) * whiteKeyWidth
                let frame = CGRect(x: boundary - blackKeyWidth / 2, y: keyTop,
                                   width: blackKeyWidth, height: blackKeyHeight)
                keys.append(PianoKey(note: note(octave: octave, semitone: entry.semitone),
                                     isBlack: true, frame: frame))
            }
        }
        return keys
    }

    var allKeys: [PianoKey] { whiteKeys + blackKeys }

    /// Black keys sit above white ones, so they are tested first.
    func key(at point: CGPoint) -> PianoKey? {
        guard point.x >= 0, point.x <= size.width, point.y >= 0, point.y <= size.height else {
            return nil
        }
        if let hit = blackKeys.first(where: { $0.frame.contains(point) }) { return hit }
        return whiteKeys.first { $0.frame.contains(point) }
    }

    func note(at point: CGPoint) -> UInt8? { key(at: point)?.note }

    /// How hard the note sounds, from where the key was struck: towards the
    /// player is louder, the way pressing further into a key is. Real velocity
    /// needs pressure the screen cannot measure, and touch area is too noisy to
    /// play with, but position is predictable and works on every device.
    static func velocity(for point: CGPoint, on key: PianoKey) -> UInt8 {
        guard key.frame.height > 0 else { return 100 }
        let depth = (point.y - key.frame.minY) / key.frame.height
        let eased = min(max(depth, 0), 1)
        return UInt8(58 + eased * 69)   // 58...127, never inaudible
    }

    static func name(for note: UInt8) -> String {
        let value = Int(note)
        return noteNames[((value % 12) + 12) % 12] + String(value / 12 - 1)
    }
}
