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
            .onChange(of: firstOctave) { conductor.allNotesOff() }
            .onChange(of: octaveCount) { conductor.allNotesOff() }
        }
    }

    private func handle(points: [CGPoint], layout: PianoLayout) {
        let notes = Set(points.compactMap { layout.note(at: $0) })
        for note in conductor.activeNotes.subtracting(notes) {
            conductor.noteOff(note)
        }
        for note in notes.subtracting(conductor.activeNotes) {
            conductor.noteOn(note)
        }
    }
}
