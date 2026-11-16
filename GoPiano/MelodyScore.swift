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

    init(note: UInt8, start: TimeInterval, end: TimeInterval, velocity: UInt8 = 100) {
        self.note = note
        self.start = start
        self.end = end
        self.velocity = velocity
    }

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }

    private enum CodingKeys: String, CodingKey {
        case note, start, end, velocity
    }

    /// Melodies recorded before velocity was captured have no such key, and
    /// decode at a steady mezzo-forte rather than failing to open.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        note = try container.decode(UInt8.self, forKey: .note)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        velocity = try container.decodeIfPresent(UInt8.self, forKey: .velocity) ?? 100
    }
}

struct MelodyScore: Codable, Hashable {
    var spans: [NoteSpan] = []
    var duration: TimeInterval = 0

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
        let count = min(maximumOctaves, max(1, last - first + 1))
        return (max(0, first), count)
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
