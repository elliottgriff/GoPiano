//
//  ContentView.swift
//  GoPiano
//

import SwiftUI

struct ContentView: View {
    @Environment(Conductor.self) private var conductor
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("firstOctave") private var firstOctave = 3
    @AppStorage("octaveCount") private var octaveCount = 1
    @AppStorage("showsLabels") private var showsLabels = true

    @State private var elapsed: TimeInterval = 0
    @State private var showRecordings = false
    @State private var saveConfirmation: String?
    @State private var isNamingTake = false
    @State private var takeName = ""
    @State private var saveError: String?
    @State private var showSettings = false

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    /// Stop short of the two octaves above the sampled range, which were just
    /// the topmost sample stretched upwards and sounded thin for it.
    private var maxFirstOctave: Int {
        let highestOctave = (SampleMap.highestSampledNote - baseMIDINote - 11) / 12
        return max(0, highestOctave - (octaveCount - 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            KeyboardView(firstOctave: firstOctave,
                         octaveCount: octaveCount,
                         showsLabels: showsLabels)
                .background(Color(white: 0.65))
            // A bezel along the front edge, where a real keyboard has one. It
            // also keeps the keys out of the home indicator, so the swipe that
            // leaves the app doesn't sound a note on the way out.
            bezel
        }
        // The colour runs under the home indicator while the content stays
        // inside the safe area, so the front edge reads as one strip.
        .background(Self.bezelColor.ignoresSafeArea())
        .overlay(alignment: .top) { startupError }
        .sheet(isPresented: $showRecordings) { RecordingsView() }
        .alert("Save Melody", isPresented: $isNamingTake) {
            TextField("Name", text: $takeName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { save(as: takeName) }
        } message: {
            Text("Saved melodies appear in the Files app and can be shared.")
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
            clampOctave()
        }
        .onReceive(tick) { _ in
            if conductor.isRecording { elapsed += 0.05 }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { conductor.allNotesOff() }
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: 14) {
            Toggle("", isOn: Binding(
                get: { octaveCount == 2 },
                set: { octaveCount = $0 ? 2 : 1; clampOctave() }
            ))
            .labelsHidden()
            .accessibilityLabel(octaveCount == 2 ? "Show one octave" : "Show two octaves")

            circleButton("minus", enabled: firstOctave > 0) {
                firstOctave -= 1
            }
            .accessibilityLabel("Octave down")

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

            circleButton("arrow.counterclockwise", enabled: conductor.hasRecording || conductor.isRecording) {
                conductor.reset()
                elapsed = 0
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
                         enabled: conductor.hasRecording && !conductor.isRecording) {
                conductor.togglePlayback()
            }
            .accessibilityLabel(conductor.isPlaying ? "Pause playback" : "Play recording")

            circleButton("square.and.arrow.down", enabled: conductor.hasRecording && !conductor.isRecording) {
                takeName = RecordingStore.shared.suggestedName()
                isNamingTake = true
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
            .frame(minWidth: 104)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.7), lineWidth: 2))
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
        firstOctave = min(max(0, firstOctave), maxFirstOctave)
    }

    private func save(as name: String) {
        do {
            _ = try conductor.saveRecording(named: name)
            flash("Saved")
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func flash(_ message: String) {
        saveConfirmation = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            saveConfirmation = nil
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let hundredths = Int((seconds * 100).rounded())
        return String(format: "%02d:%02d:%02d",
                      hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }
}
