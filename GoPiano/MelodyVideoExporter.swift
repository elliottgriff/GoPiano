//
//  MelodyVideoExporter.swift
//  GoPiano
//
//  Renders a melody as video: the keyboard drawn frame by frame from the score,
//  then muxed with the melody's own audio. Nothing is screen-captured, so the
//  result has no status bar, no fingers and no UI chrome - just the keys.
//

import AVFoundation
import CoreGraphics
import UIKit

enum MelodyVideoError: LocalizedError {
    case noScore
    case setupFailed
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noScore:
            "This melody was saved before GoPiano recorded which keys were played, so it can't be turned into a video."
        case .setupFailed:
            "The video could not be set up."
        case .exportFailed(let reason):
            reason
        }
    }
}

struct MelodyVideoExporter {
    var size = CGSize(width: 1280, height: 720)
    var framesPerSecond: Int32 = 30
    /// A moment of still keyboard at each end, so the video does not snap shut.
    var leadIn: TimeInterval = 0.3
    var tailOut: TimeInterval = 1.0

    func export(recording: Recording, score: MelodyScore) async throws -> URL {
        guard !score.isEmpty else { throw MelodyVideoError.noScore }

        let silentVideo = FileManager.default.temporaryDirectory
            .appendingPathComponent("melody-frames-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try await renderFrames(score: score, audioDuration: recording.duration, to: silentVideo)
        defer { try? FileManager.default.removeItem(at: silentVideo) }

        return try await mux(video: silentVideo, audio: recording.url, name: recording.name)
    }

    // MARK: - Frames

    private func renderFrames(score: MelodyScore,
                              audioDuration: TimeInterval,
                              to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                           sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw MelodyVideoError.setupFailed }
        writer.add(input)
        guard writer.startWriting() else {
            throw MelodyVideoError.exportFailed(writer.error?.localizedDescription ?? "Could not start writing.")
        }
        writer.startSession(atSourceTime: .zero)

        let framing = score.framing()
        let layout = PianoLayout(firstOctave: framing.firstOctave,
                                 octaveCount: framing.octaveCount,
                                 size: size)
        let total = max(score.duration, audioDuration) + tailOut
        let frameCount = max(1, Int((total + leadIn) * Double(framesPerSecond)))

        guard let pool = adaptor.pixelBufferPool else { throw MelodyVideoError.setupFailed }
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for frame in 0..<frameCount {
            await waitUntilReady(input)
            let time = Double(frame) / Double(framesPerSecond) - leadIn
            let pressed = score.notes(at: time)

            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                  let pixelBuffer = buffer else {
                throw MelodyVideoError.setupFailed
            }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let context = CGContext(
                data: CVPixelBufferGetBaseAddress(pixelBuffer),
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) {
                // Core Video buffers are bottom-up; flip so the renderer can
                // work in the same top-left space as the on-screen keyboard.
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                KeyboardRenderer.draw(layout: layout,
                                      pressed: pressed,
                                      showsLabels: true,
                                      fillsBackground: true,
                                      in: context)
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

            let presentation = CMTime(value: CMTimeValue(frame), timescale: framesPerSecond)
            adaptor.append(pixelBuffer, withPresentationTime: presentation)
        }

        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw MelodyVideoError.exportFailed(writer.error?.localizedDescription ?? "Writing failed.")
        }
    }

    private func waitUntilReady(_ input: AVAssetWriterInput) async {
        while !input.isReadyForMoreMediaData {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Muxing

    private func mux(video: URL, audio: URL, name: String) async throws -> URL {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideo = composition.addMutableTrack(withMediaType: .video,
                                                                 preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MelodyVideoError.setupFailed }

        let videoDuration = try await videoAsset.load(.duration)
        try compositionVideo.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                             of: videoTrack,
                                             at: .zero)

        if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudio = composition.addMutableTrack(withMediaType: .audio,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid) {
            let audioDuration = try await audioAsset.load(.duration)
            // The video carries a lead-in before the first note, so the audio
            // starts after it rather than at zero.
            let offset = CMTime(seconds: leadIn, preferredTimescale: 600)
            let usable = min(audioDuration, CMTimeSubtract(videoDuration, offset))
            if usable > .zero {
                try compositionAudio.insertTimeRange(CMTimeRange(start: .zero, duration: usable),
                                                     of: audioTrack,
                                                     at: offset)
            }
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFileName(name))
            .appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: output)

        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality)
        else { throw MelodyVideoError.setupFailed }

        if #available(iOS 18.0, *) {
            try await session.export(to: output, as: .mp4)
        } else {
            session.outputURL = output
            session.outputFileType = .mp4
            await session.export()
            if session.status == .failed {
                throw MelodyVideoError.exportFailed(session.error?.localizedDescription ?? "Export failed.")
            }
        }
        return output
    }

    private func safeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Melody" : cleaned
    }
}
