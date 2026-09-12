//
//  RecordingStore.swift
//  GoPiano
//
//  Saved takes live in Documents, so they survive relaunches.
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

final class RecordingStore {
    static let shared = RecordingStore()

    private let directory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func newFileURL(named name: String, pathExtension: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-")
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

    func all() -> [Recording] {
        let keys: [URLResourceKey] = [.creationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                 includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { !$0.hasDirectoryPath }
            .compactMap { url in
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let duration: TimeInterval
                if let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 {
                    duration = Double(file.length) / file.fileFormat.sampleRate
                } else {
                    duration = 0
                }
                return Recording(url: url, created: created, duration: duration)
            }
            .sorted { $0.created > $1.created }
    }

    func delete(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
    }

    func suggestedName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH.mm.ss"
        return "Take \(formatter.string(from: Date()))"
    }
}
