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

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView("No Recordings",
                                           systemImage: "waveform",
                                           description: Text("Record a take, then tap Save to keep it."))
                } else {
                    List {
                        ForEach(recordings) { recording in
                            Button {
                                play(recording)
                            } label: {
                                HStack {
                                    Image(systemName: nowPlaying == recording
                                          ? "stop.circle.fill" : "play.circle")
                                        .font(.title2)
                                    VStack(alignment: .leading) {
                                        Text(recording.name)
                                        Text(recording.created, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(format(recording.duration))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { stop(); dismiss() }
                }
            }
        }
        .onAppear { recordings = RecordingStore.shared.all() }
        .onDisappear { stop() }
    }

    private func play(_ recording: Recording) {
        if nowPlaying == recording { stop(); return }
        stop()
        player = try? AVAudioPlayer(contentsOf: recording.url)
        player?.play()
        nowPlaying = recording
    }

    private func stop() {
        player?.stop()
        player = nil
        nowPlaying = nil
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            RecordingStore.shared.delete(recordings[index])
        }
        recordings.remove(atOffsets: offsets)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
