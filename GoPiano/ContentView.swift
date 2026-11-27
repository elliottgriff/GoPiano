//
//  ContentView.swift
//  GoPiano
//

import Combine
import SwiftUI

struct ContentView: View {
    @Environment(Conductor.self) private var conductor
    @Environment(\.colorScheme) private var colorScheme
    private var finish: Finish { Finish(colorScheme) }
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("firstOctave") private var firstOctave = 3
    @AppStorage("octaveCount") private var octaveCount = 1
    @AppStorage("showsLabels") private var showsLabels = true
    /// Until the player picks a width themselves, a big screen gets a big
    /// keyboard rather than one octave of enormous keys.
    @AppStorage("hasChosenOctaveCount") private var hasChosenOctaveCount = false

    /// Mirrors `Conductor.readoutTime` so the readout redraws as it ticks.
    @State private var elapsed: TimeInterval = 0
    @State private var showRecordings = false
    @State private var saveConfirmation: String?
    @State private var isNamingTake = false
    @State private var takeName = ""
    @State private var saveError: String?
    @State private var showSettings = false
    /// A melody imported from the library, waiting for the sheet to go so it
    /// can be played on the keyboard rather than behind it.
    @State private var imported: (score: MelodyScore, name: String)?
    @State private var isConfirmingReset = false
    @State private var isExplainingImportSave = false
    /// The name of the imported song on the keyboard, for its sheet music.
    @State private var importName = "Imported Song"
    @State private var sharedFile: ExportedFile?

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    /// Stop short of the two octaves above the sampled range, which were just
    /// the topmost sample stretched upwards and sounded thin for it.
    private var maxFirstOctave: Int {
        let highestOctave = (SampleMap.highestSampledNote - baseMIDINote - 11) / 12
        return max(0, highestOctave - (octaveCount - 1))
    }

    /// How many octaves the screen can show while the white keys stay wide
    /// enough to hit: a phone fits two, an iPad three. The keys keep real
    /// proportions whatever the count, and on an iPad the height that leaves
    /// above them goes to the score.
    private var maxOctaves: Int {
        let minimumWhiteKey: CGFloat = 48
        let whiteKeys = Int(screenSize.width / minimumWhiteKey)
        // Every keyboard ends on a trailing C, so octaves are counted after it.
        return min(3, max(1, (whiteKeys - 1) / 7))
    }

