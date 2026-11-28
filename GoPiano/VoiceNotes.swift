//
//  VoiceNotes.swift
//  GoPiano
//
//  Hearing notes in a voice: the pitch of a single sung, hummed or whistled
//  line, followed frame by frame and split into notes. The same two pieces run
//  live on the microphone and over a recording - a voice memo of a melody
//  idea - so what's heard while singing is what an imported memo becomes.
//
//  One voice at a time: a chord, a band or a strummed guitar has no single
//  pitch to follow, and comes out as whichever note is loudest at the moment.
//

import Accelerate
import AVFoundation
import Foundation
import os
import UniformTypeIdentifiers

/// The pitch of one frame of audio, by YIN (de Cheveigné & Kawahara, 2002):
/// how unlike itself the frame is at each lag, normalised so the first deep
/// dip is the period. Robust to the strong harmonics of a voice, which fool a
/// plain autocorrelation into jumping an octave.
struct PitchTracker {
    let sampleRate: Double
    /// About 46 ms at 44.1 kHz: two periods of the lowest note it listens for.
    let frameSize = 2048
    /// Lowest and highest pitches it listens for: C2, below a bass's low
    /// notes, to C7, the top of a whistle.
    let lowest = 64.0
    let highest = 2100.0
    /// Frames quieter than this (RMS) are taken as silence. A recording is
    /// brought up to a working level first; the microphone is not, so it
    /// listens a little lower.
    var gate: Float = 0.008
    /// Only clear pitches: no settling for the best of a weak dip. A
    /// recording takes what it can get from a breathy take; live, a fan or a
    /// conversation across the room would light keys nobody sang.
    var strict = false

    /// A frame's fundamental, and how sure of it the frame is (0...1), or nil
    /// for silence and noise.
    func pitch(of frame: UnsafeBufferPointer<Float>) -> (frequency: Double, clarity: Double)? {
        let window = frameSize / 2
        guard frame.count >= frameSize, let start = frame.baseAddress else { return nil }

        // Too quiet to be singing.
        guard Self.level(of: frame) > gate else { return nil }

        let minLag = max(2, Int(sampleRate / highest))
        let maxLag = min(window - 1, Int(sampleRate / lowest))
        guard maxLag > minLag + 2 else { return nil }

        // d(τ) = e(0) + e(τ) - 2r(τ), with r the autocorrelation over one
        // window - one vDSP call rather than a loop per lag.
        var correlation = [Float](repeating: 0, count: maxLag + 1)
        vDSP_conv(start, 1, start, 1, &correlation, 1, vDSP_Length(maxLag + 1), vDSP_Length(window))
        var energy: Float = 0
        vDSP_svesq(start, 1, &energy, vDSP_Length(window))
        var shifted = energy
        var difference = [Float](repeating: 0, count: maxLag + 1)
        for lag in 1...maxLag {
            let leaving = start[lag - 1], arriving = start[lag - 1 + window]
            shifted += arriving * arriving - leaving * leaving
            difference[lag] = max(0, energy + shifted - 2 * correlation[lag])
        }

        // Cumulative mean normalised difference: 1 at lag zero, dipping
        // towards 0 at each period.
        var normalised = [Float](repeating: 1, count: maxLag + 1)
        var running: Float = 0
        for lag in 1...maxLag {
            running += difference[lag]
            normalised[lag] = running > 0 ? difference[lag] * Float(lag) / running : 1
        }

        // The first dip under the threshold, followed to its bottom; failing
        // that, the deepest dip, if it is deep enough to trust at all.
        var lag = -1
        var candidate = minLag
        while candidate <= maxLag {
            if normalised[candidate] < 0.15 {
                while candidate + 1 <= maxLag, normalised[candidate + 1] < normalised[candidate] {
                    candidate += 1
                }
                lag = candidate
                break
            }
            candidate += 1
        }
        if lag < 0 {
            guard !strict else { return nil }
            var deepest = minLag
            for index in minLag...maxLag where normalised[index] < normalised[deepest] {
                deepest = index
            }
            guard normalised[deepest] < 0.35 else { return nil }
            lag = deepest
        }

        // An octave low is YIN's usual slip: when the true period's dip is
        // shallow, as it is through a room or a phone's speaker, the dip at
        // twice the period can cross the threshold first. If half the lag dips
        // nearly as deep, that is the note.
        let half = lag / 2
        if half >= minLag {
            var best = half
            for index in max(minLag, half - 2)...min(maxLag, half + 2) where normalised[index] < normalised[best] {
                best = index
            }
            if normalised[best] < 0.3, normalised[best] < normalised[lag] + 0.12 { lag = best }
        }

        // A parabola through the dip places it between samples.
        var refined = Double(lag)
        if lag > minLag, lag < maxLag {
            let before = Double(normalised[lag - 1]), at = Double(normalised[lag]),
                after = Double(normalised[lag + 1])
            let curve = before - 2 * at + after
            if curve > 0 { refined += 0.5 * (before - after) / curve }
        }
        let frequency = sampleRate / refined
        guard frequency >= lowest * 0.95, frequency <= highest * 1.05 else { return nil }
        return (frequency, Double(max(0, 1 - normalised[lag])))
    }

