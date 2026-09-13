//
//  RecordingStore.swift
//  GoPiano
//
//  Saved takes live in the app's Documents folder, so they survive relaunches,
//  show up in the Files app, and can be handed to the share sheet.
//

import AVFoundation
import Foundation

struct Recording: Identifiable, Hashable {
    let url: URL
    let created: Date
    let duration: TimeInterval

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum RecordingStoreError: LocalizedError {
    case noTake
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noTake: "There is nothing recorded to save."
        case .exportFailed: "The recording could not be converted."
        }
    }
}

final class RecordingStore {
    static let shared = RecordingStore()

    /// Takes are stored as AAC in an .m4a container. The recorder writes
    /// uncompressed float CAF, which runs to roughly 20 MB a minute and which
    /// plenty of apps refuse to open - no use for something meant to be shared.
    static let fileExtension = "m4a"

    let directory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Saving

    /// Converts the take at `source` into the library under `name`.
    @discardableResult
    func save(copying source: URL, named name: String) throws -> Recording {
        let destination = availableURL(for: name)
        try export(from: source, to: destination)
        let created = (try? destination.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
        return Recording(url: destination, created: created, duration: duration(of: destination))
    }

    private func export(from source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: input.fileFormat.sampleRate,
            AVNumberOfChannelsKey: min(2, Int(input.fileFormat.channelCount)),
            AVEncoderBitRateKey: 128_000,
        ]
        let output = try AVAudioFile(forWriting: destination, settings: settings)

        // AVAudioFile converts from the buffer's PCM format to the file's
        // encoded format on write, so no explicit converter is needed.
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat,
                                            frameCapacity: 8192) else {
            throw RecordingStoreError.exportFailed
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
    }

    // MARK: - Library

    func all() -> [Recording] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls
            .filter { !$0.hasDirectoryPath && !$0.lastPathComponent.hasPrefix(".") }
            .map { url in
                Recording(url: url,
                          created: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast,
                          duration: duration(of: url))
            }
            .sorted { $0.created > $1.created }
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
    }

    /// Renames a take, keeping its extension. Returns the moved recording.
    @discardableResult
    func rename(_ recording: Recording, to newName: String) throws -> Recording {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != recording.name else { return recording }
        let destination = availableURL(for: trimmed,
                                       pathExtension: recording.url.pathExtension)
        try FileManager.default.moveItem(at: recording.url, to: destination)
        return Recording(url: destination, created: recording.created, duration: recording.duration)
    }

    func suggestedName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d 'at' HH.mm"
        return "Take \(formatter.string(from: Date()))"
    }

    // MARK: - Helpers

    /// Strips characters that are awkward in a filename and avoids collisions.
    private func availableURL(for name: String,
                              pathExtension: String = RecordingStore.fileExtension) -> URL {
        var safe = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        if safe.isEmpty || safe.hasPrefix(".") { safe = "Take" }

        var candidate = directory.appendingPathComponent(safe).appendingPathExtension(pathExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(safe) \(counter)")
                .appendingPathExtension(pathExtension)
            counter += 1
        }
        return candidate
    }

    private func duration(of url: URL) -> TimeInterval {
        guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else {
            return 0
        }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
