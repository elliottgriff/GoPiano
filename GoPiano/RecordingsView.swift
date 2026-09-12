//
//  RecordingsView.swift
//  GoPiano
//

import SwiftUI

struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Conductor.self) private var conductor

    @State private var recordings: [Recording] = []
    @State private var renaming: Recording?
    @State private var newName = ""
    @State private var errorMessage: String?
    @State private var exporting: Recording?
    @State private var exportedVideo: URL?

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView("No Melodies",
                                           systemImage: "waveform",
                                           description: Text("Record something, then tap Save to keep it."))
                } else {
                    list
                }
            }
            .navigationTitle("Melodies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { reload() }
        .alert("Rename", isPresented: Binding(get: { renaming != nil },
                                              set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { commitRename() }
        }
        .alert("Something Went Wrong",
               isPresented: Binding(get: { errorMessage != nil },
                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $exportedVideo) { url in
            VideoShareSheet(url: url)
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(recordings) { recording in
                    row(for: recording)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Tap a melody to play it on the keyboard. Melodies are saved on this iPhone and also appear in the Files app, under GoPiano.")
            }
        }
    }

    private func row(for recording: Recording) -> some View {
        let playable = RecordingStore.shared.hasScore(for: recording)
        return HStack(spacing: 12) {
            Button {
                playOnKeyboard(recording)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "play.circle").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.name).lineLimit(1)
                        Text("\(recording.created.formatted(date: .abbreviated, time: .shortened)) · \(format(recording.duration))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(recording.name) on the keyboard")

            if exporting == recording {
                ProgressView()
            } else {
                Menu {
                    ShareLink(item: recording.url, preview: SharePreview(recording.name)) {
                        Label("Share Audio", systemImage: "waveform")
                    }
                    Button {
                        exportVideo(recording)
                    } label: {
                        Label("Share Video", systemImage: "film")
                    }
                    .disabled(!playable)
                    Button {
                        newName = recording.name
                        renaming = recording
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share or rename \(recording.name)")
            }
        }
        .disabled(exporting != nil)
    }

    // MARK: - Actions

    private func reload() {
        recordings = RecordingStore.shared.all()
    }

    /// Hands the melody to the conductor and gets out of the way, so it plays
    /// on the real keyboard with the keys lighting up.
    private func playOnKeyboard(_ recording: Recording) {
        do {
            try conductor.load(recording)
            dismiss()
            conductor.togglePlayback()
        } catch {
            errorMessage = "That melody could not be played."
        }
    }

    private func exportVideo(_ recording: Recording) {
        guard let score = RecordingStore.shared.score(for: recording) else {
            errorMessage = MelodyVideoError.noScore.localizedDescription
            return
        }
        exporting = recording
        Task {
            do {
                let url = try await MelodyVideoExporter().export(recording: recording, score: score)
                exporting = nil
                exportedVideo = url
            } catch {
                exporting = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            RecordingStore.shared.delete(recordings[index])
        }
        recordings.remove(atOffsets: offsets)
    }

    private func commitRename() {
        guard let recording = renaming else { return }
        renaming = nil
        do {
            try RecordingStore.shared.rename(recording, to: newName)
            reload()
        } catch {
            errorMessage = "That name could not be used."
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Lets a freshly rendered video be shared without first saving it anywhere
/// the user has to manage.
private struct VideoShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "film").font(.system(size: 48)).foregroundStyle(.secondary)
                Text("Your melody is ready to share.")
                    .multilineTextAlignment(.center)
                ShareLink(item: url, preview: SharePreview(url.deletingPathExtension().lastPathComponent)) {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