    /// How loud a frame is: its RMS.
    static func level(of frame: UnsafeBufferPointer<Float>) -> Float {
        guard let start = frame.baseAddress, !frame.isEmpty else { return 0 }
        var power: Float = 0
        vDSP_svesq(start, 1, &power, vDSP_Length(frame.count))
        return sqrt(power / Float(frame.count))
    }

    static func midi(for frequency: Double) -> Double {
        69 + 12 * log2(frequency / 440)
    }
}

/// Turns a stream of pitches into notes. A voice never sits exactly on a
/// note: it scoops into it, wavers with vibrato and slides out. So a note
/// starts only once a pitch has held for a moment, survives wobbles of most of
/// a semitone, and ends after a short silence or once a new pitch has held.
/// The same note sung twice is told apart by the dip in loudness between
/// them - a breath, or the consonant of "la-la" - even when the pitch never
/// stops.
struct NoteSplitter {
    /// How long a new pitch must hold before it counts as a note.
    var settle: TimeInterval = 0.05
    /// How long a gap must last before the note is over.
    var release: TimeInterval = 0.06
    /// How far the voice may wander from the note before it's a different one.
    var tolerance = 0.75

    private(set) var current: (note: UInt8, start: TimeInterval)?
    private var candidate: (note: UInt8, since: TimeInterval)?
    private var silentSince: TimeInterval?
    /// The note's recent loudest, easing down over time so a note that
    /// gently fades isn't mistaken for a breath.
    private var peak: Float = 0
    private var dippedAt: TimeInterval?
    private var lastTime: TimeInterval?

    enum Event {
        case began(UInt8, at: TimeInterval)
        case ended(UInt8, at: TimeInterval)
    }

    /// Takes one frame: when it was, how loud (RMS), and the pitch heard in
    /// it as a MIDI number (fractional), or nil for none. Returns what changed.
    mutating func take(_ midi: Double?, level: Float, at time: TimeInterval) -> [Event] {
        var events: [Event] = []
        let elapsed = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time
        peak *= Float(pow(0.5, elapsed / 0.6))

        guard let midi, (24...108).contains(midi) else {
            candidate = nil
            if silentSince == nil { silentSince = time }
            if let current, let silentSince, time - silentSince >= release {
                events.append(.ended(current.note, at: silentSince))
                self.current = nil
                dippedAt = nil
            }
            return events
        }
        silentSince = nil

        if let current, abs(midi - Double(current.note)) < tolerance {
            candidate = nil
            // A breath between two of the same note: loudness falls away,
            // then comes back.
            // About 10 dB down: deeper than the swell and fade of vibrato,
            // which moves loudness as well as pitch.
            if level < peak * 0.3 {
                if dippedAt == nil { dippedAt = time }
            } else if let dip = dippedAt, level > peak * 0.6 {
                events.append(.ended(current.note, at: dip))
                events.append(.began(current.note, at: time))
                self.current = (current.note, time)
                dippedAt = nil
                peak = level
            }
            peak = max(peak, level)
            return events
        }

        let nearest = UInt8(midi.rounded())
        if let candidate, candidate.note == nearest {
            if time - candidate.since >= settle {
                if let current { events.append(.ended(current.note, at: candidate.since)) }
                current = (nearest, candidate.since)
                events.append(.began(nearest, at: candidate.since))
                self.candidate = nil
                dippedAt = nil
                peak = level
            }
        } else {
            candidate = (nearest, time)
        }
        return events
    }

    /// The end of the audio, or of listening: whatever is sounding stops here.
    mutating func finish(at time: TimeInterval) -> [Event] {
        defer {
            current = nil; candidate = nil; silentSince = nil
            dippedAt = nil; peak = 0; lastTime = nil
        }
        guard let current else { return [] }
        return [.ended(current.note, at: silentSince ?? time)]
    }
}

