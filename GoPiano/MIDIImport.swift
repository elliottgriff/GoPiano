//
//  MIDIImport.swift
//  GoPiano
//
//  The other direction from MIDIFile: someone else's Standard MIDI File read
//  into a MelodyScore, so the keyboard can perform it.
//
//  Reading is handed to AudioToolbox's MusicSequence rather than done by hand.
//  Real files are far messier than the ones GoPiano writes - format 1 with a
//  track per instrument is what every DAW exports, running status is
//  everywhere, and tempo changes mean ticks only become seconds by walking the
//  tempo map. MusicSequence already does all of that, and hands back each
//  note's velocity and its time in seconds.
//

import AudioToolbox
import Foundation

enum MIDIImportError: LocalizedError {
    case unreadable
    case noNotes

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "That file could not be read as MIDI."
        case .noNotes:
            "That file has no notes the keyboard can play. Drum tracks are left out, since they make no sense on a piano."
        }
    }
}

enum MIDIImport {
    /// General MIDI puts percussion on channel 10, which counts from zero as 9.
    /// Mapped onto a keyboard those notes are drum sounds pitched as random
    /// piano keys, so they are dropped rather than played.
    private static let percussionChannel: UInt8 = 9

    /// The shortest note kept, matching what the recorder allows. A note that
    /// rounds to nothing never sounds and never lights a key.
    private static let shortestNote: TimeInterval = 0.05

    static func score(from url: URL) throws -> MelodyScore {
        // Files from the document picker live outside the sandbox, and can only
        // be read between these two calls.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        var created: MusicSequence?
        guard NewMusicSequence(&created) == noErr, let sequence = created else {
            throw MIDIImportError.unreadable
        }
        defer { DisposeMusicSequence(sequence) }

        guard MusicSequenceFileLoad(sequence, url as CFURL, .midiType, []) == noErr else {
            throw MIDIImportError.unreadable
        }

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)

        var spans: [NoteSpan] = []
        for index in 0..<trackCount {
            var track: MusicTrack?
            guard MusicSequenceGetIndTrack(sequence, index, &track) == noErr,
                  let track else { continue }
            spans += notes(in: track, of: sequence)
        }

        guard let firstStart = spans.map(\.start).min() else {
            throw MIDIImportError.noNotes
        }

        // The file's own beat, so its sheet music can be written in bars with
        // real note values. A file that doesn't say is in 4/4, as the MIDI
        // standard has it.
        let signature = timeSignature(of: sequence) ?? .common

        // Files often open with a bar or two of silence - a count-in, or room
        // for a pickup. Played on the keyboard that is just a wait in front of
        // a dark keyboard, so the melody starts on its first note instead. The
        // beats move back by whole bars only, so the bar lines still fall
        // where the file put them.
        let firstBeat = spans.compactMap(\.beat).min() ?? 0
        let barShift = (firstBeat / signature.barLength).rounded(.down) * signature.barLength
        let shifted = spans
            .map { NoteSpan(note: $0.note,
                            start: $0.start - firstStart,
                            end: $0.end - firstStart,
                            velocity: $0.velocity,
                            beat: $0.beat.map { $0 - barShift },
                            beats: $0.beats) }
            .sorted { $0.start < $1.start }

        return MelodyScore(spans: shifted,
                           duration: shifted.map(\.end).max() ?? 0,
                           timeSignature: signature)
    }

    /// The first time signature in the file, if it has one.
    private static func timeSignature(of sequence: MusicSequence) -> TimeSignature? {
        var found: MusicTrack?
        guard MusicSequenceGetTempoTrack(sequence, &found) == noErr, let track = found else {
            return nil
        }
        var created: MusicEventIterator?
        guard NewMusicEventIterator(track, &created) == noErr, let iterator = created else {
            return nil
        }
        defer { DisposeMusicEventIterator(iterator) }

        var hasEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        while hasEvent.boolValue {
            var beat: MusicTimeStamp = 0
            var type: MusicEventType = 0
            var data: UnsafeRawPointer?
            var size: UInt32 = 0
            MusicEventIteratorGetEventInfo(iterator, &beat, &type, &data, &size)
            if type == kMusicEventType_Meta, let data {
                let meta = data.loadUnaligned(as: MIDIMetaEvent.self)
                // 0x58 is a time signature: numerator, then the denominator
                // as a power of two.
                if meta.metaEventType == 0x58, meta.dataLength >= 2 {
                    let bytes = data + (MemoryLayout<MIDIMetaEvent>.offset(of: \MIDIMetaEvent.data) ?? 8)
                    let beats = Int(bytes.load(as: UInt8.self))
                    let power = Int(bytes.load(fromByteOffset: 1, as: UInt8.self))
                    if (1...16).contains(beats), (1...4).contains(power) {
                        return TimeSignature(beats: beats, unit: 1 << power)
                    }
                }
            }
            MusicEventIteratorNextEvent(iterator)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        }
        return nil
    }

    private static func notes(in track: MusicTrack, of sequence: MusicSequence) -> [NoteSpan] {
        var created: MusicEventIterator?
        guard NewMusicEventIterator(track, &created) == noErr, let iterator = created else {
            return []
        }
        defer { DisposeMusicEventIterator(iterator) }

        var spans: [NoteSpan] = []
        var hasEvent: DarwinBoolean = false
        MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)

        while hasEvent.boolValue {
            var beat: MusicTimeStamp = 0
            var type: MusicEventType = 0
            var data: UnsafeRawPointer?
            var size: UInt32 = 0
            MusicEventIteratorGetEventInfo(iterator, &beat, &type, &data, &size)

            if type == kMusicEventType_MIDINoteMessage, let data {
                let message = data.loadUnaligned(as: MIDINoteMessage.self)
                if message.channel != percussionChannel {
                    // Positions and durations are in beats; going through the
                    // sequence turns them into seconds with every tempo change
                    // along the way taken into account.
                    var start: Float64 = 0
                    var end: Float64 = 0
                    MusicSequenceGetSecondsForBeats(sequence, beat, &start)
                    MusicSequenceGetSecondsForBeats(sequence, beat + MusicTimeStamp(message.duration), &end)
                    spans.append(NoteSpan(note: message.note,
                                          start: start,
                                          end: max(end, start + shortestNote),
                                          velocity: max(1, message.velocity),
                                          beat: beat,
                                          beats: Double(message.duration)))
                }
            }

            MusicEventIteratorNextEvent(iterator)
            MusicEventIteratorHasCurrentEvent(iterator, &hasEvent)
        }
        return spans
    }
}
