//
//  KeyboardView.swift
//  GoPiano
//

import SwiftUI

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
                Canvas { context, _ in draw(layout: layout, in: &context) }
                TouchTracker { points in
                    handle(points: points, layout: layout)
                }
            }
            .onChange(of: firstOctave) { conductor.allNotesOff() }
            .onChange(of: octaveCount) { conductor.allNotesOff() }
        }
    }

    // MARK: - Drawing

    private func draw(layout: PianoLayout, in context: inout GraphicsContext) {
        // Hand off to the shared renderer so the live keyboard and an exported
        // video are drawn by the same code.
        let pressed = conductor.highlightedNotes
        context.withCGContext { cgContext in
            KeyboardRenderer.draw(layout: layout,
                                  pressed: pressed,
                                  showsLabels: showsLabels,
                                  in: cgContext)
        }
    }

    // MARK: - Touch handling

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