/// Follows a voice live, buffer by buffer from the microphone. It runs on
/// whatever thread the input tap delivers on, keeping its own state there, and
/// reports each note's start and end on the main thread, stamped in host time
/// (the clock `CACurrentMediaTime` reads) at the moment it was sung - not when
/// it was recognised, a few tens of milliseconds later.
final class VoiceListener {
    private var tracker: PitchTracker?
    private var splitter = NoteSplitter()
    private var pending: [Float] = []
    /// When the first sample in `pending` was heard.
    private var pendingStart: TimeInterval = 0
    private let report: (NoteSplitter.Event) -> Void
    /// The room's own level, followed down at once and up only slowly, so a
    /// voice stands out from it but a long held note doesn't become it.
    private var floor: Float = 0.002
    private var notches: ClickNotches?
    /// Set from the main thread while the metronome plays, so its click
    /// isn't heard as notes.
    var removesClick = false

    init(report: @escaping (NoteSplitter.Event) -> Void) {
        self.report = report
        pending.reserveCapacity(8192)
    }

    func take(_ buffer: AVAudioPCMBuffer, at when: AVAudioTime) {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let rate = buffer.format.sampleRate
        if tracker?.sampleRate != rate {
            tracker = PitchTracker(sampleRate: rate, gate: 0.005, strict: true)
            notches = ClickNotches(sampleRate: rate)
            pending.removeAll(keepingCapacity: true)
        }
        guard let tracker else { return }
        let count = Int(buffer.frameLength)
        if pending.isEmpty {
            pendingStart = when.isHostTimeValid
                ? AVAudioTime.seconds(forHostTime: when.hostTime)
                : CACurrentMediaTime() - Double(count) / rate
        }
        let appendedAt = pending.count
        pending.append(contentsOf: UnsafeBufferPointer(start: data, count: count))
        if removesClick, notches != nil {
            pending.withUnsafeMutableBufferPointer { samples in
                notches!.process(samples.baseAddress! + appendedAt, count: count)
            }
        }

        // A frame every 10 ms, each overlapping the last.
        let hop = max(1, Int(rate * 0.01))
        var events: [NoteSplitter.Event] = []
        while pending.count >= tracker.frameSize {
            let time = pendingStart + Double(tracker.frameSize / 2) / rate
            pending.withUnsafeBufferPointer { samples in
                let frame = UnsafeBufferPointer(rebasing: samples[0..<tracker.frameSize])
                let level = PitchTracker.level(of: frame)
                floor = level < floor ? level : floor + (level - floor) * Float(Double(hop) / rate / 10)
                // Well clear of the room - 6 dB - or it isn't singing.
                let heard = level > floor * 2 ? tracker.pitch(of: frame) : nil
                events += splitter.take(heard.map { PitchTracker.midi(for: $0.frequency) },
                                        level: level, at: time)
            }
            pending.removeFirst(hop)
            pendingStart += Double(hop) / rate
        }
        guard !events.isEmpty else { return }
        let report = report
        DispatchQueue.main.async { events.forEach(report) }
    }
}

/// Takes the metronome back out of what the microphone hears. Over the
/// speaker the click goes straight into the microphone - into the take, and
/// into the notes, where it was read as high A's and B's. The click is a pure
/// tone at two known pitches, so a very narrow notch at each (and at the
/// overtones a small speaker adds) removes it and leaves the voice: each is
/// 100 Hz wide, a sliver of a voice's harmonics. Measured on a sung take over
/// the speaker, the click came out 20 dB down, under the voice.
struct ClickNotches {
    /// The metronome's two tones, and their first overtones.
    static let frequencies: [Double] = [Metronome.beatPitch, Metronome.accentPitch,
                                        Metronome.beatPitch * 2, Metronome.accentPitch * 2]
    private static let width = 100.0

    private var sections: [Section]

    init(sampleRate: Double) {
        sections = Self.frequencies
            .filter { $0 < sampleRate * 0.45 }
            .map { Section(notchAt: $0, width: Self.width, sampleRate: sampleRate) }
    }

    mutating func process(_ data: UnsafeMutablePointer<Float>, count: Int) {
        for index in sections.indices { sections[index].process(data, count: count) }
    }

    /// One notch, as a biquad (Robert Bristow-Johnson's), transposed direct
    /// form II.
    private struct Section {
        let b0, b1, b2, a1, a2: Float
        var z1: Float = 0, z2: Float = 0

