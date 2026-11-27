//
//  Conductor.swift
//  GoPiano
//
//  Owns the audio graph: a multi-sampled piano into reverb, tapped by a
//  recorder, with a player for listening back.
//

import AVFoundation
import AudioKit
import CDunneAudioKit
import DunneAudioKit
import Observation

@Observable
final class Conductor {

    enum Transport: Equatable {
        case idle
        case recording
        case playing
    }

    // MARK: - Graph

    private let engine = AudioEngine()
    private let sampler = Sampler()
    private let instrumentBus: Mixer
    private let reverb: Reverb
    private let player = AudioPlayer()
    private let mainBus: Mixer
    private var recorder: NodeRecorder?

    // MARK: - Observable state

    private(set) var transport: Transport = .idle
    private(set) var isInstrumentLoaded = false
    private(set) var hasRecording = false
    /// A take was recorded and has not been saved. Only this can be lost, so
    /// only this is worth a confirmation - and only this is what Save saves.
    /// It survives opening a melody from the library or importing a file: those
    /// change what Play plays, but the take is still on disk until it is saved,
    /// reset, or recorded over. (`hasRecording` is also true for a library
    /// melody, which is already safe.)
    private(set) var hasUnsavedTake = false
    /// An imported melody is loaded: notes with no audio behind them, which
    /// the sampler has to perform. Kept apart from `hasRecording`, which means
    /// there is a take that can be saved and shared as sound.
    private(set) var hasSequence = false

    /// Whether there is anything for Play to play, whichever kind it is.
    var canPlay: Bool { hasRecording || hasSequence }
    private(set) var activeNotes: Set<UInt8> = []
    /// Keys lit by playback rather than by a finger. Replay only highlights -
    /// the sound comes from the recording, so the sampler is left alone.
    private(set) var replayNotes: Set<UInt8> = []
    private(set) var startupError: String?

    /// What the keyboard should show as held down, whoever is holding it.
    var highlightedNotes: Set<UInt8> { activeNotes.union(replayNotes) }

    /// Sustain holds notes on after the key is released, like the right pedal.
    private(set) var isSustaining = false

    /// How wet the reverb is. Stored here because the effect can only be
    /// written once the engine has built its audio units.
    private(set) var reverbMix: Float = 0.25

    var isRecording: Bool { transport == .recording }
    var isPlaying: Bool { transport == .playing }

    // MARK: - What was played

    /// Kept so the instrument can be handed back after the engine restarts:
    /// `update(data:)` re-inits the core sampler at whatever rate the DSP knows,
    /// which is how it picks up a new hardware sample rate.
    private var loadedSamples: SamplerData?

    private var scoreRecorder = ScoreRecorder()
    private var recordingStart: TimeInterval = 0
    /// The score matching whatever the player currently holds.
    private(set) var currentScore = MelodyScore()
    /// The notes of the last take, kept apart from `currentScore`: opening a
    /// library melody replaces that, and saving the take afterwards paired its
    /// audio with the other melody's notes.
    private var takeScore = MelodyScore()
    private var replayTimer: Timer?

    // Sequencer state - see "Performing a melody" below.
    private var sequence: [SequencedEvent] = []
    private var sequenceIndex = 0
    private var sequenceStart: TimeInterval = 0
    private var sequenceTimer: Timer?
    /// Notes the sequencer has sounded and not yet released, counted, because a
    /// file can hold the same note twice at once; it only goes quiet when the
    /// last of them ends.
    private var sequencedNotes: [UInt8: Int] = [:]

    private var now: TimeInterval { CACurrentMediaTime() }

    /// What the time readout shows: the take growing while it records, how far
    /// in while something plays, and otherwise how long the loaded melody runs.
    /// Always read off a real clock - adding up timer ticks drifts, because the
    /// ticks arrive late under load.
    var readoutTime: TimeInterval {
        switch transport {
        case .recording:
            return now - recordingStart
        case .playing:
            let position = hasSequence ? now - sequenceStart : player.currentTime
            return min(max(0, position), finishedTakeDuration)
        case .idle:
            return finishedTakeDuration
        }
    }

