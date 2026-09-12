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

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
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
    private var open: [UInt8: TimeInterval] = [:]

    mutating func reset() {
        finished.removeAll()
        open.removeAll()
    }

    mutating func noteOn(_ note: UInt8, at time: TimeInterval) {
        guard open[note] == nil else { return }
        open[note] = time
    }

    mutating func noteOff(_ note: UInt8, at time: TimeInterval) {
        guard let start = open.removeValue(forKey: note) else { return }
        finished.append(NoteSpan(note: note, start: start, end: max(time, start + 0.05)))
    }

    /// Closes anything still held and returns the finished score.
    mutating func finish(at time: TimeInterval) -> MelodyScore {
        for (note, start) in open {
            finished.append(NoteSpan(note: note, start: start, end: max(time, start + 0.05)))
        }
        open.removeAll()
        finished.sort { $0.start < $1.start }
        return MelodyScore(spans: finished, duration: max(time, finished.map(\.end).max() ?? 0))
    }
}
