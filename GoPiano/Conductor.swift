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
    private(set) var startupError: String?

    var isRecording: Bool { transport == .recording }
    var isPlaying: Bool { transport == .playing }

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
            reverb.dryWetMix = 0.25

            // Set before the samples are handed over: swapping in new sampler
            // data copies the envelope settings across from the current one,
            // and the parameters reject writes made straight after the swap.
            sampler.masterVolume = 0.9
            sampler.releaseDuration = 0.45

            loadInstrument()
            recorder = try NodeRecorder(node: reverb)
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
        sampler.update(data: data)

        isInstrumentLoaded = true
    }

    // MARK: - Playing

    func noteOn(_ note: UInt8) {
        guard isInstrumentLoaded, !activeNotes.contains(note) else { return }
        activeNotes.insert(note)
        sampler.play(noteNumber: note, velocity: 100)
    }

    func noteOff(_ note: UInt8) {
        guard activeNotes.contains(note) else { return }
        activeNotes.remove(note)
        sampler.stop(noteNumber: note)
    }

    func allNotesOff() {
        for note in activeNotes { sampler.stop(noteNumber: note) }
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
        player.stop()
        do {
            try recorder.reset()
            try recorder.record()
            transport = .recording
        } catch {
            Log("Could not start recording: \(error)")
        }
    }

    private func stopRecording() {
        guard let recorder else { return }
        recorder.stop()
        transport = .idle
        if let file = recorder.audioFile, file.length > 0 {
            try? player.load(file: file)
            hasRecording = true
        }
    }

    func togglePlayback() {
        switch transport {
        case .playing:
            player.stop()
            transport = .idle
        case .recording:
            break
        case .idle:
            guard hasRecording else { return }
            player.play()
            transport = .playing
        }
    }

    private func playbackFinished() {
        if transport == .playing { transport = .idle }
    }

    func reset() {
        player.stop()
        allNotesOff()
        try? recorder?.reset()
        hasRecording = false
        transport = .idle
    }

    /// Saves the current take into Documents so it outlives the session.
    @discardableResult
    func saveRecording(named name: String) -> URL? {
        guard let source = recorder?.audioFile?.url else { return nil }
        let destination = RecordingStore.shared.newFileURL(named: name,
                                                           pathExtension: source.pathExtension)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            Log("Could not save recording: \(error)")
            return nil
        }
    }
}