    /// The narrowest the keyboard goes. An iPad keeps at least two octaves,
    /// so the keys never grow tall enough to push the music off the screen;
    /// a phone, with no music above its keys, can go down to one.
    private var minOctaves: Int {
        isPad ? min(2, maxOctaves) : 1
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var screenSize: CGSize {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.size }
            .max { $0.width < $1.width } ?? .zero
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            keyboardArea
            // A bezel along the front edge, where a real keyboard has one. It
            // also keeps the keys out of the home indicator, so the swipe that
            // leaves the app doesn't sound a note on the way out.
            bezel
        }
        // The colour runs under the home indicator while the content stays
        // inside the safe area, so the front edge reads as one strip.
        .background(finish.bezel.ignoresSafeArea())
        .overlay(alignment: .top) { startupError }
        .sheet(isPresented: $showRecordings, onDismiss: playImported) {
            RecordingsView(onImport: { imported = ($0, $1) })
        }
        .alert("Save Melody", isPresented: $isNamingTake) {
            TextField("Name", text: $takeName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { save(as: takeName) }
        } message: {
            Text("Saved melodies appear in the Files app and can be shared.")
        }
        .alert("Discard This Take?", isPresented: $isConfirmingReset) {
            Button("Discard", role: .destructive) { resetTake() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It hasn't been saved, so it can't be got back.")
        }
        .alert("Imported Songs Can't Be Saved Yet", isPresented: $isExplainingImportSave) {
            // Its notes are all an import has, which is exactly what sheet
            // music needs.
            Button("Share Sheet Music") { shareImportedSheetMusic() }
            Button("OK", role: .cancel) {}
        } message: {
            Text("An imported song is only its notes, with no recording behind it, so there's nothing to save as a melody. You can still share it as sheet music.")
        }
        .alert("Couldn't Save",
               isPresented: Binding(get: { saveError != nil },
                                    set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear {
            conductor.start()
            applyDefaultWidth()
            clampOctave()
        }
        .onReceive(tick) { _ in
            // Read off the recorder's own clock rather than adding 0.05 to a
            // counter: ticks arrive late under load, so a late tick now shows
            // up as a less frequent update instead of a short take.
            let shown = conductor.readoutTime
            if shown != elapsed { elapsed = shown }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { conductor.allNotesOff() }
        }
    }

    // MARK: - Controls

    /// Grouped by what each part is for - where you are on the keyboard, the
    /// take, the library - with Record as the one primary control. It used to
    /// be eleven identical circles, Settings exactly as loud as Record.
    private var controlBar: some View {
        HStack(spacing: 8) {
            // Each group takes its natural width and only the spacers give.
            // Left flexible, the groups competed with the spacers for room
            // and SwiftUI squeezed the text out of the Save button to make it.
            pedal.fixedSize()
            instrumentButton.fixedSize()
            octaveStepper.fixedSize()
            Spacer(minLength: 6)
            transport.fixedSize()
            Spacer(minLength: 6)
            panelIcon("music.note.list", enabled: true) { showRecordings = true }
                .accessibilityLabel("Melodies")
            panelIcon("gearshape", enabled: true) { showSettings = true }
                .accessibilityLabel("Settings")
                .popover(isPresented: $showSettings) {
                    SettingsView(showsLabels: $showsLabels)
                        .presentationCompactAdaptation(.popover)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        // Here rather than beside the Melodies sheet: two sheets on one view
        // and only the last one presents.
        .sheet(item: $sharedFile) { ExportShareSheet(file: $0) }
        .background {
            // The case of the instrument - black lacquer, or ivory in light
            // mode - with a catch of light along its top edge. It meets the
            // felt drawn at the back of the keys.
            LinearGradient(colors: finish.bar, startPoint: .top, endPoint: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(finish.barHighlight).frame(height: 1)
                }
                .ignoresSafeArea(edges: [.top, .horizontal])
        }
    }

    /// The keys at their proper proportions, and the music written out in the
    /// space that leaves above them. On a phone the keys need every point of
    /// the height, so there is no room for a score and none is shown. On an
    /// iPad the music is always there: where the keys would leave it too
    /// little room, they give up some length instead.
    private var keyboardArea: some View {
        GeometryReader { proxy in
            let whiteKeys = CGFloat(octaveCount * 7 + 1)
            let natural = min(proxy.size.height,
                              proxy.size.width / whiteKeys * PianoLayout.longestKeyRatio)
            let keyLength = isPad ? min(natural, proxy.size.height - Self.shortestScore) : natural
            let scoreHeight = proxy.size.height - keyLength
            let showsScore = isPad || scoreHeight >= Self.shortestScore
            VStack(spacing: 0) {
                if showsScore {
                    ScoreView().frame(height: scoreHeight)
                }
                KeyboardView(firstOctave: firstOctave,
                             octaveCount: octaveCount,
                             showsLabels: showsLabels)
                    .frame(height: showsScore ? keyLength : proxy.size.height)
            }
        }
        .background(finish.bezel)
    }

    /// Below this a grand staff is too cramped to read, and the keys may as
    /// well have the height.
    private static let shortestScore: CGFloat = 150

    /// A front edge below the keys. Devices with a home indicator get most of
    /// this from the safe area; this is the minimum for those without one.
    private var bezel: some View {
        LinearGradient(colors: [finish.bezelEdge, finish.bezel],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 14)
            .overlay(alignment: .top) {
                Rectangle().fill(finish.bezelLine).frame(height: 1)
            }
    }

    // MARK: Instrument

    /// Beside the pedal, so the sound can change mid-play. On a phone, where
    /// the bar has no room to spare, it's an icon; an iPad has room for the
    /// name as well.
    private var instrumentButton: some View {
        let current = conductor.instrument
        return Menu {
            Picker("Instrument", selection: Binding(get: { conductor.instrument },
                                                    set: { conductor.setInstrument($0) })) {
                ForEach(Instrument.allCases) { instrument in
                    Label(instrument.name, systemImage: instrument.symbol).tag(instrument)
                }
            }
        } label: {
            PanelKey(shape: Capsule(), colors: nil, pressed: false) {
                HStack(spacing: 6) {
                    Image(systemName: current.symbol)
                        .font(.system(size: unit * 0.38, weight: .semibold))
                    if isPad {
                        Text(current.name)
                            .font(.system(size: unit * 0.36, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(finish.panelText)
                .padding(.horizontal, isPad ? 14 : 0)
                .frame(minWidth: unit, minHeight: unit)
            }
        }
        .disabled(!conductor.isInstrumentLoaded)
        .opacity(conductor.isInstrumentLoaded ? 1 : 0.4)
        .accessibilityLabel("Instrument")
        .accessibilityValue(current.name)
    }

    // MARK: Pedal

    /// A pedal you hold, the way a pianist uses one: down while the thumb is
    /// on it, up when it lifts - changed with each chord so the harmonies don't
    /// blur. A quick tap still latches it down for hands-free sustain, and
    /// another tap lifts it.
    ///
    /// Touches come through the same tracker as the keys, which recognises
    /// alongside every other touch, so the pedal works while the other hand is
    /// playing.
    private var pedal: some View {
        let down = conductor.isSustaining
        let loaded = conductor.isInstrumentLoaded
        // Down is a lit, pressed-in green rather than a tint on an icon, so
        // it reads by brightness as well as by colour.
        let fill: [Color] = down
            ? [Color(red: 0.16, green: 0.50, blue: 0.29), Color(red: 0.24, green: 0.66, blue: 0.38)]
            : finish.panel
        let rim: LinearGradient = down
            ? LinearGradient(colors: [.white.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            : finish.panelRim
        let shadow: Color = down ? .clear : finish.panelShadow
        let text: Color = down ? .white : finish.panelText
        return Text("Pedal")
            .font(.system(size: unit * 0.375, weight: .semibold))
            .foregroundStyle(text)
            .padding(.horizontal, 14)
            .frame(height: unit)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(rim, lineWidth: 1))
                    .shadow(color: shadow, radius: 1.5, y: 1)
            }
            .overlay {
                TouchTracker { points in pedalTouched(!points.isEmpty) }
                    .allowsHitTesting(loaded)
            }
            .opacity(loaded ? 1 : 0.4)
            .accessibilityElement()
            .accessibilityLabel("Sustain pedal")
            .accessibilityValue(down ? "Down" : "Up")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Hold while playing to sustain. Tap to keep it down.")
            .accessibilityAction { conductor.setSustain(!conductor.isSustaining) }
    }

    @State private var pedalPressStart: Date?
    @State private var pedalWasLatched = false

    private func pedalTouched(_ touching: Bool) {
        if touching {
            guard pedalPressStart == nil else { return }
            pedalPressStart = Date()
            pedalWasLatched = conductor.isSustaining
            conductor.setSustain(true)
        } else {
            guard let start = pedalPressStart else { return }
            pedalPressStart = nil
            let tapped = Date().timeIntervalSince(start) < 0.3
            // A quick tap on a lifted pedal leaves it latched down. Anything
            // else - a hold, or a tap on a latched pedal - lets it up.
            if tapped && !pedalWasLatched { return }
            conductor.setSustain(false)
        }
    }

    // MARK: Where you are

    private var octaveStepper: some View {
        HStack(spacing: 4) {
            panelIcon("minus", enabled: firstOctave > 0) { firstOctave -= 1 }
                .accessibilityLabel("Octave down")
            rangeButton
            panelIcon("plus", enabled: firstOctave < maxFirstOctave) { firstOctave += 1 }
                .accessibilityLabel("Octave up")
        }
    }

    /// The notes on screen, between the buttons that move them - a stepper, read
    /// as one. Tapping it switches between the narrowest keyboard - one octave
    /// on a phone, two on an iPad - and as many octaves as fit. It
    /// replaces an unlabelled switch that did the same thing without saying so,
    /// and it is the only place that says where on the keyboard you are once
    /// note names are off.
    private var rangeButton: some View {
        let low = PianoLayout.name(for: UInt8(clamping: baseMIDINote + firstOctave * 12))
        let high = PianoLayout.name(for: UInt8(clamping: baseMIDINote + (firstOctave + octaveCount) * 12))
        let canWiden = maxOctaves > minOctaves
        return Button {
            hasChosenOctaveCount = true
            octaveCount = octaveCount > minOctaves ? minOctaves : maxOctaves
            clampOctave()
        } label: {
            Text("\(low)–\(high)")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(finish.panelText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: unit)
        }
        .buttonStyle(PanelButtonStyle(shape: Capsule()))
        .disabled(!canWiden)
        .opacity(canWiden ? 1 : 0.5)
        .accessibilityLabel("Keyboard range")
        .accessibilityValue("\(low) to \(high)")
        .accessibilityHint(octaveCount > minOctaves
                           ? (minOctaves == 1 ? "Shows one octave" : "Shows \(minOctaves) octaves")
                           : "Shows \(maxOctaves) octaves")
    }

    // MARK: The take

    /// Discard, record, play, how long, save. Discard and Save appear only when
    /// there is something for them to act on, but they keep their places, so
    /// nothing shifts under a thumb when they arrive.
    private var transport: some View {
        HStack(spacing: 6) {
            // Also the way to wipe the music page after playing freely, which
            // leaves notes there but no take - on iPad, where the page shows.
            panelIcon("trash", enabled: true) { discardTapped() }
                .accessibilityLabel(conductor.hasSequence || !conductor.canPlay ? "Clear" : "Discard take")
                .contextual(conductor.canPlay || conductor.isRecording
                            || (isPad && conductor.hasWrittenNotes))

            recordButton

            panelIcon(conductor.isPlaying ? "pause.fill" : "play.fill",
                      enabled: conductor.canPlay && !conductor.isRecording) {
                conductor.togglePlayback()
            }
            .accessibilityLabel(conductor.isPlaying ? "Pause" : "Play")

            timeReadout

            saveButton
                .contextual((conductor.hasUnsavedTake || conductor.hasSequence) && !conductor.isRecording)
        }
    }

    /// The primary control: bigger, and the only filled colour on the bar. It
    /// glows while a take is running, so recording can't be missed.
    private var recordButton: some View {
        let recording = conductor.isRecording
        let loaded = conductor.isInstrumentLoaded
        return Button {
            if !recording { elapsed = 0 }
            conductor.toggleRecording()
        } label: {
            Group {
                if recording {
                    RoundedRectangle(cornerRadius: 3).fill(.white)
                        .frame(width: unit * 0.375, height: unit * 0.375)
                } else {
                    Circle().fill(.white).frame(width: unit * 0.42, height: unit * 0.42)
                }
            }
            .frame(width: unit + 8, height: unit + 8)
        }
        .buttonStyle(PanelButtonStyle(shape: Circle(),
                                      colors: [Color(red: 0.93, green: 0.25, blue: 0.22),
                                               Color(red: 0.68, green: 0.10, blue: 0.10)]))
        .shadow(color: .red.opacity(recording ? 0.7 : 0), radius: 8)
        .animation(.easeInOut(duration: 0.2), value: recording)
        .disabled(!loaded)
        .opacity(loaded ? 1 : 0.4)
        .accessibilityLabel(recording ? "Stop recording" : "Record")
    }

    /// Words rather than an icon: the download-arrow glyph this used to be
    /// read as "download", not "keep this take".
    private var saveButton: some View {
        Button { saveTapped() } label: {
            Text("Save")
                .font(.system(size: unit * 0.375, weight: .semibold))
                .foregroundStyle(Color(white: 0.08))
                .padding(.horizontal, 14)
                .frame(height: unit)
        }
        .buttonStyle(PanelButtonStyle(shape: Capsule(),
                                      colors: [Color(white: 0.97), Color(white: 0.82)]))
        .accessibilityLabel("Save take")
    }

    /// An inset display rather than an outlined box, and red while a take is
    /// running - the one state that most needs to be unmissable.
    private var timeReadout: some View {
        // Counting in, the clock counts the beats down to the downbeat.
        Text(conductor.isCountingIn ? "\(conductor.countInBeatsLeft)" : saveConfirmation ?? format(elapsed))
            .font(.system(.callout, design: .monospaced).weight(.medium))
            .foregroundStyle(conductor.isRecording
                             ? Color(red: 1.0, green: 0.38, blue: 0.33)
                             : Color(white: 0.92))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minWidth: 80)
            .padding(.vertical, (unit - 22) / 2)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(finish.display)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(LinearGradient(colors: [.black.opacity(0.6), .white.opacity(0.08)],
                                                     startPoint: .top, endPoint: .bottom),
                                      lineWidth: 1))
            }
    }

    // Sits right beside Record, so a slip is easy. Asking every time would be
    // a tax; asking only when a take would be lost is not.
    private func discardTapped() {
        if conductor.isRecording || conductor.hasUnsavedTake {
            isConfirmingReset = true
        } else if !conductor.canPlay {
            // Nothing recorded: just the notes played freely onto the page.
            conductor.clearPage()
        } else {
            resetTake()
        }
    }

    // An import on screen is what the player is looking at, so a tap means
    // "save this" - explain, rather than quietly saving an earlier take they
    // can't see.
    private func saveTapped() {
        if conductor.hasSequence {
            isExplainingImportSave = true
        } else {
            takeName = RecordingStore.shared.suggestedName()
            isNamingTake = true
        }
    }

    // MARK: Panel parts

    /// The size every control is built from. A little bigger on iPad, where
    /// phone-sized buttons spread across a 13-inch bar looked lost. Decided by
    /// device rather than size class: a large iPhone in landscape reports a
    /// regular width too, and its bar has no room to grow.
    private var unit: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 46 : 40
    }

    private func panelIcon(_ symbol: String,
                           enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: unit * 0.4, weight: .semibold))
                .foregroundStyle(finish.panelText)
                .frame(width: unit, height: unit)
        }
        .buttonStyle(PanelButtonStyle(shape: Circle()))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    @ViewBuilder
    private var startupError: some View {
        if let message = conductor.startupError {
            Text(message)
                .font(.footnote)
                .padding(8)
                .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
                .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func clampOctave() {
        // A keyboard wider than the screen can show would just squash the keys.
        octaveCount = min(max(minOctaves, octaveCount), maxOctaves)
        firstOctave = min(max(0, firstOctave), maxFirstOctave)
    }

    /// On an iPad, start wide instead of on one octave of enormous keys. A
    /// phone starts on one, where two are thin enough to choose deliberately.
    private func applyDefaultWidth() {
        guard !hasChosenOctaveCount else { return }
        if isPad { octaveCount = maxOctaves }
    }

    /// Moves the keyboard to where the imported melody is played, as widely as
    /// the screen allows, and starts it. Notes outside that still sound; they
    /// just have no key on screen to light.
    private func playImported() {
        guard let (score, name) = imported else { return }
        imported = nil
        importName = name
        conductor.load(score)
        let framing = score.framing(maximumOctaves: maxOctaves)
        octaveCount = framing.octaveCount
        firstOctave = framing.firstOctave
        clampOctave()
        conductor.togglePlayback()
        // The readout is the one place on screen with room for words; the
        // song's name sits there long enough to read, then the clock returns.
        flash(name, for: 2.5)
    }

    private func shareImportedSheetMusic() {
        do {
            sharedFile = ExportedFile(url: try SheetMusicPDF.write(conductor.currentScore,
                                                                   named: importName,
                                                                   subtitle: "Imported from a MIDI file"),
                                      kind: .sheetMusic)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func resetTake() {
        conductor.reset()
        elapsed = 0
    }

    private func save(as name: String) {
        do {
            _ = try conductor.saveRecording(named: name)
            flash("Saved")
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func flash(_ message: String, for seconds: Double = 1.5) {
        saveConfirmation = message
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            saveConfirmation = nil
        }
    }

    /// Minutes, seconds and hundredths the way a stopwatch shows them: 0:14.50.
    /// Written as 00:14:50 it read as fourteen minutes fifty.
    private func format(_ seconds: TimeInterval) -> String {
        let hundredths = Int((max(0, seconds) * 100).rounded())
        return String(format: "%d:%02d.%02d",
                      hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }
}

/// A soft raised key on the instrument's panel: lit from above, pressing in
/// when touched.
private struct PanelButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    /// The key's own colours; the finish's panel colours when not given.
    var colors: [Color]?

    func makeBody(configuration: Configuration) -> some View {
        PanelKey(shape: shape, colors: colors, pressed: configuration.isPressed) {
            configuration.label
        }
    }
}

private struct PanelKey<S: InsettableShape, Label: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let shape: S
    let colors: [Color]?
    let pressed: Bool
    @ViewBuilder let label: Label

    var body: some View {
        let finish = Finish(colorScheme)
        let fill = colors ?? finish.panel
        label
            .background {
                shape
                    .fill(LinearGradient(colors: pressed ? fill.reversed() : fill,
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(finish.panelRim, lineWidth: 1))
                    .shadow(color: pressed ? .clear : finish.panelShadow, radius: 1.5, y: 1)
            }
            .contentShape(shape)
    }
}

/// The instrument's finish. Black lacquer in dark mode; in light mode the
/// ivory of a white piano, so the case matches the keys instead of framing
/// them in black. The felt stays red and the clock stays a dark display
/// either way.
struct Finish {
    let dark: Bool

    init(_ scheme: ColorScheme) { dark = scheme == .dark }

    private static func ivory(_ value: Double) -> Color {
        Color(red: value, green: value * 0.992, blue: value * 0.965)
    }

    /// The control bar: lit from above.
    var bar: [Color] {
        dark ? [Color(white: 0.14), Color(white: 0.07)] : [Self.ivory(0.975), Self.ivory(0.925)]
    }
    var barHighlight: Color { dark ? .white.opacity(0.07) : .white.opacity(0.9) }

    /// Around and below the keys.
    var bezel: Color { dark ? Color(white: 0.06) : Self.ivory(0.9) }
    var bezelEdge: Color { dark ? Color(white: 0.10) : Self.ivory(0.86) }
    var bezelLine: Color { dark ? .black.opacity(0.5) : .black.opacity(0.12) }

    /// The raised keys of the control panel.
    var panel: [Color] {
        dark ? [Color(white: 0.24), Color(white: 0.15)] : [Self.ivory(1.0), Self.ivory(0.93)]
    }
    var panelText: Color { dark ? Color(white: 0.92) : Color(white: 0.16) }
    var panelRim: LinearGradient {
        LinearGradient(colors: dark ? [.white.opacity(0.18), .white.opacity(0.03)]
                                    : [.white.opacity(0.9), .black.opacity(0.10)],
                       startPoint: .top, endPoint: .bottom)
    }
    var panelShadow: Color { dark ? .black.opacity(0.5) : .black.opacity(0.16) }

    /// The clock's window: dark in both, solid enough to stay a display on ivory.
    var display: Color { dark ? .black.opacity(0.55) : Color(white: 0.13).opacity(0.92) }

    /// The page of music above the keys.
    var page: [Color] {
        dark ? [Color(white: 0.10), Color(white: 0.05)] : [Self.ivory(0.985), Self.ivory(0.95)]
    }
}

private extension View {
    /// Shown only when it applies, but always holding its place, so the
    /// controls around it never move.
    func contextual(_ shown: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .animation(.easeOut(duration: 0.15), value: shown)
    }
}
