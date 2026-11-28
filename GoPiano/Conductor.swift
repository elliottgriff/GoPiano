//
//  Conductor.swift
//  GoPiano
//
//  Owns the audio graph: a multi-sampled piano into reverb - a room always,
//  a hall while the pedal is down - tapped by a recorder, with a player for
//  listening back.
//

import AVFoundation
import AudioKit
import CDunneAudioKit
import DunneAudioKit
import Observation

/// The sounds GoPiano can play. Each is a set of samples in the app bundle,
/// mapped across the keyboard the same way.
enum Instrument: String, CaseIterable, Identifiable {
    case piano
    case electricPiano
    case guitar

    var id: String { rawValue }

    var name: String {
        switch self {
        case .piano: "Piano"
        case .electricPiano: "Electric Piano"
        case .guitar: "Guitar"
        }
    }

    var symbol: String {
        switch self {
        case .piano: "pianokeys"
        case .electricPiano: "pianokeys.inverse"
        case .guitar: "guitars"
        }
    }

    var samples: [SampleMap.Entry] {
        switch self {
        case .piano: SampleMap.piano
        case .electricPiano: SampleMap.electricPiano
        case .guitar: SampleMap.guitar
        }
    }

    /// How quickly a note stops once its key is let go: the piano's dampers,
    /// an electric piano's softer ones, a finger lifting off a string.
    var release: Float {
        switch self {
        case .piano: 0.45
        case .electricPiano: 0.5
        case .guitar: 0.3
        }
    }
}

@Observable
final class Conductor {

    enum Transport: Equatable {
        case idle
        /// The metronome's bar of clicks before a take starts on the downbeat.
        case countingIn
        case recording
        case playing
    }

    // MARK: - Graph

    private let engine = AudioEngine()
    private let sampler = Sampler()
    private let instrumentBus: Mixer
    private let reverb: Reverb
    /// The pedal's ring. With the dampers lifted a piano's strings sound on
    /// and set the rest of the instrument humming; a hall reverb, faded in
    /// only while the pedal is down, stands in for that. Wholly wet, so the
    /// room above still sets how dry the piano is.
    private let hall: Reverb
    private let hallSend: Mixer
    /// The piano and both reverbs.
    private let instrumentOut: Mixer
    /// The microphone, connected only while listening. It goes into takes
    /// but never to the speaker, where it would feed straight back in.
    private let voice = VoiceNode()
    /// What's recorded: the instrument, and the voice singing along.
    private let takeMix: Mixer
    /// Carries the take mix to the output at no volume, so the engine pulls
    /// it - and the recorder hears it - without the voice being played out.
    private let takeSend: Mixer
    private var hallFade: Timer?
    private let player = AudioPlayer()
    /// The metronome. It joins the graph after the reverb and away from the
    /// recorder's tap, so the click is heard but never recorded.
    private let click = ClickNode()
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
    var highlightedNotes: Set<UInt8> {
        var notes = activeNotes.union(replayNotes)
        if let sungNote { notes.insert(sungNote) }
        return notes
    }

    /// Sustain holds notes on after the key is released, like the right pedal.
    private(set) var isSustaining = false

    /// How wet the reverb is. Stored here because the effect can only be
    /// written once the engine has built its audio units.
    private(set) var reverbMix: Float = 0.25

    /// A take is under way, counting in included: what the controls care about.
    var isRecording: Bool { transport == .recording || transport == .countingIn }
    var isCountingIn: Bool { transport == .countingIn }
    /// Beats left before a counted-in take starts, for the clock to show.
    private(set) var countInBeatsLeft = 0
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

    /// The song as sheet music, shown above the keys: every note written down
    /// in the order it was played, notes struck together stacked into chords.
    /// It is the music of whatever is loaded - the take just recorded, a saved
    /// melody, an import - or, with nothing loaded, of whatever is played.
    private(set) var page: SheetPage = .written([])
    /// Whether playing writes onto the page. True with nothing loaded and
    /// while recording; false while the page shows a finished take or a
    /// melody, so playing along with it doesn't scribble over it.
    private(set) var pageIsLive = true