    private var finishedTakeDuration: TimeInterval = 0

    init() {
        instrumentBus = Mixer(sampler)
        reverb = Reverb(instrumentBus)
        mainBus = Mixer(reverb, player)
        engine.output = mainBus

        player.isLooping = false
        player.completionHandler = { [weak self] in
            Task { @MainActor in self?.playbackFinished() }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isInstrumentLoaded, startupError == nil else { return }
        do {
            removeOrphanedTakes()
            try configureSession()
            // The engine must be running before the instrument is handed over:
            // the sampler's DSP only learns the real hardware sample rate when
            // it is started, and `update(data:)` re-inits the core sampler with
            // whatever rate it knows at that moment. Load first and every note
            // plays sharp by the ratio between 44100 and the actual rate.
            try engine.start()
            // Effect parameters are only writable once the engine has
            // instantiated the underlying audio units.
            reverb.loadFactoryPreset(.mediumRoom)
            reverb.dryWetMix = AUValue(reverbMix)

            // Set before the samples are handed over: swapping in new sampler
            // data copies the envelope settings across from the current one,
            // and the parameters reject writes made straight after the swap.
            applySamplerParameters()

            loadInstrument()
            recorder = try NodeRecorder(node: reverb)
            observeAudioSession()
        } catch {
            startupError = error.localizedDescription
            Log("Audio start failed: \(error)")
        }
    }

    func stop() {
        allNotesOff()
        player.stop()
        engine.stop()
        isInstrumentLoaded = false
    }

    // MARK: - Surviving interruptions

    /// A call, an alarm, or headphones being pulled stops the engine. Nothing
    /// restarted it, so the app went silent until it was relaunched.
    private func observeAudioSession() {
        let centre = NotificationCenter.default
        #if os(iOS)
        centre.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: nil, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                MainActor.assumeIsolated { self.handleInterruptionBegan() }
            case .ended:
                let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
                if options.contains(.shouldResume) {
                    MainActor.assumeIsolated { self.resumeAudio() }
                }
            @unknown default:
                break
            }
        }

