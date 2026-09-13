//
//  RecordingsView.swift
//  GoPiano
//

import AVFoundation
import SwiftUI

struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recordings: [Recording] = []
    @State private var player: AVAudioPlayer?
    @State private var nowPlaying: Recording?
    @State private var renaming: Recording?
    @State private var newName = ""
    @State private var errorMessage: String?

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
                    Button("Done") { stop(); dismiss() }
                }
            }
        }
        .onAppear { reload() }
        .onDisappear { stop() }
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
    }

    private var list: some View {
        List {
            Section {
                ForEach(recordings) { recording in
                    row(for: recording)
                }
                .onDelete(perform: delete)
            } footer: {
                Text("Melodies are saved on this iPhone and also appear in the Files app, under GoPiano.")
            }
        }
    }

    private func row(for recording: Recording) -> some View {
        HStack(spacing: 12) {
            Button {
                play(recording)
            } label: {
                Image(systemName: nowPlaying == recording ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nowPlaying == recording ? "Stop" : "Play \(recording.name)")

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.name).lineLimit(1)
                Text("\(recording.created.formatted(date: .abbreviated, time: .shortened)) · \(format(recording.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            ShareLink(item: recording.url,
                      preview: SharePreview(recording.name)) {
                Image(systemName: "square.and.arrow.up").font(.body)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share \(recording.name)")
        }
        .swipeActions(edge: .leading) {
            Button {
                newName = recording.name
                renaming = recording
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.indigo)
        }
    }

    // MARK: - Actions

    private func reload() {
        recordings = RecordingStore.shared.all()
    }

    private func play(_ recording: Recording) {
        if nowPlaying == recording { stop(); return }
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: recording.url)
            player.play()
            self.player = player
            nowPlaying = recording
        } catch {
            errorMessage = "That melody could not be played."
        }
    }

    private func stop() {
        player?.stop()
        player = nil
        nowPlaying = nil
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            if recordings[index] == nowPlaying { stop() }
            RecordingStore.shared.delete(recordings[index])
        }
        recordings.remove(atOffsets: offsets)
    }

    private func commitRename() {
        guard let recording = renaming else { return }
        renaming = nil
        do {
            try RecordingStore.shared.rename(recording, to: newName)
            if nowPlaying == recording { stop() }
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
