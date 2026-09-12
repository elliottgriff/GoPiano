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

    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    /// One octave can start anywhere; two need room for the second.
    private var maxFirstOctave: Int { octaveCount == 2 ? 5 : 6 }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            KeyboardView(firstOctave: firstOctave,
                         octaveCount: octaveCount,
                         showsLabels: showsLabels)
                .background(Color(white: 0.65))
        }
        .background(Color.black)
        .ignoresSafeArea(.all, edges: .bottom)
        .overlay(alignment: .top) { startupError }
        .sheet(isPresented: $showRecordings) { RecordingsView() }
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
                save()
            }
            .accessibilityLabel("Save recording")

            circleButton("list.bullet", enabled: true) {
                showRecordings = true
            }
            .accessibilityLabel("Show saved recordings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.25, green: 0.27, blue: 0.30))
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

    private func save() {
        let name = RecordingStore.shared.suggestedName()
        if conductor.saveRecording(named: name) != nil {
            flash("Saved")
        } else {
            flash("Save failed")
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