    // Sequencer state - see "Performing a melody" below.
    private var sequence: [SequencedEvent] = []
    private var sequenceIndex = 0
    private var sequenceStart: TimeInterval = 0
    private var sequenceTimer: Timer?
    /// Whether the sequencer, rather than the recording, is what's playing.
    @ObservationIgnored private var isPerformingNotes = false
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
        case .countingIn:
            return 0
        case .playing:
            let position = isPerformingNotes ? now - sequenceStart : player.currentTime
            return min(max(0, position), finishedTakeDuration)
        case .idle:
            return finishedTakeDuration
        }
    }

    private var finishedTakeDuration: TimeInterval = 0

    init() {
        instrumentBus = Mixer(sampler)
        reverb = Reverb(instrumentBus)
        hall = Reverb(instrumentBus)
        hallSend = Mixer(hall)
        hallSend.volume = 0
        instrumentOut = Mixer(reverb, hallSend)
        takeMix = Mixer(instrumentOut, voice)
        takeSend = Mixer(takeMix)
        takeSend.volume = 0
        mainBus = Mixer(instrumentOut, player, click, takeSend)
        engine.output = mainBus

        player.isLooping = false
        player.completionHandler = { [weak self] in
            Task { @MainActor in self?.playbackFinished() }
        }
    }

    // MARK: - Lifecycle

    /// Audio setup runs here rather than on the main thread. Activating the
    /// session, starting the engine, reading every sample and the sampler's
    /// slow first event together held the main thread for over a second at
    /// launch - long enough on a device for touches to time out and the app to
    /// look frozen. Only the results are handed back to the main thread.
    private let audioQueue = DispatchQueue(label: "com.ecgriffin.GoPiano.audio", qos: .userInitiated)
    @ObservationIgnored private var isStarting = false

    static let instrumentKey = "instrument"

    /// What the keys play. Kept across launches.
    private(set) var instrument = Instrument(rawValue: UserDefaults.standard.string(forKey: Conductor.instrumentKey) ?? "")
        ?? .piano

    /// Swaps the samples the keys play. Done on the audio queue, like loading
    /// at launch, so the keys stay responsive while a new set is read.
    func setInstrument(_ choice: Instrument) {
        guard choice != instrument else { return }
        instrument = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Self.instrumentKey)
        guard isInstrumentLoaded else { return }
        allNotesOff()
        let pedal = isSustaining
        audioQueue.async { [self] in
            do {
                applySamplerParameters(for: choice)
                let samples = try loadInstrument(choice)
                sampler.sustainPedal(pedalDown: pedal)
                DispatchQueue.main.async { [self] in
                    // A quicker second choice may have landed first.
                    if instrument == choice { loadedSamples = samples }
                }
            } catch {
                Log("Could not load \(choice.name): \(error)")
            }
        }
    }

    func start() {
        guard !isInstrumentLoaded, !isStarting, startupError == nil else { return }
        isStarting = true
        let mix = reverbMix
        let choice = instrument
        audioQueue.async { [self] in
            let outcome: Result<(samples: SamplerData, recorder: NodeRecorder,
                                 clicks: (accent: AVAudioPCMBuffer, beat: AVAudioPCMBuffer)?), Error>
            do {
                removeOrphanedTakes()
                try configureSession()
                // The engine must be running before the instrument is handed
                // over: the sampler's DSP only learns the real hardware sample
                // rate when it is started, and `update(data:)` re-inits the core
                // sampler with whatever rate it knows at that moment. Load first
                // and every note plays sharp by the ratio between 44100 and the
                // actual rate.
                try engine.start()
                // Effect parameters are only writable once the engine has
                // instantiated the underlying audio units.
                reverb.loadFactoryPreset(.mediumRoom)
                reverb.dryWetMix = AUValue(mix)
                hall.loadFactoryPreset(.largeHall)
                hall.dryWetMix = 1

                // Set before the samples are handed over: swapping in new
                // sampler data copies the envelope settings across from the
                // current one, and the parameters reject writes made straight
                // after the swap.
                applySamplerParameters(for: choice)
                let samples = try loadInstrument(choice)
                outcome = .success((samples, try NodeRecorder(node: takeMix), makeClickSounds()))
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async { [self] in
                isStarting = false
                switch outcome {
                case .success(let ready):
                    loadedSamples = ready.samples
                    recorder = ready.recorder
                    clickSounds = ready.clicks
                    isInstrumentLoaded = true
                    observeAudioSession()
                case .failure(let error):
                    startupError = error.localizedDescription
                    Log("Audio start failed: \(error)")
                }
            }
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
        sungNote = nil
        player.stop()
        stopReplay()
        stopSequence()
        stopClicks()
        transport = .idle
    }

    /// Brings the engine back and hands the instrument over again, so a changed
    /// sample rate is picked up rather than silently detuning everything.
    func resumeAudio() {
        guard isInstrumentLoaded else { return }
        guard !engine.avEngine.isRunning else { return }
        let pedal = isSustaining
        let choice = instrument
        // Off the main thread for the same reason as starting up. Several
        // notifications can arrive together, so whichever runs first restarts
        // the engine and the rest find it running.
        audioQueue.async { [self] in
            guard !engine.avEngine.isRunning else { return }
            do {
                try configureSession()
                try engine.start()
                restoreInstrument(choice, pedal: pedal)
                if let microphone, !microphone.isRunning { try microphone.start() }
            } catch {
                Log("Could not resume audio: \(error)")
            }
        }
    }

    /// Hands the instrument to a restarted engine, which may be running at a
    /// new sample rate. On the audio queue.
    ///
    /// Always a freshly read instrument, never the one already playing:
    /// handing the sampler its current data again re-initialises the sampler
    /// the audio thread is playing from, and the next event to reach it - the
    /// pedal, restored just below - crashed the app.
    private func restoreInstrument(_ choice: Instrument, pedal: Bool) {
        do {
            // Same ordering as at startup, and for the same reason: the swap
            // copies these across from the current sampler and rejects writes
            // made straight after it.
            applySamplerParameters(for: choice)
            let samples = try loadInstrument(choice)
            DispatchQueue.main.async { [self] in
                if instrument == choice { loadedSamples = samples }
            }
        } catch {
            Log("Could not reload \(choice.name): \(error)")
        }
        // The sampler comes back with the pedal up, while the control went on
        // showing it down - so sustain looked on, did nothing, and had to be
        // pressed twice to come back.
        sampler.sustainPedal(pedalDown: pedal)
    }

    /// Volume and envelope for the sampler. Always set *before* sampler data
    /// is swapped in, never after: the swap copies these across from the
    /// current sampler, and writes made straight afterwards are rejected.
    private func applySamplerParameters(for instrument: Instrument) {
        sampler.masterVolume = 0.9
        // The dampers: a key let go without the pedal stops soon after.
        sampler.releaseDuration = instrument.release
    }

    /// Whether the session is set up for the microphone. Read and written on
    /// the audio queue only.
    @ObservationIgnored private var sessionListens = false

    private func configureSession() throws {
        #if os(iOS)
        if sessionListens {
            // Listening: the microphone in, and the instrument still out of
            // the speaker rather than the earpiece a call would use. Bluetooth
            // headphones keep their full-quality playback; the voice comes in
            // through the device's own microphone.
            try Settings.session.setCategory(.playAndRecord, mode: .default,
                                             options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        } else {
            // Otherwise playback only: the recorder taps a node inside the
            // graph, so nothing needs the microphone.
            try Settings.session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
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

    /// Reads the samples and hands them to the sampler, returning them so
    /// they can be handed over again after an interruption.
    private func loadInstrument(_ instrument: Instrument) throws -> SamplerData {
        let entries = instrument.samples
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

        guard !descriptors.isEmpty else { throw InstrumentError.noSamples }

        // buildKeyMap() works through the underlying C sampler, not the struct.
        let data = SamplerData(filesWithSampleDescriptors: descriptors)
        data.buildKeyMap()
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
        return data
    }

    enum InstrumentError: LocalizedError {
        case noSamples
        var errorDescription: String? { "No instrument samples found in the app bundle." }
    }

    // MARK: - Playing

    func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        guard isInstrumentLoaded, !activeNotes.contains(note) else { return }
        let at = now - recordingStart
        activeNotes.insert(note)
        sampler.play(noteNumber: note, velocity: velocity)
        // Played to the click, the take is written in bars as it goes;
        // otherwise each note is added after the last.
        if transport == .recording, takeTempo != nil {
            refreshLivePage()
        } else if pageIsLive {
            write(note, at: at)
        }
        if transport == .recording { scoreRecorder.noteOn(note, velocity: velocity, at: at) }
    }

    func noteOff(_ note: UInt8) {
        guard activeNotes.contains(note) else { return }
        let at = now - recordingStart
        activeNotes.remove(note)
        sampler.stop(noteNumber: note)
        if transport == .recording { scoreRecorder.noteOff(note, at: at) }
        if transport == .recording, takeTempo != nil { refreshLivePage() }
    }

    /// Notes played freely onto the page, with no take behind them - all a
    /// player has to clear when nothing's been recorded.
    var hasWrittenNotes: Bool {
        if case .written(let chords) = page { return !chords.isEmpty }
        return false
    }

    /// Wipes the freely played notes off the page, leaving everything else -
    /// the pedal, the instrument - as it is.
    func clearPage() {
        page = .written([])
        pageIsLive = true
    }

    /// Writes a played note onto the page. A very long session keeps its most
    /// recent stretch rather than growing without end.
    private func write(_ note: UInt8, at time: TimeInterval) {
        guard case .written(var chords) = page else { return }
        SheetMusic.add(note, at: time, to: &chords)
        if chords.count > 5000 { chords.removeFirst(1000) }
        page = .written(chords)
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
        // Down, the ring swells in; up, the dampers fall and it's gone soon
        // after - quickly, but not so suddenly that it clicks.
        fadeHall(to: on ? Self.pedalRing : 0, over: on ? 0.15 : 0.35)
    }

    /// How loud the pedal's ring is beside the piano.
    private static let pedalRing: AUValue = 0.45

    /// Mixer volume can't be ramped by the engine, so it's stepped here, often
    /// enough that the steps aren't heard.
    private func fadeHall(to target: AUValue, over duration: TimeInterval) {
        hallFade?.invalidate()
        let from = hallSend.volume
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (CACurrentMediaTime() - began) / duration)
            self.hallSend.volume = from + (target - from) * AUValue(progress)
            if progress >= 1 { timer.invalidate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hallFade = timer
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
            if transport == .recording { scoreRecorder.noteOff(note, at: now - recordingStart) }
        }
        activeNotes.removeAll()
    }

    // MARK: - Listening

    /// Whether the microphone is on, following a voice.
    private(set) var isListening = false
    /// The note being sung, lit on its key.
    private(set) var sungNote: UInt8?
    /// When the sung note began, and whether it has lasted long enough to be
    /// written down.
    @ObservationIgnored private var sungSince: TimeInterval = 0
    @ObservationIgnored private var sungIsWritten = false
    /// Why listening couldn't start, to tell the player.
    var listeningError: String?

    func toggleListening() {
        if isListening { stopListening() } else { startListening() }
    }

    /// Turns on the microphone. Restarting the engine would cut a take short,
    /// so it waits until nothing is being recorded.
    private func startListening() {
        guard isInstrumentLoaded, !isRecording, !isListening else { return }
        // Already allowed: on at once, so the button answers the tap.
        if AVAudioApplication.shared.recordPermission == .granted {
            beginListening()
            return
        }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.listeningError = "GoPiano needs the microphone to hear your voice. You can allow it in Settings, under Privacy & Security."
                    return
                }
                self.beginListening()
            }
        }
    }

    /// The microphone's own engine, while listening. Only ever touched on the
    /// audio queue.
    @ObservationIgnored private var microphone: AVAudioEngine?
    /// The metronome while listening: played by the microphone's engine, so
    /// its echo canceller knows the click and takes it back out of what the
    /// microphone hears. Nil when not listening, or when the device has no
    /// echo cancellation, and the instrument engine's click is used instead.
    @ObservationIgnored private var microphoneClick: AVAudioPlayerNode?
    private var clickPlayer: AVAudioPlayerNode { microphoneClick ?? click.player }

    /// What's listening, so the metronome can tell it to filter out its click.
    @ObservationIgnored private var voiceListener: VoiceListener?
    @ObservationIgnored private var voiceFeed: VoiceFeed?

    /// Whether the microphone should filter out the click: while it plays.
    private func filterClick(_ on: Bool) {
        voiceListener?.removesClick = on
        voiceFeed?.removesClick = on
    }

    private func beginListening() {
        guard !isListening, !isRecording else { return }
        isListening = true
        stopPlayback()
        allNotesOff()
        let choice = instrument, pedal = isSustaining
        let listener = VoiceListener { [weak self] event in self?.heard(event) }
        let feed = VoiceFeed(ring: voice.ring)
        voiceListener = listener
        voiceFeed = feed
        filterClick(clickTimer != nil)
        let sounds = clickSounds
        audioQueue.async { [self] in
            // The session's category can only change with the engine stopped.
            engine.stop()
            sessionListens = true
            do {
                try configureSession()
                try engine.start()
                restoreInstrument(choice, pedal: pedal)

                // The microphone gets an engine of its own. Once an engine has
                // used its input it expects one for good, and on a device it
                // then fails to start again under playback alone - so the
                // instruments went silent after singing, until a relaunch.
                voice.ring.clear()
                let opened = try openMicrophone(cancellingEcho: true, listener: listener, feed: feed, clicks: sounds)
                self.microphone = opened.engine
                DispatchQueue.main.async { [self] in microphoneClick = opened.clicks }

                // Echo cancellation isn't everywhere - the Simulator, some
                // routes - and where it fails the microphone can start but
                // deliver nothing. If nothing has arrived after a moment, it
                // opens again without it, so singing never just stops working.
                audioQueue.asyncAfter(deadline: .now() + 0.8) { [self] in
                    guard self.microphone === opened.engine,
                          !opened.hearing.isWorking(rate: opened.rate) else { return }
                    Log("No sound with echo cancellation; listening without it")
                    closeMicrophone()
                    do {
                        let plain = try openMicrophone(cancellingEcho: false, listener: listener, feed: feed, clicks: nil)
                        self.microphone = plain.engine
                    } catch {
                        Log("Could not start listening: \(error)")
                    }
                }
            } catch {
                Log("Could not start listening: \(error)")
                closeMicrophone()
                sessionListens = false
                engine.stop()
                try? configureSession()
                try? engine.start()
                restoreInstrument(choice, pedal: pedal)
                DispatchQueue.main.async { [self] in
                    isListening = false
                    listeningError = (error as? LocalizedError)?.errorDescription
                        ?? "The microphone couldn't be started."
                }
            }
        }
    }

    /// How much the microphone's tap has delivered, and whether any of it
    /// was more than digital silence - which a working microphone never gives.
    final class Hearing: @unchecked Sendable {
        var frames = 0
        var anySound = false
        func isWorking(rate: Double) -> Bool { anySound && Double(frames) >= rate * 0.4 }
    }

    /// Starts an engine for the microphone, with or without echo cancellation,
    /// feeding the pitch tracker and the voice for takes. With echo
    /// cancellation it also gets a player for the metronome, since the
    /// canceller can only take out what its own engine plays. On the audio
    /// queue.
    private func openMicrophone(cancellingEcho: Bool, listener: VoiceListener, feed: VoiceFeed,
                                clicks sounds: (accent: AVAudioPCMBuffer, beat: AVAudioPCMBuffer)?) throws
        -> (engine: AVAudioEngine, clicks: AVAudioPlayerNode?, hearing: Hearing, rate: Double) {
        let microphone = AVAudioEngine()
        let input = microphone.inputNode

        // Echo cancellation - the voice processing calls use - so that what
        // this engine plays is taken back out of what its microphone hears.
        // Over a phone's speaker the metronome's click is loud and distorted,
        // a few millimetres from the microphone: it went into takes, and was
        // even heard as a note. Filtering its pitches wasn't enough. The
        // instruments, on the other engine, aren't ducked for it.
        var clicks: AVAudioPlayerNode?
        if cancellingEcho {
            do {
                try input.setVoiceProcessingEnabled(true)
                input.voiceProcessingOtherAudioDuckingConfiguration =
                    .init(enableAdvancedDucking: false, duckingLevel: .min)
                if let sounds {
                    let player = AVAudioPlayerNode()
                    microphone.attach(player)
                    microphone.connect(player, to: microphone.mainMixerNode, format: sounds.accent.format)
                    clicks = player
                }
            } catch {
                Log("No echo cancellation: \(error)")
            }
        }

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ListeningError.noMicrophone
        }
        let hearing = Hearing()
        // Pitch from the tap, which arrives in tenth-of-a-second pieces: fine
        // for following a voice, and off the audio thread.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
            hearing.frames += Int(buffer.frameLength)
            if !hearing.anySound, let data = buffer.floatChannelData?[0] {
                for index in 0..<Int(buffer.frameLength) where data[index] != 0 {
                    hearing.anySound = true
                    break
                }
            }
            listener.take(buffer, at: when)
        }
        // The voice for takes straight from the audio thread, a few
        // milliseconds at a time, so it stays in time with the keys.
        let rate = format.sampleRate
        let sink = AVAudioSinkNode { _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
            if let data = buffers.first?.mData?.assumingMemoryBound(to: Float.self) {
                feed.take(data, count: Int(frameCount), rate: rate)
            }
            return noErr
        }
        microphone.attach(sink)
        microphone.connect(input, to: sink, format: format)
        try microphone.start()
        return (microphone, clicks, hearing, format.sampleRate)
    }

    /// Stops and lets go of the microphone's engine. On the audio queue.
    private func closeMicrophone() {
        if let microphone {
            microphone.inputNode.removeTap(onBus: 0)
            microphone.stop()
        }
        microphone = nil
        voice.ring.clear()
        DispatchQueue.main.async { [self] in microphoneClick = nil }
    }

    private func stopListening() {
        guard isListening, !isRecording else { return }
        isListening = false
        if let note = sungNote { endSung(note, at: now) }
        let choice = instrument, pedal = isSustaining
        audioQueue.async { [self] in
            closeMicrophone()
            // Back to playback alone, so the system's microphone indicator
            // goes out and audio sounds as it did before.
            engine.stop()
            sessionListens = false
            do {
                try configureSession()
                try engine.start()
                restoreInstrument(choice, pedal: pedal)
            } catch {
                Log("Could not stop listening: \(error)")
            }
        }
    }

    enum ListeningError: LocalizedError {
        case noMicrophone
        var errorDescription: String? { "No microphone is available." }
    }

    /// A note heard in the voice. It lights its key and goes on the page and
    /// into a take just as a played note does - but it isn't sounded, since
    /// the singer is already making it, and the microphone would only hear
    /// the instrument and chase it.
    private func heard(_ event: NoteSplitter.Event) {
        // Playing back, the voice in the take is coming out of the speaker:
        // the replay is already lighting those keys.
        guard isListening, transport != .playing else {
            releaseSungNote()
            return
        }
        switch event {
        case .began(let note, let time):
            // The click is a high F#/G and B: whatever gets past the echo
            // cancelling is not a note anyone sang.
            if clickTimer != nil, note >= Self.lowestClickNote { return }
            if let previous = sungNote { endSung(previous, at: time) }
            sungNote = note
            sungSince = time
            sungIsWritten = false
            // Lit at once, but written down only once it has lasted: a voice
            // breaking up for an instant, or a scoop between two notes, leaves
            // blips nobody meant as notes.
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, time + Self.shortestSungNote - now)) { [weak self] in
                guard let self, self.sungNote == note, self.sungSince == time else { return }
                self.writeSung(note, at: time)
            }
        case .ended(let note, let time):
            guard sungNote == note else { return }
            endSung(note, at: time)
        }
    }

    /// Lets go of whatever was being sung - as playback takes over the keys.
    /// Events from the microphone are ignored while something plays, so a
    /// note heard just before (a hum in the room, say) would otherwise stay
    /// lit right through it, and keep the keyboard where it had followed it.
    private func releaseSungNote() {
        if let note = sungNote { endSung(note, at: now) }
    }

    private static let shortestSungNote: TimeInterval = 0.1
    /// F#6, just under the metronome's lower tick.
    private static let lowestClickNote: UInt8 = 90

    private func writeSung(_ note: UInt8, at time: TimeInterval) {
        sungIsWritten = true
        let at = time - recordingStart
        if transport == .recording {
            scoreRecorder.noteOn(note, velocity: 90, at: max(0, at))
        }
        if transport == .recording, takeTempo != nil {
            refreshLivePage()
        } else if pageIsLive {
            write(note, at: at)
        }
    }

    private func endSung(_ note: UInt8, at time: TimeInterval) {
        sungNote = nil
        if !sungIsWritten, time - sungSince >= Self.shortestSungNote { writeSung(note, at: sungSince) }
        guard sungIsWritten else { return }
        sungIsWritten = false
        // Played on the keys at the same time, the key's own release ends it.
        guard transport == .recording, !activeNotes.contains(note) else { return }
        scoreRecorder.noteOff(note, at: max(0, time - recordingStart))
        if takeTempo != nil { refreshLivePage() }
    }

    // MARK: - Choosing what to play

    /// What's being played: one of the instruments on the keys, or a voice
    /// into the microphone. One list, so singing is just another way to play.
    enum Choice: Hashable {
        case instrument(Instrument)
        case voice
    }

    var choice: Choice { isListening ? .voice : .instrument(instrument) }

    /// Changes what's played. A melody that's playing carries on from the
    /// same moment in its new sound - a sung idea heard on guitar, then back
    /// in the voice that sang it.
    func choose(_ choice: Choice) {
        guard choice != self.choice else { return }
        // The microphone restarts the engine, which would cut a take short;
        // swapping one instrument for another mid-take is fine.
        if isRecording, choice == .voice || isListening { return }
        let resumeAt: TimeInterval? = transport == .playing && hasRecording ? readoutTime : nil
        if resumeAt != nil { stopPlayback() }
        switch choice {
        case .voice:
            startListening()
        case .instrument(let instrument):
            if isListening { stopListening() }
            setInstrument(instrument)
        }
        // After the engine and samples are ready: the audio queue runs in
        // order, so this lands behind them.
        if let resumeAt {
            audioQueue.async {
                DispatchQueue.main.async { [weak self] in self?.resumePlayback(at: resumeAt) }
            }
        }
    }

    /// A sung melody - a take sung into the microphone, or an imported voice
    /// memo - plays its notes on the chosen instrument, and in the voice
    /// itself only when Voice is chosen. Takes played on the keys always play
    /// as they were recorded.
    var playsSungNotes: Bool {
        hasRecording && currentScore.isSung == true && !currentScore.isEmpty && !isListening
    }

    private func resumePlayback(at position: TimeInterval) {
        guard transport == .idle, hasRecording else { return }
        releaseSungNote()
        if playsSungNotes {
            startNotes(from: position)
        } else {
            player.play(from: position)
            transport = .playing
            startReplay()
        }
    }

    private func startNotes(from position: TimeInterval) {
        sequence = Self.events(for: currentScore)
        startSequence(from: position)
    }

    // MARK: - Transport

    func toggleRecording() {
        switch transport {
        case .recording: stopRecording()
        case .countingIn:
            // Changed their mind during the count: nothing was recorded.
            stopClicks()
            transport = .idle
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
        finishedTakeDuration = 0
        hasUnsavedTake = false
        // A new take starts a new page.
        page = .written([])
        pageIsLive = true
        currentScore = MelodyScore()

        let metronome = Self.metronomeSettings
        guard metronome.isOn, clickSounds != nil else {
            takeTempo = nil
            takeSignature = nil
            beginTake(at: now)
            return
        }

        // One bar counted in, then the take starts on the downbeat, so its
        // notes can be counted in beats from the first one.
        takeTempo = metronome.tempo
        takeSignature = TimeSignature(beats: metronome.beatsPerBar, unit: 4)
        let interval = 60 / metronome.tempo
        let firstClick = now + 0.1
        let downbeat = firstClick + interval * Double(metronome.beatsPerBar)
        transport = .countingIn
        countInBeatsLeft = metronome.beatsPerBar
        startClicks(at: firstClick, interval: interval, beatsPerBar: metronome.beatsPerBar)
        let start = DispatchWorkItem { [weak self] in self?.beginTake(at: downbeat) }
        downbeatWork = start
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, downbeat - now), execute: start)
    }

    private func beginTake(at start: TimeInterval) {
        guard let recorder else { return }
        downbeatWork = nil
        do {
            try recorder.reset()
            try recorder.record()
            scoreRecorder.reset()
            recordingStart = start
            transport = .recording
        } catch {
            stopClicks()
            transport = .idle
            Log("Could not start recording: \(error)")
        }
    }

    private func stopRecording() {
        guard let recorder else { return }
        let elapsed = now - recordingStart
        recorder.stop()
        stopClicks()
        transport = .idle
        finishedTakeDuration = elapsed
        currentScore = scoreRecorder.finish(at: elapsed)
        // Played to the click, every note can be counted in beats - which is
        // what lets the take be written with real note values, and saved so
        // its sheet music keeps them.
        if let tempo = takeTempo, let signature = takeSignature {
            currentScore = Self.measured(currentScore, tempo: tempo, signature: signature)
        }
        // Sung with the microphone on: the voice is in the recording.
        if isListening, !currentScore.isEmpty { currentScore.isSung = true }
        takeTempo = nil
        takeScore = currentScore
        // The page now is the take, timed from its start so a replay can
        // follow along on it.
        page = SheetPage(score: currentScore)
        pageIsLive = false
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
        case .recording, .countingIn:
            break
        case .idle:
            releaseSungNote()
            if hasSequence {
                startSequence(from: 0)
            } else if playsSungNotes {
                startNotes(from: 0)
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
        // Stopped to hand over to the instrument, not finished.
        guard !isPerformingNotes else { return }
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
        page = SheetPage(score: currentScore)
        pageIsLive = false
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
        page = SheetPage(score: score)
        pageIsLive = false
        finishedTakeDuration = score.duration
        transport = .idle
    }

    func reset() {
        player.stop()
        stopReplay()
        stopSequence()
        stopClicks()
        takeTempo = nil
        hasSequence = false
        hasUnsavedTake = false
        takeScore = MelodyScore()
        sequence = []
        page = .written([])
        pageIsLive = true
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

    // MARK: - Metronome

    static let metronomeKey = "metronome"
    static let tempoKey = "tempo"
    static let beatsPerBarKey = "beatsPerBar"

    /// What Settings stored, read as each take starts.
    private static var metronomeSettings: (isOn: Bool, tempo: Double, beatsPerBar: Int) {
        let defaults = UserDefaults.standard
        let tempo = defaults.object(forKey: tempoKey) as? Int ?? 100
        let beats = defaults.object(forKey: beatsPerBarKey) as? Int ?? 4
        return (defaults.bool(forKey: metronomeKey),
                Double(min(max(tempo, 30), 240)),
                min(max(beats, 2), 7))
    }

    /// The tempo and time signature of the take under way, when it is played
    /// to the click; nil for a take played freely.
    private var takeTempo: Double?
    private var takeSignature: TimeSignature?

    private var clickSounds: (accent: AVAudioPCMBuffer, beat: AVAudioPCMBuffer)?
    private var clickTimer: Timer?
    private var clickOrigin: TimeInterval = 0
    private var clickInterval: TimeInterval = 0.6
    private var clickBeatsPerBar = 4
    private var clickNext = 0
    private var downbeatWork: DispatchWorkItem?

    /// Two short, bright ticks - higher for the first beat of the bar - made in
    /// whatever format the graph gave the click, which a player has to match.
    private func makeClickSounds() -> (accent: AVAudioPCMBuffer, beat: AVAudioPCMBuffer)? {
        let format = click.player.outputFormat(forBus: 0)
        func tick(pitch: Double, level: Float) -> AVAudioPCMBuffer? {
            let rate = format.sampleRate
            let frames = AVAudioFrameCount(rate * 0.06)
            guard rate > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let channels = buffer.floatChannelData else { return nil }
            buffer.frameLength = frames
            for frame in 0..<Int(frames) {
                let time = Double(frame) / rate
                // A 2 ms rise: an instant start is a snap across every
                // frequency, which the filters that keep the click out of
                // the microphone couldn't catch.
                let rise = min(1, time / 0.002)
                let sample = Float(sin(2 * .pi * pitch * time) * exp(-time * 70) * rise) * level
                for channel in 0..<Int(format.channelCount) { channels[channel][frame] = sample }
            }
            return buffer
        }
        guard let accent = tick(pitch: Metronome.accentPitch, level: 0.55),
              let beat = tick(pitch: Metronome.beatPitch, level: 0.35) else {
            return nil
        }
        return (accent, beat)
    }

    private func startClicks(at origin: TimeInterval, interval: TimeInterval, beatsPerBar: Int) {
        stopClicks()
        clickOrigin = origin
        clickInterval = interval
        clickBeatsPerBar = beatsPerBar
        clickNext = 0
        clickPlayer.play()
        filterClick(true)
        scheduleClicks()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.scheduleClicks() }
        RunLoop.main.add(timer, forMode: .common)
        clickTimer = timer
    }

    /// Clicks are booked a little ahead at exact host times, so they keep time
    /// to the sample rather than to whenever this timer gets round to it.
    private func scheduleClicks() {
        guard let sounds = clickSounds else { return }
        while clickOrigin + Double(clickNext) * clickInterval < now + 0.4 {
            let at = clickOrigin + Double(clickNext) * clickInterval
            let sound = clickNext % clickBeatsPerBar == 0 ? sounds.accent : sounds.beat
            clickPlayer.scheduleBuffer(sound, at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: at)))
            clickNext += 1
        }
        if transport == .countingIn {
            let elapsed = Int(((now - clickOrigin) / clickInterval).rounded(.down))
            let left = max(1, clickBeatsPerBar - max(0, elapsed))
            if left != countInBeatsLeft { countInBeatsLeft = left }
        }
    }

    private func stopClicks() {
        clickTimer?.invalidate()
        clickTimer = nil
        // The last click is still ringing in the room for a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.clickTimer == nil else { return }
            self.filterClick(false)
        }
        downbeatWork?.cancel()
        downbeatWork = nil
        click.player.stop()
        microphoneClick?.stop()
    }

    /// The take so far, written in bars: rebuilt as each note starts and ends.
    private func refreshLivePage() {
        guard transport == .recording, let tempo = takeTempo, let signature = takeSignature else { return }
        let elapsed = now - recordingStart
        let sofar = MelodyScore(spans: scoreRecorder.snapshot(at: elapsed), duration: elapsed)
        if let music = MeteredMusic(score: Self.measured(sofar, tempo: tempo, signature: signature)) {
            page = .metered(music)
        }
    }

    /// A take recorded to the click, with every note's place and length
    /// counted in beats at the tempo it was played to.
    static func measured(_ score: MelodyScore, tempo: Double, signature: TimeSignature) -> MelodyScore {
        let perBeat = 60 / tempo
        var measured = score
        measured.spans = score.spans.map {
            NoteSpan(note: $0.note, start: $0.start, end: $0.end, velocity: $0.velocity,
                     beat: $0.start / perBeat, beats: ($0.end - $0.start) / perBeat)
        }
        measured.timeSignature = signature
        measured.tempo = tempo
        return measured
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

    /// Performs `sequence` from `position` seconds in. Notes already sounding
    /// at that moment are struck, so starting partway through a held note
    /// doesn't leave a gap until the next one.
    private func startSequence(from position: TimeInterval) {
        guard !sequence.isEmpty else { return }
        stopSequence()
        isPerformingNotes = true
        sequenceStart = now - position
        sequenceIndex = sequence.firstIndex { $0.time >= position } ?? sequence.count
        if position > 0 {
            for span in currentScore.spans where span.start < position && span.end > position {
                sampler.play(noteNumber: span.note, velocity: span.velocity)
                sequencedNotes[span.note, default: 0] += 1
            }
            replayNotes = Set(sequencedNotes.keys)
        }
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
        guard transport == .playing, isPerformingNotes else { stopSequence(); return }
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
        isPerformingNotes = false
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

/// The voice's way into takes: plays whatever the microphone's engine has
/// handed across, and silence otherwise.
final class VoiceNode: Node {
    let ring = VoiceRing()
    private let source: AVAudioSourceNode

    init() {
        let ring = ring
        source = AVAudioSourceNode(format: VoiceRing.format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            ring.read(into: first, count: frames)
            for buffer in buffers.dropFirst() {
                buffer.mData?.assumingMemoryBound(to: Float.self).update(from: first, count: frames)
            }
            return noErr
        }
    }

    var avAudioNode: AVAudioNode { source }
    var connections: [Node] { [] }
    /// Connected at its own rate, so the engine converts it rather than
    /// playing it at the wrong speed.
    var outputFormat: AVAudioFormat { VoiceRing.format }
}

/// The metronome's voice in the audio graph: a plain player node, wrapped so
/// AudioKit can mix it in alongside the piano.
final class ClickNode: Node {
    let player = AVAudioPlayerNode()
    var avAudioNode: AVAudioNode { player }
    var connections: [Node] { [] }
}