        init(notchAt frequency: Double, width: Double, sampleRate: Double) {
            let w0 = 2 * Double.pi * frequency / sampleRate
            let alpha = sin(w0) / (2 * (frequency / width))
            let a0 = 1 + alpha
            b0 = Float(1 / a0)
            b1 = Float(-2 * cos(w0) / a0)
            b2 = Float(1 / a0)
            a1 = Float(-2 * cos(w0) / a0)
            a2 = Float((1 - alpha) / a0)
        }

        mutating func process(_ data: UnsafeMutablePointer<Float>, count: Int) {
            for index in 0..<count {
                let x = data[index]
                let y = b0 * x + z1
                z1 = b1 * x - a1 * y + z2
                z2 = b2 * x - a2 * y
                data[index] = y
            }
        }
    }
}

/// The metronome's sound, shared by the click itself and the filters that
/// take it back out of the microphone.
enum Metronome {
    static let accentPitch = 2000.0
    static let beatPitch = 1500.0
}

/// The voice on its way into a take. The microphone runs on an engine of
/// its own - so the instrument's engine never has an input, and never fails to
/// restart once the microphone is off - and this carries what it hears across:
/// written by the microphone's tap, read by the instrument engine as it
/// renders. Kept short, so the voice stays in time with the keys.
final class VoiceRing: @unchecked Sendable {
    static let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private var samples = [Float](repeating: 0, count: 24_000)
    private var readIndex = 0
    private var count = 0
    private let lock = OSAllocatedUnfairLock()
    /// More than this waiting means the reader has fallen behind; the oldest
    /// is dropped rather than letting the voice drift late.
    private let mostLatency = 4_800

    func write(_ source: UnsafePointer<Float>, count frames: Int) {
        lock.withLock {
            let capacity = samples.count
            for index in 0..<frames {
                samples[(readIndex + count) % capacity] = source[index]
                if count < capacity { count += 1 } else { readIndex = (readIndex + 1) % capacity }
            }
            if count > mostLatency {
                readIndex = (readIndex + count - mostLatency / 2) % capacity
                count = mostLatency / 2
            }
        }
    }

    /// Fills `destination`, with silence for whatever hasn't arrived.
    func read(into destination: UnsafeMutablePointer<Float>, count frames: Int) {
        lock.withLock {
            let capacity = samples.count
            let available = min(frames, count)
            for index in 0..<available { destination[index] = samples[(readIndex + index) % capacity] }
            for index in available..<frames { destination[index] = 0 }
            readIndex = (readIndex + available) % capacity
            count -= available
        }
    }

    func clear() {
        lock.withLock { readIndex = 0; count = 0 }
    }
}

/// Hands the microphone's audio to the ring as it arrives, a few
/// milliseconds at a time, on the microphone engine's audio thread - so
/// nothing here allocates or waits for long. A microphone running at another
/// rate is brought to the ring's by straight-line interpolation, plenty for a
/// voice going into a take.
final class VoiceFeed: @unchecked Sendable {
    private let ring: VoiceRing
    private var scratch = [Float](repeating: 0, count: 8_192)
    private var position = 0.0
    private var previous: Float = 0
    private var notches = ClickNotches(sampleRate: VoiceRing.format.sampleRate)
    /// Set from the main thread while the metronome plays. A stale read
    /// costs one buffer of a few milliseconds, either way.
    var removesClick = false

    init(ring: VoiceRing) { self.ring = ring }

    func take(_ data: UnsafePointer<Float>, count: Int, rate: Double) {
        guard count > 0 else { return }
        let target = VoiceRing.format.sampleRate
        if rate == target {
            guard removesClick, count <= scratch.count else {
                ring.write(data, count: count)
                return
            }
            scratch.withUnsafeMutableBufferPointer { out in
                guard let base = out.baseAddress else { return }
                base.update(from: data, count: count)
                notches.process(base, count: count)
                ring.write(base, count: count)
            }
            return
        }
        // The stream as the last sample of the previous piece, then this one:
        // index 0 is `previous`, index n is data[n - 1].
        let step = rate / target
        var written = 0
        scratch.withUnsafeMutableBufferPointer { out in
            while position < Double(count), written < out.count {
                let index = Int(position)
                let fraction = Float(position - Double(index))
                let before = index == 0 ? previous : data[index - 1]
                let after = data[index]
                out[written] = before + (after - before) * fraction
                written += 1
                position += step
            }
            if let base = out.baseAddress {
                if removesClick { notches.process(base, count: written) }
                ring.write(base, count: written)
            }
        }
        position -= Double(count)
        previous = data[count - 1]
    }
}

enum VoiceTranscriptionError: LocalizedError {
    case unreadable
    case noMelody

