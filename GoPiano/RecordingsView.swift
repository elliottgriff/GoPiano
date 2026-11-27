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
import UniformTypeIdentifiers

struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Conductor.self) private var conductor

    /// Handed an imported melody to perform on the keyboard once this sheet
    /// has gone, rather than playing it in here behind the library.
    let onImport: (MelodyScore, _ name: String) -> Void

    @State private var recordings: [Recording] = []
    @State private var selection: Recording?
    @State private var renaming: Recording?
    @State private var newName = ""
    @State private var errorMessage: String?
    @State private var exportingVideo = false
    @State private var exported: ExportedFile?
    @State private var isImporting = false
    /// Set once an imported melody has been handed to the keyboard, so going
    /// away does not stop the performance it is about to start.
    @State private var handedOff = false

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView("No Melodies",
                                           systemImage: "waveform",
                                           description: Text("Record something, then tap Save to keep it - or import a MIDI file to watch it played."))
                } else {
                    HStack(spacing: 0) {
                        list
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 280)
                        Divider()
                        detail
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Melodies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Import") { isImporting = true }
                        .accessibilityHint("Opens a MIDI file to play on the keyboard")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                }
            }
        }
        // Dark, like the instrument it slides up over. A bright standard sheet
        // made it look like a second app.
        .preferredColorScheme(.dark)
        .pageSizedOnPad()
        .onAppear(perform: reload)
        .onDisappear { if !handedOff { conductor.stopPlayback() } }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.midi],
                      onCompletion: importMIDI)
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
        .sheet(item: $exported) { ExportShareSheet(file: $0) }
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

                // Labels never wrap; if the pane is too narrow for words the
                // whole row falls back to icons rather than stacking letters.
                // Narrower still, Play takes a row of its own above the rest,
                // so nothing is ever pushed off the edge of the pane.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        playButton(for: recording, showingLabels: true)
                        actions(for: recording, showingLabels: true)
                    }
                    HStack(spacing: 10) {
                        playButton(for: recording, showingLabels: true)
                        actions(for: recording, showingLabels: false)
                    }
                    VStack(spacing: 10) {
                        playButton(for: recording, showingLabels: true)
                        actions(for: recording, showingLabels: false)
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

    private func playButton(for recording: Recording, showingLabels: Bool) -> some View {
        Button {
            togglePlay(recording)
        } label: {
            actionLabel(conductor.isPlaying ? "Stop" : "Play",
                        systemImage: conductor.isPlaying ? "stop.fill" : "play.fill",
                        showingLabels: showingLabels)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }

    /// Everything but Play: sharing, exports, and the rest.
    @ViewBuilder
    private func actions(for recording: Recording, showingLabels: Bool) -> some View {
        HStack(spacing: 10) {
            ShareLink(item: recording.url, preview: SharePreview(recording.name)) {
                actionLabel("Share", systemImage: "square.and.arrow.up",
                            showingLabels: showingLabels)
            }
            .buttonStyle(.bordered)

            Button {
                exportVideo(recording)
            } label: {
                if exportingVideo {
                    ProgressView()
                } else {
                    actionLabel("Video", systemImage: "film", showingLabels: showingLabels)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!hasScore(recording) || exportingVideo)

            Button {
                exportMIDI(recording)
            } label: {
                actionLabel("MIDI", systemImage: "pianokeys", showingLabels: showingLabels)
            }
            .buttonStyle(.bordered)
            .disabled(!hasScore(recording))

            Button {
                exportSheetMusic(recording)
            } label: {
                actionLabel("Sheet Music", systemImage: "music.quarternote.3",
                            showingLabels: showingLabels)
            }
            .buttonStyle(.bordered)
            .disabled(!hasScore(recording))

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
                Image(systemName: "ellipsis")
                    .frame(minWidth: 20)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("More actions")
        }
        .disabled(exportingVideo)
    }

    private func hasScore(_ recording: Recording) -> Bool {
        RecordingStore.shared.hasScore(for: recording)
    }

    @ViewBuilder
    private func actionLabel(_ title: String, systemImage: String,
                             showingLabels: Bool) -> some View {
        if showingLabels {
            Label(title, systemImage: systemImage)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Image(systemName: systemImage)
                .frame(minWidth: 20)
                .accessibilityLabel(title)
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
                let url = try await MelodyVideoExporter().export(recording: recording, score: score)
                exported = ExportedFile(url: url, kind: .video)
            } catch {
                errorMessage = error.localizedDescription
            }
            exportingVideo = false
        }
    }

    /// Writing a MIDI file is a few hundred bytes of arithmetic, so unlike the
    /// video export it needs no progress of its own.
    private func exportMIDI(_ recording: Recording) {
        guard let score = RecordingStore.shared.score(for: recording), !score.isEmpty else {
            errorMessage = MIDIExportError.noScore.localizedDescription
            return
        }
        conductor.stopPlayback()
        do {
            exported = ExportedFile(url: try MIDIFile.write(score, named: recording.name),
                                    kind: .midi)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The melody written out as sheet music, the way the page above the keys
    /// showed it, as a PDF to print or send.
    private func exportSheetMusic(_ recording: Recording) {
        guard let score = RecordingStore.shared.score(for: recording), !score.isEmpty else {
            errorMessage = SheetMusicError.noNotes.localizedDescription
            return
        }
        conductor.stopPlayback()
        do {
            let played = recording.created.formatted(date: .long, time: .omitted)
            exported = ExportedFile(url: try SheetMusicPDF.write(score,
                                                                 named: recording.name,
                                                                 subtitle: "Played \(played)",
                                                                 length: recording.duration),
                                    kind: .sheetMusic)
        } catch {
            errorMessage = error.localizedDescription
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

    private func importMIDI(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let score = try MIDIImport.score(from: url)
            conductor.stopPlayback()
            handedOff = true
            onImport(score, url.deletingPathExtension().lastPathComponent)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A freshly made file, held only long enough to be shared.
struct ExportedFile: Identifiable {
    enum Kind {
        case video
        case midi
        case sheetMusic
    }

    let url: URL
    let kind: Kind

    var id: URL { url }
}

/// Lets a freshly made export be shared without first saving it anywhere the
/// user has to manage.
struct ExportShareSheet: View {
    let file: ExportedFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
                Text(message)
                    .multilineTextAlignment(.center)
                ShareLink(item: file.url,
                          preview: SharePreview(file.url.deletingPathExtension().lastPathComponent)) {
                    Label("Share \(title)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var title: String {
        switch file.kind {
        case .video: "Video"
        case .midi: "MIDI"
        case .sheetMusic: "Sheet Music"
        }
    }

    private var icon: String {
        switch file.kind {
        case .video: "film"
        case .midi: "pianokeys"
        case .sheetMusic: "music.quarternote.3"
        }
    }

    private var message: String {
        switch file.kind {
        case .video:
            "Your melody is ready to share."
        case .midi:
            "Your melody as editable notes. Open it in a DAW, or send it to yourself to work on later."
        case .sheetMusic:
            "Your melody written out as sheet music, ready to print or send."
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private extension View {
    /// On iPad the standard form sheet is too narrow for the list beside a
    /// melody's keys and actions; a page-sized sheet gives the detail room.
    @ViewBuilder
    func pageSizedOnPad() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}
