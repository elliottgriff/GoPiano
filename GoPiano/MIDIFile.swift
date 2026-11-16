//
//  MIDIFile.swift
//  GoPiano
//
//  A melody as notes rather than as sound: a Standard MIDI File that any DAW
//  will open, with every note editable afterwards. The audio take is a
//  performance; this is the performance's instructions, which is what someone
//  who wants to build on a melody actually needs.
//

import Foundation

enum MIDIExportError: LocalizedError {
    case noScore
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noScore:
            "This melody was saved before GoPiano recorded which keys were played, so there are no notes to export."
        case .writeFailed:
            "The MIDI file could not be written."
        }
    }
}

enum MIDIFile {
    /// Resolution of the written file. 480 divides cleanly by every note value
    /// a player is likely to hit, so nothing lands between ticks.
    static let ticksPerQuarterNote = 480

    /// Melodies are played freely against no click, so there is no tempo to
    /// preserve - only the real times the keys went down. Writing those times
    /// against a declared 120 bpm keeps them exact in seconds and lets a DAW
    /// show the melody over its own grid, unquantised, which is the honest
    /// representation of a free performance.
    static let microsecondsPerQuarterNote = 500_000

    private static let ticksPerSecond =
        Double(ticksPerQuarterNote) * 1_000_000 / Double(microsecondsPerQuarterNote)

    /// Acoustic grand piano, so the melody arrives sounding like what was played.
    private static let program: UInt8 = 0

    private static let channel: UInt8 = 0

    // MARK: - Writing

    /// Writes `score` to a temporary `.mid` file and returns it, ready to hand
    /// to the share sheet.
    static func write(_ score: MelodyScore, named name: String) throws -> URL {
        guard !score.isEmpty else { throw MIDIExportError.noScore }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFileName(name))
            .appendingPathExtension("mid")
        try? FileManager.default.removeItem(at: url)

        do {
            try data(for: score, named: name).write(to: url, options: .atomic)
        } catch {
            throw MIDIExportError.writeFailed
        }
        return url
    }

    /// The bytes of a format 0 file: one track holding every note.
    static func data(for score: MelodyScore, named name: String) -> Data {
        var file = Data()
        file.append(contentsOf: Array("MThd".utf8))
        file.append(uInt32: 6)
        file.append(uInt16: 0)                                  // format 0
        file.append(uInt16: 1)                                  // one track
        file.append(uInt16: UInt16(ticksPerQuarterNote))

        let track = trackData(for: score, named: name)
        file.append(contentsOf: Array("MTrk".utf8))
        file.append(uInt32: UInt32(track.count))
        file.append(track)
        return file
    }

    // MARK: - Track

    private static func trackData(for score: MelodyScore, named name: String) -> Data {
        var track = Data()

        // Meta events all sit at tick 0, before the first note.
        track.append(variableLength(0))
        track.append(contentsOf: [0xFF, 0x03])                  // track name
        let title = Array(name.utf8.prefix(127))
        track.append(variableLength(title.count))
        track.append(contentsOf: title)

        track.append(variableLength(0))
        track.append(contentsOf: [0xFF, 0x51, 0x03])            // tempo
        track.append(contentsOf: [
            UInt8((microsecondsPerQuarterNote >> 16) & 0xFF),
            UInt8((microsecondsPerQuarterNote >> 8) & 0xFF),
            UInt8(microsecondsPerQuarterNote & 0xFF),
        ])

        track.append(variableLength(0))
        track.append(contentsOf: [0xC0 | channel, program])     // program change

        var previous = 0
        for event in events(for: score) {
            track.append(variableLength(event.tick - previous))
            track.append(contentsOf: [
                (event.isOff ? 0x80 : 0x90) | channel,
                event.note,
                event.velocity,
            ])
            previous = event.tick
        }

        track.append(variableLength(0))
        track.append(contentsOf: [0xFF, 0x2F, 0x00])            // end of track
        return track
    }

    private struct Event {
        let tick: Int
        let isOff: Bool
        let note: UInt8
        let velocity: UInt8
    }

    private static func events(for score: MelodyScore) -> [Event] {
        var events: [Event] = []
        for span in score.spans {
            let start = ticks(span.start)
            // A note that rounds to zero length is dropped by some hosts, so
            // every note keeps at least one tick.
            let end = max(ticks(span.end), start + 1)
            events.append(Event(tick: start, isOff: false, note: span.note,
                                velocity: max(1, span.velocity)))
            events.append(Event(tick: end, isOff: true, note: span.note, velocity: 0))
        }

        // Releases are written before presses at the same tick: a key struck
        // again on the exact tick it was let go would otherwise have its new
        // note switched straight back off.
        return events.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.tick != rhs.element.tick { return lhs.element.tick < rhs.element.tick }
                if lhs.element.isOff != rhs.element.isOff { return lhs.element.isOff }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    private static func ticks(_ seconds: TimeInterval) -> Int {
        max(0, Int((seconds * ticksPerSecond).rounded()))
    }

    // MARK: - Helpers

    /// MIDI counts in seven-bit groups, most significant first, every byte but
    /// the last carrying a continuation bit.
    private static func variableLength(_ value: Int) -> Data {
        var remaining = max(0, value)
        var bytes = [UInt8(remaining & 0x7F)]
        remaining >>= 7
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        return Data(bytes)
    }

    private static func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "Melody" : cleaned
    }
}

private extension Data {
    mutating func append(uInt16 value: UInt16) {
        append(contentsOf: [UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    mutating func append(uInt32 value: UInt32) {
        append(contentsOf: [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }
}