    var errorDescription: String? {
        switch self {
        case .unreadable: "This recording couldn't be opened."
        case .noMelody: "No melody could be heard in this recording. Try one with a single voice singing, humming or whistling."
        }
    }
}

/// A whole recording turned into notes, for importing a voice memo.
enum VoiceTranscriber {
    /// The notes sung in `url`, with the recording's length, as a score the
    /// library can keep beside the recording itself.
    static func score(from url: URL) throws -> MelodyScore {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw VoiceTranscriptionError.unreadable }
        let format = file.processingFormat
        let rate = format.sampleRate
        let channels = Int(format.channelCount)
        let tracker = PitchTracker(sampleRate: rate)
        let hop = Int(rate * 0.01)
        var splitter = NoteSplitter()

        // Read in chunks, mixing down to one channel, and step through the
        // audio a hop at a time, each frame overlapping the last.
        var mono: [Float] = []
        mono.reserveCapacity(Int(file.length))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 65_536) else {
            throw VoiceTranscriptionError.unreadable
        }
        while file.framePosition < file.length {
            do { try file.read(into: buffer) } catch { throw VoiceTranscriptionError.unreadable }
            guard buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            let count = Int(buffer.frameLength)
            for frame in 0..<count {
                var sum: Float = 0
                for channel in 0..<channels { sum += data[channel][frame] }
                mono.append(sum / Float(channels))
            }
        }
        let duration = Double(mono.count) / rate

        // Quiet recordings still have a melody in them: bring the loudest
        // part up to a working level before listening.
        var peak: Float = 0
        vDSP_maxmgv(mono, 1, &peak, vDSP_Length(mono.count))
        if peak > 0, peak < 0.5 {
            var gain = 0.5 / peak
            vDSP_vsmul(mono, 1, &gain, &mono, 1, vDSP_Length(mono.count))
        }

        var spans: [NoteSpan] = []
        var opened: (start: TimeInterval, level: Float)?
        func apply(_ events: [NoteSplitter.Event]) {
            for event in events {
                switch event {
                case .began(_, let start):
                    opened = (start, 0)
                case .ended(let note, let end):
                    guard let held = opened else { continue }
                    opened = nil
                    // Blips under a tenth of a second are scoops and slides,
                    // not notes anyone meant.
                    guard end - held.start >= 0.1 else { continue }
                    let velocity = UInt8(max(50, min(115, 60 + Int(held.level * 200))))
                    spans.append(NoteSpan(note: note, start: held.start, end: end, velocity: velocity))
                }
            }
        }

        var position = 0
        mono.withUnsafeBufferPointer { samples in
            while position + tracker.frameSize <= samples.count {
                let frame = UnsafeBufferPointer(rebasing: samples[position..<(position + tracker.frameSize)])
                let time = Double(position + tracker.frameSize / 2) / rate
                let heard = tracker.pitch(of: frame)
                let level = PitchTracker.level(of: frame)
                apply(splitter.take(heard.map { PitchTracker.midi(for: $0.frequency) }, level: level, at: time))
                // How loud the note gets, for its velocity.
                if heard != nil, let held = opened {
                    opened = (held.start, max(held.level, level))
                }
                position += hop
            }
        }
        apply(splitter.finish(at: duration))

        guard !spans.isEmpty else { throw VoiceTranscriptionError.noMelody }
        var score = MelodyScore(spans: spans.sorted { $0.start < $1.start }, duration: duration)
        score.isSung = true
        return score
    }
}

/// Bringing a voice memo into the library: the recording is kept as it is,
/// with the notes heard in it as its score, so it plays back in the singer's
/// own voice while the keys and the sheet music follow along.
enum VoiceMemoImport {
    /// Listens to the recording at `url` and keeps a copy of it in the
    /// library. Takes a moment for a long memo, so call it off the main thread.
    static func importMemo(at url: URL) throws -> Recording {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
            discardInboxCopy(url)
        }
        let score = try VoiceTranscriber.score(from: url)
        return try RecordingStore.shared.save(copying: url,
                                              named: url.deletingPathExtension().lastPathComponent,
                                              score: score)
    }

    /// Files sent from another app's share sheet arrive as copies in
    /// Documents/Inbox, which the Files app would otherwise show as clutter
    /// beside the melodies. Once read, the copy has done its job.
    static func discardInboxCopy(_ url: URL) {
        let inbox = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        guard url.standardizedFileURL.path.hasPrefix(inbox.standardizedFileURL.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func isMIDI(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .midi) ?? false
    }
}
