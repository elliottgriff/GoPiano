//
//  MelodyScore.swift
//  GoPiano
//
//  What was played, as data rather than pixels: one span per note held down.
//  Spans answer "which keys are down at time t" with a plain lookup, which is
//  what both on-screen replay and video rendering need, and unlike a stream of
//  on/off events they survive pausing and seeking.
//

import Foundation

struct NoteSpan: Codable, Hashable {
    let note: UInt8
    let start: TimeInterval
    var end: TimeInterval

    /// How hard the key was struck, on the MIDI scale. Carried so an exported
    /// MIDI file keeps the dynamics of the performance instead of flattening
    /// every note to the same weight.
    var velocity: UInt8

    /// Where the note falls and how long it lasts, in quarter-note beats -
    /// known only for music that came with a beat, such as an imported MIDI
    /// file. It is what lets sheet music write a note's value rather than
    /// guess it from seconds. Nil for anything played freely.
    var beat: Double?
    var beats: Double?

    init(note: UInt8, start: TimeInterval, end: TimeInterval, velocity: UInt8 = 100,
         beat: Double? = nil, beats: Double? = nil) {
        self.note = note
        self.start = start
        self.end = end
        self.velocity = velocity
        self.beat = beat
        self.beats = beats
    }

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }

    private enum CodingKeys: String, CodingKey {
        case note, start, end, velocity, beat, beats
    }

    /// Melodies recorded before velocity was captured have no such key, and
    /// decode at a steady mezzo-forte rather than failing to open.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = try container.decode(UInt8.self, forKey: .note)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        velocity = try container.decodeIfPresent(UInt8.self, forKey: .velocity) ?? 100
        beat = try container.decodeIfPresent(Double.self, forKey: .beat)
        beats = try container.decodeIfPresent(Double.self, forKey: .beats)
    }
}

/// How many beats make a bar, and what kind of note gets one: 4/4, 3/4, 6/8.
struct TimeSignature: Codable, Hashable {
    let beats: Int
    let unit: Int

    static let common = TimeSignature(beats: 4, unit: 4)

    /// A bar's length in quarter notes - the unit every beat here is counted in.
    var barLength: Double { Double(beats) * 4 / Double(unit) }
}

struct MelodyScore: Codable, Hashable {
    var spans: [NoteSpan] = []
    var duration: TimeInterval = 0
    /// Set only for music that came with a beat. With it, sheet music can be
    /// written in bars with real note values; without it, notes are written
    /// in the order they were played.
    var timeSignature: TimeSignature?
    /// Beats per minute, for music played to the metronome. Lets an exported
    /// MIDI file carry the tempo it was played at, so a DAW's grid lines up.
    var tempo: Double?
    /// Whether the recording is of a voice - sung into the microphone, or an
    /// imported voice memo - rather than of the keys. Its notes were heard,
    /// not played, so they can be played back on any instrument.
    var isSung: Bool?

    var isEmpty: Bool { spans.isEmpty }

    func notes(at time: TimeInterval) -> Set<UInt8> {
        Set(spans.lazy.filter { $0.contains(time) }.map(\.note))
    }

    var noteRange: ClosedRange<UInt8>? {
        guard let low = spans.map(\.note).min(), let high = spans.map(\.note).max() else {
            return nil
        }
        return low...high
    }

    /// A keyboard wide enough to show every note that was played, snapped to
    /// whole octaves. Used for video framing, where nobody is there to move the
    /// octave controls.
    func framing(maximumOctaves: Int = 4) -> (firstOctave: Int, octaveCount: Int) {
        guard let range = noteRange else { return (3, 1) }
        let first = (Int(range.lowerBound) - baseMIDINote) / 12
        let last = (Int(range.upperBound) - baseMIDINote) / 12
        let needed = max(1, last - first + 1)
        guard needed > maximumOctaves else { return (max(0, first), needed) }

        // Wider than the keyboard can show - an imported piece, usually. Frame
        // the stretch where most of the playing happens: starting from the
        // bottom would keep the bass and cut off the tune.
        let busiest = (max(0, first)...max(0, last - maximumOctaves + 1)).max { lhs, rhs in
            noteCount(fromOctave: lhs, octaves: maximumOctaves)
                < noteCount(fromOctave: rhs, octaves: maximumOctaves)
        } ?? max(0, first)
        return (busiest, maximumOctaves)
    }

    /// Notes that land on a keyboard of `octaves` starting at `fromOctave`,
    /// counting the C it ends on.
    private func noteCount(fromOctave octave: Int, octaves: Int) -> Int {
        let low = baseMIDINote + octave * 12
        let high = low + octaves * 12
        return spans.lazy.filter { Int($0.note) >= low && Int($0.note) <= high }.count
    }
}

/// Collects spans while a take is being recorded.
struct ScoreRecorder {
    private var finished: [NoteSpan] = []
    private var open: [UInt8: (start: TimeInterval, velocity: UInt8)] = [:]

    mutating func reset() {
        finished.removeAll()
        open.removeAll()
    }

    mutating func noteOn(_ note: UInt8, velocity: UInt8, at time: TimeInterval) {
        guard open[note] == nil else { return }
        open[note] = (time, velocity)
    }

    mutating func noteOff(_ note: UInt8, at time: TimeInterval) {
        guard let held = open.removeValue(forKey: note) else { return }
        finished.append(NoteSpan(note: note,
                                 start: held.start,
                                 end: max(time, held.start + 0.05),
                                 velocity: held.velocity))
    }

    /// The take so far, with notes still held lasting until `time`.
    func snapshot(at time: TimeInterval) -> [NoteSpan] {
        finished + open.map { note, held in
            NoteSpan(note: note, start: held.start,
                     end: max(time, held.start + 0.05), velocity: held.velocity)
        }
    }

    /// Closes anything still held and returns the finished score.
    mutating func finish(at time: TimeInterval) -> MelodyScore {
        for (note, held) in open {
            finished.append(NoteSpan(note: note,
                                     start: held.start,
                                     end: max(time, held.start + 0.05),
                                     velocity: held.velocity))
        }
        open.removeAll()
        finished.sort { $0.start < $1.start }
        return MelodyScore(spans: finished, duration: max(time, finished.map(\.end).max() ?? 0))
    }
}
