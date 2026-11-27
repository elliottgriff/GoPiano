//
//  ContentView.swift
//  GoPiano
//

import Combine
import SwiftUI

struct ContentView: View {
    @Environment(Conductor.self) private var conductor
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

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    /// Stop short of the two octaves above the sampled range, which were just
    /// the topmost sample stretched upwards and sounded thin for it.
    private var maxFirstOctave: Int {
        let highestOctave = (SampleMap.highestSampledNote - baseMIDINote - 11) / 12
        return max(0, highestOctave - (octaveCount - 1))
    }

    /// How many octaves the screen can show while the white keys stay wide
    /// enough to play comfortably. A phone fits two, an iPad three. Four fits
    /// on a 13-inch iPad but the keys end up too thin to hit.
    private var maxOctaves: Int {
        let minimumWhiteKey: CGFloat = 48
        let fits = Int(screenWidth / (7 * minimumWhiteKey))
        return min(3, max(1, fits))
    }

    private var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.bounds.width }
            .max() ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            KeyboardView(firstOctave: firstOctave,
                         octaveCount: octaveCount,
                         showsLabels: showsLabels)
                .background(Self.bezelColor)
            // A bezel along the front edge, where a real keyboard has one. It
            // also keeps the keys out of the home indicator, so the swipe that
            // leaves the app doesn't sound a note on the way out.
            bezel
        }
        // The colour runs under the home indicator while the content stays
        // inside the safe area, so the front edge reads as one strip.
        .background(Self.bezelColor.ignoresSafeArea())
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
            Button("OK", role: .cancel) {}
        } message: {
            Text("An imported song is only its notes, with no recording behind it, so there's nothing to save as a melody. The file itself is still wherever you imported it from.")
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

    private var controlBar: some View {
        // 12 apart rather than 14: on a current iPhone the row had about 14
        // points to spare, and the octave range needed more than that.
        HStack(spacing: 12) {
            circleButton("minus", enabled: firstOctave > 0) {
                firstOctave -= 1
            }
            .accessibilityLabel("Octave down")

            rangeButton

            circleButton("plus", enabled: firstOctave < maxFirstOctave) {
                firstOctave += 1
            }
            .accessibilityLabel("Octave up")

            timeReadout

            Spacer(minLength: 0)

            circleButton("pedal.accelerator",
                         tint: conductor.isSustaining ? .green : .white,
                         enabled: conductor.isInstrumentLoaded) {
                conductor.setSustain(!conductor.isSustaining)
            }
            .accessibilityLabel(conductor.isSustaining ? "Sustain on" : "Sustain off")

            circleButton("arrow.counterclockwise", enabled: conductor.canPlay || conductor.isRecording) {
                // Sits right beside Record, so a slip is easy. Asking every
                // time would be a tax; asking only when a take would be lost
                // is not.
                if conductor.isRecording || conductor.hasUnsavedTake {
                    isConfirmingReset = true
                } else {
                    resetTake()
                }
            }
            .accessibilityLabel("Reset recording")

            circleButton(conductor.isRecording ? "stop.fill" : "record.circle",
                         tint: .red,
                         enabled: conductor.isInstrumentLoaded) {
                if !conductor.isRecording { elapsed = 0 }
                conductor.toggleRecording()
            }
            .accessibilityLabel(conductor.isRecording ? "Stop recording" : "Start recording")

            circleButton(conductor.isPlaying ? "pause.fill" : "play.fill",
                         enabled: conductor.canPlay && !conductor.isRecording) {
                conductor.togglePlayback()
            }
            .accessibilityLabel(conductor.isPlaying ? "Pause playback" : "Play recording")

            // Enabled for an import too, so a tap can say why it can't be saved
            // - a greyed-out button on a phone explains nothing, and there is
            // no hover to hang a tooltip on.
            circleButton("square.and.arrow.down",
                         enabled: (conductor.hasUnsavedTake || conductor.hasSequence) && !conductor.isRecording) {
                // An import on screen is what the player is looking at, so a
                // tap means "save this" - explain, rather than quietly saving
                // an earlier take they can't see.
                if conductor.hasSequence {
                    isExplainingImportSave = true
                } else {
                    takeName = RecordingStore.shared.suggestedName()
                    isNamingTake = true
                }
            }
            .accessibilityLabel("Save recording")

            circleButton("list.bullet", enabled: true) {
                showRecordings = true
            }
            .accessibilityLabel("Show saved melodies")

            circleButton("gearshape", enabled: true) {
                showSettings = true
            }
            .accessibilityLabel("Settings")
            .popover(isPresented: $showSettings) {
                SettingsView(showsLabels: $showsLabels)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.25, green: 0.27, blue: 0.30))
    }

    static let bezelColor = Color(white: 0.16)

    /// A front edge below the keys. Devices with a home indicator get most of
    /// this from the safe area; this is the minimum for those without one.
    private var bezel: some View {
        Rectangle()
            .fill(Self.bezelColor)
            .frame(height: 14)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1)
            }
    }

    private var timeReadout: some View {
        Text(saveConfirmation ?? format(elapsed))
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minWidth: 88)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.7), lineWidth: 2))
    }

    /// The notes on screen, between the buttons that move them - a stepper, read
    /// as one. Tapping it switches between one octave and as many as fit. It
    /// replaces an unlabelled switch that did the same thing without saying so,
    /// and it is the only place that says where on the keyboard you are once
    /// note names are off.
    private var rangeButton: some View {
        let low = PianoLayout.name(for: UInt8(clamping: baseMIDINote + firstOctave * 12))
        let high = PianoLayout.name(for: UInt8(clamping: baseMIDINote + (firstOctave + octaveCount) * 12))
        let canWiden = maxOctaves > 1
        return Button {
            hasChosenOctaveCount = true
            octaveCount = octaveCount > 1 ? 1 : maxOctaves
            clampOctave()
        } label: {
            Text("\(low)–\(high)")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Capsule().stroke(Color.white.opacity(canWiden ? 0.6 : 0.2), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!canWiden)
        .accessibilityLabel("Keyboard range")
        .accessibilityValue("\(low) to \(high)")
        .accessibilityHint(octaveCount > 1 ? "Shows one octave" : "Shows \(maxOctaves) octaves")
    }

    private func circleButton(_ symbol: String,
                              tint: Color = .white,
                              enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? tint : tint.opacity(0.3))
                .frame(width: 40, height: 40)
                .background(Circle().stroke(Color.white.opacity(enabled ? 0.6 : 0.2), lineWidth: 2))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
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
        octaveCount = min(max(1, octaveCount), maxOctaves)
        firstOctave = min(max(0, firstOctave), maxFirstOctave)
    }

    /// On a screen with room for it, start wide instead of on one octave.
    private func applyDefaultWidth() {
        guard !hasChosenOctaveCount else { return }
        if maxOctaves >= 3 { octaveCount = maxOctaves }
    }

    /// Moves the keyboard to where the imported melody is played, as widely as
    /// the screen allows, and starts it. Notes outside that still sound; they
    /// just have no key on screen to light.
    private func playImported() {
        guard let (score, name) = imported else { return }
        imported = nil
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
