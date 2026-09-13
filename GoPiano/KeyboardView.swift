//
//  KeyboardView.swift
//  GoPiano
//

import SwiftUI

/// Draws a keyboard and nothing else. Shared by the playable keyboard and the
/// small preview in the melody library, so both look like the exported video.
struct KeyboardCanvas: View {
    let firstOctave: Int
    let octaveCount: Int
    let pressed: Set<UInt8>
    var showsLabels: Bool = true

    var body: some View {
        Canvas { context, size in
            let layout = PianoLayout(firstOctave: firstOctave,
                                     octaveCount: octaveCount,
                                     size: size)
            context.withCGContext { cgContext in
                KeyboardRenderer.draw(layout: layout,
                                      pressed: pressed,
                                      showsLabels: showsLabels,
                                      in: cgContext)
            }
        }
    }
}

/// The playable keyboard: the same drawing, plus touch handling.
struct KeyboardView: View {
    @Environment(Conductor.self) private var conductor

    let firstOctave: Int
    let octaveCount: Int
    var showsLabels: Bool = true

    var body: some View {
        GeometryReader { proxy in
            let layout = PianoLayout(firstOctave: firstOctave,
                                     octaveCount: octaveCount,
                                     size: proxy.size)
            ZStack {
                KeyboardCanvas(firstOctave: firstOctave,
                               octaveCount: octaveCount,
                               pressed: conductor.highlightedNotes,
                               showsLabels: showsLabels)
                TouchTracker { points in
                    handle(points: points, layout: layout)
                }
            }
            .accessibilityRepresentation {
                // The drawn keyboard is invisible to VoiceOver, so stand in a
                // row of buttons it can move through and play.
                HStack(spacing: 0) {
                    ForEach(layout.allKeys.sorted { $0.note < $1.note }) { key in
                        Button(PianoLayout.name(for: key.note)) {
                            conductor.tapNote(key.note)
                        }
                    }
                }
            }
            .onChange(of: firstOctave) { conductor.allNotesOff() }
            .onChange(of: octaveCount) { conductor.allNotesOff() }
        }
    }

    private func handle(points: [CGPoint], layout: PianoLayout) {
        var velocities: [UInt8: UInt8] = [:]
        for point in points {
            guard let key = layout.key(at: point) else { continue }
            velocities[key.note] = PianoLayout.velocity(for: point, on: key)
        }
        let notes = Set(velocities.keys)

        for note in conductor.activeNotes.subtracting(notes) {
            conductor.noteOff(note)
        }
        for note in notes.subtracting(conductor.activeNotes) {
            conductor.noteOn(note, velocity: velocities[note] ?? 100)
        }
    }
}