        // A new route can mean a new sample rate, which the sampler has to be
        // told about or every note comes out at the wrong pitch.
        centre.addObserver(forName: AVAudioSession.routeChangeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.resumeAudio() }
        }

        centre.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.resumeAudio() }
        }
        #endif
    }

    private func handleInterruptionBegan() {
        allNotesOff()
        player.stop()
        stopReplay()
        stopSequence()
        transport = .idle
    }

    /// Brings the engine back and hands the instrument over again, so a changed
    /// sample rate is picked up rather than silently detuning everything.
    func resumeAudio() {
        guard isInstrumentLoaded else { return }
        guard !engine.avEngine.isRunning else { return }
        do {
            try configureSession()
            try engine.start()
            if let loadedSamples {
                // Same ordering as at startup, and for the same reason: the
                // swap copies these across from the current sampler and
                // rejects writes made straight after it.
                applySamplerParameters()
                sampler.update(data: loadedSamples)
            }
            // The sampler comes back with the pedal up, while the control went
            // on showing it down - so sustain looked on, did nothing, and had
            // to be pressed twice to come back.
            sampler.sustainPedal(pedalDown: isSustaining)
        } catch {
            Log("Could not resume audio: \(error)")
        }
    }

    /// Volume and envelope for the sampler. Always set *before* sampler data
    /// is swapped in, never after: the swap copies these across from the
    /// current sampler, and writes made straight afterwards are rejected.
    private func applySamplerParameters() {
        sampler.masterVolume = 0.9
        sampler.releaseDuration = 0.45
    }

    private func configureSession() throws {
        #if os(iOS)
        // Playback only: the recorder taps a node inside the graph rather than
        // the microphone, so the app never needs record permission.
        try Settings.session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        // Asked for before the session is activated, which is when the
        // preference is read. Left to the system the buffer can run to 20ms or
        // more: unremarkable for playing a file back, but on an instrument it
        // is the gap between the key going down and the note arriving. It is a
        // request rather than a setting - the hardware and the current route
        // decide what is actually granted - so a refusal is not fatal and the
        // session still goes active.
        try? Settings.session.setPreferredIOBufferDuration(0.005)
        try Settings.session.setActive(true)
        #endif
    }

    private func loadInstrument() {
        let entries = SampleMap.entries
        var descriptors: [SamplerData.FileWithSampleDescriptor] = []

        for (index, entry) in entries.enumerated() {
            guard let url = Bundle.main.url(forResource: entry.file,
                                            withExtension: nil,
                                            subdirectory: "Samples"),
                  let file = try? AVAudioFile(forReading: url)
            else {
                Log("Missing sample \(entry.file)")
                continue
            }

            // Every sample claims the notes nearest to it, and the outermost two
            // cover the rest of the keyboard. The key map matches a note against
            // every sample whose range contains it and takes the first hit, so
            // leaving these at 0...127 would make one sample answer for the
            // whole keyboard.
            let low = index == 0
                ? 0
                : (entries[index - 1].root + entry.root) / 2 + 1
            let high = index == entries.count - 1
                ? 127
                : (entry.root + entries[index + 1].root) / 2

            let descriptor = SampleDescriptor(noteNumber: Int32(entry.root),
                                              noteFrequency: entry.frequency,
                                              minimumNoteNumber: Int32(low),
                                              maximumNoteNumber: Int32(high),
                                              minimumVelocity: 0,
                                              maximumVelocity: 127,
                                              isLooping: false,
                                              loopStartPoint: 0,
                                              loopEndPoint: 0,
                                              startPoint: 0,
                                              endPoint: 0)
            descriptors.append((sampleDescriptor: descriptor, file: file))
        }

        guard !descriptors.isEmpty else {
            startupError = "No piano samples found in the app bundle."
            return
        }

        // buildKeyMap() works through the underlying C sampler, not the struct.
        let data = SamplerData(filesWithSampleDescriptors: descriptors)
        data.buildKeyMap()
        loadedSamples = data
        sampler.update(data: data)

        // The first MIDI event through the sampler costs the best part of a
        // second in lazy setup, which would otherwise land on the first key the
        // player touches - delaying the sound and, mid-take, the note written
        // down with it. A note-off takes the same path and makes no sound, so
        // that cost is spent here instead.
        //
        // Deliberately not `silence()`: that calls stopAllVoices(), which sets
        // a flag only restartVoices() clears, leaving the sampler mute for good.
        sampler.stop(noteNumber: 60)

        isInstrumentLoaded = true
    }

    // MARK: - Playing

    func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        guard isInstrumentLoaded, !activeNotes.contains(note) else { return }
        let at = now - recordingStart
        activeNotes.insert(note)
        sampler.play(noteNumber: note, velocity: velocity)
        if isRecording { scoreRecorder.noteOn(note, velocity: velocity, at: at) }
    }

    func noteOff(_ note: UInt8) {
        guard activeNotes.contains(note) else { return }
        let at = now - recordingStart
        activeNotes.remove(note)
        sampler.stop(noteNumber: note)
        if isRecording { scoreRecorder.noteOff(note, at: at) }
    }

    func setReverbMix(_ value: Float) {
        reverbMix = min(max(value, 0), 1)
        guard isInstrumentLoaded else { return }
        reverb.dryWetMix = AUValue(reverbMix)
    }

    func setSustain(_ on: Bool) {
        guard on != isSustaining else { return }
        isSustaining = on
        sampler.sustainPedal(pedalDown: on)
    }

    /// Plays a note and releases it shortly after. VoiceOver activates a key
    /// rather than holding it, so there is no touch-up to wait for.
    func tapNote(_ note: UInt8) {
        noteOn(note)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            noteOff(note)
        }
    }

    func allNotesOff() {
        let held = activeNotes
        for note in held {
            sampler.stop(noteNumber: note)
            if isRecording { scoreRecorder.noteOff(note, at: now - recordingStart) }
        }
        activeNotes.removeAll()
    }

    // MARK: - Transport

    func toggleRecording() {
        switch transport {
        case .recording: stopRecording()
        default: startRecording()
        }
    }

    private func startRecording() {
        guard let recorder else { return }
        // The previous take is an uncompressed CAF of roughly 20 MB a minute.
        // Nothing else deletes it, so it goes now that it is being replaced.
        discardTakeFile()
        stopReplay()
        stopSequence()
        hasSequence = false
        // No point stopping a player that was never scheduled.
        if player.isPlaying { player.stop() }
        do {
            try recorder.reset()
            try recorder.record()
            scoreRecorder.reset()
            recordingStart = now
            finishedTakeDuration = 0
            hasUnsavedTake = false
            currentScore = MelodyScore()
            transport = .recording
        } catch {
            Log("Could not start recording: \(error)")
        }
    }

    private func stopRecording() {
        guard let recorder else { return }
        let elapsed = now - recordingStart
        recorder.stop()
        transport = .idle
        finishedTakeDuration = elapsed
        currentScore = scoreRecorder.finish(at: elapsed)
        takeScore = currentScore
        if let file = recorder.audioFile, file.length > 0 {
            try? player.load(file: file)
            hasRecording = true
            hasUnsavedTake = true
        }
    }

    func togglePlayback() {
        switch transport {
        case .playing:
            player.stop()
            stopReplay()
            stopSequence()
            transport = .idle
        case .recording:
            break
        case .idle:
            if hasSequence {
                startSequence()
            } else if hasRecording {
                player.play()
                transport = .playing
                startReplay()
            }
        }
    }

    /// Stops playback without toggling into it, for views that are going away.
    func stopPlayback() {
        guard transport == .playing else { stopReplay(); return }
        player.stop()
        stopReplay()
        stopSequence()
        transport = .idle
    }

    private func playbackFinished() {
        if transport == .playing { transport = .idle }
        stopReplay()
    }

    /// Loads a saved melody so it plays - and lights up the keys - on the
    /// keyboard itself.
    func load(_ recording: Recording) throws {
        player.stop()
        stopReplay()
        stopSequence()
        try player.load(url: recording.url)
        currentScore = RecordingStore.shared.score(for: recording) ?? MelodyScore()
        hasRecording = true
        hasSequence = false
        finishedTakeDuration = recording.duration
        transport = .idle
    }

    /// Loads a melody that is notes alone - an imported MIDI file - for the
    /// keyboard to perform. There is no audio behind it, so it plays through
    /// the sampler, and there is nothing to save or share as sound.
    func load(_ score: MelodyScore) {
        player.stop()
        stopReplay()
        stopSequence()
        currentScore = score
        sequence = Self.events(for: score)
        hasRecording = false
        hasSequence = !score.isEmpty
        finishedTakeDuration = score.duration
        transport = .idle
    }

    func reset() {
        player.stop()
        stopReplay()
        stopSequence()
        hasSequence = false
        hasUnsavedTake = false
        takeScore = MelodyScore()
        sequence = []
        allNotesOff()
        setSustain(false)
        discardTakeFile()
        try? recorder?.reset()
        finishedTakeDuration = 0
        currentScore = MelodyScore()
        hasRecording = false
        transport = .idle
    }

    /// Removes the working file behind the current take. The saved melody is a
    /// separate, compressed copy, so this only throws away scratch.
    private func discardTakeFile() {
        guard let url = recorder?.audioFile?.url else { return }
        player.stop()
        try? FileManager.default.removeItem(at: url)
    }

    /// Clears takes left behind by previous runs, which used to accumulate
    /// indefinitely - a testing session alone left the best part of a gigabyte.
    private func removeOrphanedTakes() {
        let tmp = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension.lowercased() == "caf" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Replay highlighting

    private func startReplay() {
        guard !currentScore.isEmpty else { return }
        replayTimer?.invalidate()
        // Driven off the player's own clock rather than a wall clock, so it
        // stays in step through pauses and restarts.
        replayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickReplay() }
        }
    }

    private func tickReplay() {
        guard transport == .playing else { stopReplay(); return }
        let notes = currentScore.notes(at: player.currentTime)
        if notes != replayNotes { replayNotes = notes }
    }

    private func stopReplay() {
        replayTimer?.invalidate()
        replayTimer = nil
        if !replayNotes.isEmpty { replayNotes = [] }
    }

    // MARK: - Performing a melody

    /// Replay above only lights keys over a recording that makes its own sound.
    /// An imported melody has no recording, so this plays it: it walks the
    /// notes against its own clock and drives the sampler, the way fingers do.
    private struct SequencedEvent {
        let time: TimeInterval
        let isOff: Bool
        let note: UInt8
        let velocity: UInt8
    }

    /// How late a note may be and still be played. Past this it is skipped -
    /// after the app has been in the background, say, or the main thread was
    /// held up - rather than everything that was missed sounding at once.
    private static let latestPlayableNote: TimeInterval = 0.1

    private static func events(for score: MelodyScore) -> [SequencedEvent] {
        var events: [SequencedEvent] = []
        events.reserveCapacity(score.spans.count * 2)
        for span in score.spans {
            events.append(SequencedEvent(time: span.start, isOff: false,
                                         note: span.note, velocity: span.velocity))
            events.append(SequencedEvent(time: span.end, isOff: true,
                                         note: span.note, velocity: 0))
        }
        // Releases go before presses at the same instant, so a note struck
        // again the moment it ends is not switched straight back off.
        return events.sorted { ($0.time, $0.isOff ? 0 : 1) < ($1.time, $1.isOff ? 0 : 1) }
    }

    private func startSequence() {
        guard hasSequence, !sequence.isEmpty else { return }
        stopSequence()
        sequenceStart = now
        transport = .playing
        // Common mode, so it keeps time while the user is touching the screen.
        // Called directly rather than through a Task: a hop to the main actor
        // costs a little more timing on every tick, and the run loop is
        // already on the main thread.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tickSequence()
        }
        RunLoop.main.add(timer, forMode: .common)
        sequenceTimer = timer
        tickSequence()
    }

    private func tickSequence() {
        guard transport == .playing, hasSequence else { stopSequence(); return }
        let elapsed = now - sequenceStart
        var keysChanged = false

        while sequenceIndex < sequence.count, sequence[sequenceIndex].time <= elapsed {
            let event = sequence[sequenceIndex]
            sequenceIndex += 1

            if event.isOff {
                guard let held = sequencedNotes[event.note] else { continue }
                if held > 1 {
                    sequencedNotes[event.note] = held - 1
                } else {
                    sequencedNotes[event.note] = nil
                    sampler.stop(noteNumber: event.note)
                    keysChanged = true
                }
            } else {
                guard elapsed - event.time <= Self.latestPlayableNote else { continue }
                let held = sequencedNotes[event.note, default: 0]
                sampler.play(noteNumber: event.note, velocity: event.velocity)
                sequencedNotes[event.note] = held + 1
                if held == 0 { keysChanged = true }
            }
        }

        if keysChanged { replayNotes = Set(sequencedNotes.keys) }

        if sequenceIndex >= sequence.count {
            stopSequence()
            transport = .idle
        }
    }

    /// Stops the performance and lets go of anything it was holding. Safe to
    /// call when nothing is playing.
    private func stopSequence() {
        sequenceTimer?.invalidate()
        sequenceTimer = nil
        for note in sequencedNotes.keys { sampler.stop(noteNumber: note) }
        sequencedNotes.removeAll()
        sequenceIndex = 0
        if !replayNotes.isEmpty { replayNotes = [] }
    }

    /// Encodes the current take into the recordings library, along with the
    /// notes that were played so it can be replayed and exported as video.
    func saveRecording(named name: String) throws -> Recording {
        guard let source = recorder?.audioFile?.url, hasUnsavedTake else {
            throw RecordingStoreError.noTake
        }
        let saved = try RecordingStore.shared.save(copying: source,
                                                   named: name,
                                                   score: takeScore)
        hasUnsavedTake = false
        return saved
    }
}
