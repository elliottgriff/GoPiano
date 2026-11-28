//
//  RecordingsView.swift
//  GoPiano
//
//  A landscape-shaped library: melodies down the left, the selected one on the
//  right. A single-column list in landscape wastes the width and squeezes every
//  row into a sliver, and the actions that matter here - replay and video -
//  deserve to be visible rather than buried behind an icon.
//

import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Something brought in from outside, waiting to be played on the keyboard.
enum ImportedMelody {
    /// Notes alone - a MIDI file - for the sampler to perform.
    case score(MelodyScore, name: String)
    /// A recording with the notes heard in it - a voice memo - played back in
    /// its own sound while the keys follow.
    case recording(Recording)
}

struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Conductor.self) private var conductor

    /// Handed an imported melody to perform on the keyboard once this sheet
    /// has gone, rather than playing it in here behind the library.
    let onImport: (ImportedMelody) -> Void

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
    /// Set while a voice memo is being listened to for its notes.
    @State private var isListening = false
    /// What the keyboard had loaded when the library opened. Auditioning a
    /// melody here borrows the player; closing hands the keyboard back what it
    /// had, unless a melody was sent to it.
    @State private var keyboardMelody: Conductor.KeyboardMelody?
    @State private var isExplainingVoiceMemos = false

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    ContentUnavailableView("No Melodies",
                                           systemImage: "waveform",
                                           description: Text("Record something, then tap Save to keep it - or import a voice memo or a MIDI file to watch it played."))
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
                    Menu("Import") {
                        Button {
                            isImporting = true
                        } label: {
                            Label("From Files…", systemImage: "folder")
                        }
                        Button {
                            isExplainingVoiceMemos = true
                        } label: {
                            Label("From Voice Memos…", systemImage: "waveform")
                        }
                    }
                    .disabled(isListening)
                    .accessibilityHint("Brings in voice memos or a MIDI file")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { close() }
                }
            }
        }
        // Follows the instrument it slides up over - dark on the black
        // piano, light on the ivory one - so it never looks like a second app.
        .pageSizedOnPad()
        .onAppear {
            conductor.stopPlayback()
            if keyboardMelody == nil { keyboardMelody = conductor.keyboardMelody }
            reload()
        }
        .onDisappear {
            guard !handedOff else { return }
            conductor.stopPlayback()
            if let keyboardMelody { conductor.restore(keyboardMelody) }
        }
        .overlay {
            if isListening { ListeningBadge() }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.audio, .midi],
                      onCompletion: importFile)
        // Voice Memos keeps its recordings to itself - no other app can list
        // them, and they aren't in Files - so the way in starts over there.
        .alert("Import from Voice Memos", isPresented: $isExplainingVoiceMemos) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("""
            Voice Memos doesn't let other apps see its recordings, so they can't be listed here. \
            Instead, in Voice Memos tap a recording, then ⋯ → Share → GoPiano. GoPiano finds the \
            melody and adds it to Melodies.
            """)
        }
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
        HStack(spacing: 10) {
            Button {
                togglePlay(recording)
            } label: {
                actionLabel(conductor.isPlaying ? "Stop" : "Play",
                            systemImage: conductor.isPlaying ? "stop.fill" : "play.fill",
                            showingLabels: showingLabels)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            // A sung melody plays on whichever instrument is chosen, or in
            // the voice that sang it: the same list as the control bar's.
            if RecordingStore.shared.score(for: recording)?.isSung == true {
                Menu {
                    InstrumentPicker()
                } label: {
                    let listening = conductor.isListening
                    actionLabel(listening ? "Voice" : conductor.instrument.name,
                                systemImage: listening ? "mic" : conductor.instrument.symbol,
                                showingLabels: showingLabels)
                }
                .buttonStyle(.bordered)
                .disabled(!conductor.isInstrumentLoaded)
                .accessibilityLabel("Play on")
            }
        }
    }

    /// Everything but Play: sharing, exports, and the rest.
    @ViewBuilder
    private func actions(for recording: Recording, showingLabels: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                openOnKeyboard(recording)
            } label: {
                actionLabel("Keyboard", systemImage: "arrow.down.forward.square",
                            showingLabels: showingLabels)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Play on the keyboard")

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
        }
    }

    /// Picking a melody only shows it; nothing is loaded until it's played,
    /// so looking through the list leaves the keyboard as it was.
    private func select(_ recording: Recording) {
        conductor.stopPlayback()
        selection = recording
    }

    private func togglePlay(_ recording: Recording) {
        guard !conductor.isPlaying else {
            conductor.togglePlayback()
            return
        }
        if selection != recording { select(recording) }
        do {
            try conductor.load(recording)
        } catch {
            errorMessage = "That melody could not be opened."
            return
        }
        conductor.togglePlayback()
    }

    /// Sends the melody to the keyboard - fitted to the keys and playing -
    /// the one way a melody here ends up loaded there.
    private func openOnKeyboard(_ recording: Recording) {
        hand(.recording(recording))
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

    private func importFile(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            guard VoiceMemoImport.isMIDI(url) else { return importMemo(url) }
            let score = try MIDIImport.score(from: url)
            hand(.score(score, name: url.deletingPathExtension().lastPathComponent))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Listens to a voice memo off the main thread - a few seconds for a
    /// long one - then plays it on the keyboard. It is in the library too, so
    /// it's there to come back to.
    private func importMemo(_ url: URL) {
        conductor.stopPlayback()
        isListening = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try VoiceMemoImport.importMemo(at: url) }
            await MainActor.run {
                isListening = false
                switch result {
                case .success(let recording):
                    hand(.recording(recording))
                case .failure(let error):
                    recordings = RecordingStore.shared.all()
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func hand(_ melody: ImportedMelody) {
        conductor.stopPlayback()
        handedOff = true
        onImport(melody)
        dismiss()
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
        if file.kind == .sheetMusic {
            SheetMusicViewer(url: file.url)
        } else {
            card
        }
    }

    private var card: some View {
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

/// The sheet music itself, every page, before it goes anywhere: read it
/// through, zoom in on a bar, then share or print it from here.
struct SheetMusicViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    private var name: String { url.deletingPathExtension().lastPathComponent }

    var body: some View {
        NavigationStack {
            PDFPages(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url, preview: SharePreview(name)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
        .presentationDetents([.large])
        .pageSizedOnPad()
    }
}

/// A PDF's pages one above the other, fitted to the width and pinch to zoom.
private struct PDFPages: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(url: url)
        view.autoScales = true
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
        // Fit the page to the width as the sheet settles or the device turns.
        view.minScaleFactor = view.scaleFactorForSizeToFit
        view.autoScales = true
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

/// Shown while a voice memo is listened to for its notes.
struct ListeningBadge: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Listening for the melody…")
                .font(.callout)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
