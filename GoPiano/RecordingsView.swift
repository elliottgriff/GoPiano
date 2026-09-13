//
//  RecordingsView.swift
//  GoPiano
//
//  A landscape-shaped library: melodies down the left, the selected one on the
//  right. A single-column list in landscape wastes the width and squeezes every
//  row into a sliver, and the actions that matter here - replay and video -
//  deserve to be visible rather than buried behind an icon.
//

import SwiftUI

struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Conductor.self) private var conductor

    @State private var recordings: [Recording] = []
    @State private var selection: Recording?
    @State private var renaming: Recording?
    @State private var newName = ""
    @State private var errorMessage: String?
    @State private var exportingVideo = false
    @State private var exportedVideo: URL?

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView("No Melodies",
                                           systemImage: "waveform",
                                           description: Text("Record something, then tap Save to keep it."))
                } else {
                    HStack(spacing: 0) {
                        list
                            .frame(maxWidth: 300)
                        Divider()
                        detail
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Melodies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                }
            }
        }
        .onAppear(perform: reload)
        .onDisappear { conductor.stopPlayback() }
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
        .sheet(item: $exportedVideo) { VideoShareSheet(url: $0) }
    }

    // MARK: - List

    private var list: some View {
        List(selection: $selection) {
            ForEach(recordings) { recording in
                Button {
                    select(recording)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selection == recording ? "music.note.list" : "waveform")
                            .foregroundStyle(selection == recording ? Color.accentColor : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recording.name).lineLimit(1)
                            Text(format(recording.duration))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .tint(.primary)
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let recording = selection {
            VStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(recording.name).font(.headline).lineLimit(1)
                    Text("\(recording.created.formatted(date: .abbreviated, time: .shortened)) · \(format(recording.duration))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                preview(for: recording)

                HStack(spacing: 10) {
                    Button {
                        togglePlay(recording)
                    } label: {
                        Label(conductor.isPlaying ? "Stop" : "Play",
                              systemImage: conductor.isPlaying ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    ShareLink(item: recording.url, preview: SharePreview(recording.name)) {
                        Label("Audio", systemImage: "waveform")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        exportVideo(recording)
                    } label: {
                        if exportingVideo {
                            ProgressView()
                        } else {
                            Label("Video", systemImage: "film")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!RecordingStore.shared.hasScore(for: recording) || exportingVideo)

                    Menu {
                        Button {
                            newName = recording.name
                            renaming = recording
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
                .disabled(exportingVideo)
            }
            .padding()
        } else {
            ContentUnavailableView("Pick a Melody",
                                   systemImage: "hand.tap",
                                   description: Text("Choose one on the left to play it back and watch the keys."))
        }
    }

    /// The keys light up here exactly as they do in an exported video, because
    /// both go through the same renderer.
    @ViewBuilder
    private func preview(for recording: Recording) -> some View {
        let score = RecordingStore.shared.score(for: recording)
        if let score, !score.isEmpty {
            let framing = score.framing()
            KeyboardCanvas(firstOctave: framing.firstOctave,
                           octaveCount: framing.octaveCount,
                           pressed: conductor.replayNotes,
                           showsLabels: false)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .background(Color(white: 0.65))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Text("Saved before GoPiano recorded which keys were played, so there are no keys to show and no video to export.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 96)
        }
    }

    // MARK: - Actions

    private func reload() {
        recordings = RecordingStore.shared.all()
        if selection == nil || !recordings.contains(where: { $0 == selection }) {
            selection = recordings.first
            if let first = selection { try? conductor.load(first) }
        }
    }

    private func select(_ recording: Recording) {
        conductor.stopPlayback()
        selection = recording
        do {
            try conductor.load(recording)
        } catch {
            errorMessage = "That melody could not be opened."
        }
    }

    private func togglePlay(_ recording: Recording) {
        if !conductor.isPlaying, selection != recording { select(recording) }
        conductor.togglePlayback()
    }

    private func exportVideo(_ recording: Recording) {
        guard let score = RecordingStore.shared.score(for: recording) else {
            errorMessage = MelodyVideoError.noScore.localizedDescription
            return
        }
        conductor.stopPlayback()
        exportingVideo = true
        Task {
            do {
                exportedVideo = try await MelodyVideoExporter().export(recording: recording, score: score)
            } catch {
                errorMessage = error.localizedDescription
            }
            exportingVideo = false
        }
    }

    private func delete(at offsets: IndexSet) {
        let going = offsets.map { recordings[$0] }
        if going.contains(where: { $0 == selection }) { conductor.stopPlayback() }
        going.forEach(RecordingStore.shared.delete)
        recordings.remove(atOffsets: offsets)
        if let selection, !recordings.contains(selection) { self.selection = recordings.first }
    }

    private func deleteSelected() {
        guard let recording = selection,
              let index = recordings.firstIndex(of: recording) else { return }
        delete(at: IndexSet(integer: index))
    }

    private func commitRename() {
        guard let recording = renaming else { return }
        renaming = nil
        do {
            let renamed = try RecordingStore.shared.rename(recording, to: newName)
            conductor.stopPlayback()
            recordings = RecordingStore.shared.all()
            selection = recordings.first { $0.url == renamed.url } ?? recordings.first
        } catch {
            errorMessage = "That name could not be used."
        }
    }

    private func close() {
        conductor.stopPlayback()
        dismiss()
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
                Image(systemName: "film").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Your melody is ready to share.")
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
