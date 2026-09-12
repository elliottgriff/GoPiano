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
        let pressed = conductor.activeNotes

        for key in layout.whiteKeys {
            let rect = key.frame.insetBy(dx: 0.5, dy: 0)
            let path = Path(roundedRect: rect, cornerRadius: 5)
            context.fill(path, with: .color(pressed.contains(key.note)
                                            ? Color(red: 1.0, green: 0.78, blue: 0.76)
                                            : .white))
            context.stroke(path, with: .color(.black.opacity(0.25)), lineWidth: 1)

            if showsLabels {
                let label = Text(PianoLayout.name(for: key.note))
                    .font(.system(size: min(15, layout.whiteKeyWidth * 0.34), weight: .light))
                    .foregroundStyle(Color.black.opacity(0.45))
                context.draw(label, at: CGPoint(x: rect.midX, y: rect.maxY - 18))
            }
        }

        for key in layout.blackKeys {
            let path = Path(roundedRect: key.frame, cornerRadius: 3)
            context.fill(path, with: .color(pressed.contains(key.note)
                                            ? Color(white: 0.5)
                                            : Color(white: 0.07)))
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
