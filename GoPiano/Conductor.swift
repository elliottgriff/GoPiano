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
    private var replayTimer: Timer?

    private var now: TimeInterval { CACurrentMediaTime() }

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
            sampler.masterVolume = 0.9
            sampler.releaseDuration = 0.45

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
            if let loadedSamples { sampler.update(data: loadedSamples) }
        } catch {
            Log("Could not resume audio: \(error)")
        }
    }

    private func configureSession() throws {
        #if os(iOS)
        // Playback only: the recorder taps a node inside the graph rather than
        // the microphone, so the app never needs record permission.
        try Settings.session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
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
        if isRecording { scoreRecorder.noteOn(note, at: at) }
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
        // No point stopping a player that was never scheduled.
        if player.isPlaying { player.stop() }
        do {
            try recorder.reset()
            try recorder.record()
            scoreRecorder.reset()
            recordingStart = now
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
        currentScore = scoreRecorder.finish(at: elapsed)
        if let file = recorder.audioFile, file.length > 0 {
            try? player.load(file: file)
            hasRecording = true
        }
    }

    func togglePlayback() {
        switch transport {
        case .playing:
            player.stop()
            stopReplay()
            transport = .idle
        case .recording:
            break
        case .idle:
            guard hasRecording else { return }
            player.play()
            transport = .playing
            startReplay()
        }
    }

    /// Stops playback without toggling into it, for views that are going away.
    func stopPlayback() {
        guard transport == .playing else { stopReplay(); return }
        player.stop()
        stopReplay()
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
        try player.load(url: recording.url)
        currentScore = RecordingStore.shared.score(for: recording) ?? MelodyScore()
        hasRecording = true
        transport = .idle
    }

    func reset() {
        player.stop()
        stopReplay()
        allNotesOff()
        setSustain(false)
        discardTakeFile()
        try? recorder?.reset()
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

    /// Encodes the current take into the recordings library, along with the
    /// notes that were played so it can be replayed and exported as video.
    func saveRecording(named name: String) throws -> Recording {
        guard let source = recorder?.audioFile?.url, hasRecording else {
            throw RecordingStoreError.noTake
        }
        return try RecordingStore.shared.save(copying: source,
                                              named: name,
                                              score: currentScore)
    }
}
