//
//  TouchTracker.swift
//  GoPiano
//
//  SwiftUI gestures track one finger at a time, which is no use for a piano.
//  This hands back every active touch location so chords and glissandi work.
//

import SwiftUI
import UIKit

struct TouchTracker: UIViewRepresentable {
    /// Called with the locations of all touches currently down.
    var onChange: ([CGPoint]) -> Void

    func makeUIView(context: Context) -> TouchTrackingView {
        let view = TouchTrackingView()
        view.onChange = onChange
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TouchTrackingView, context: Context) {
        uiView.onChange = onChange
    }
}

final class TouchTrackingView: UIView {
    var onChange: (([CGPoint]) -> Void)?

    private var active: [ObjectIdentifier: CGPoint] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        update(touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        remove(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        remove(touches)
    }

    private func update(_ touches: Set<UITouch>) {
        for touch in touches {
            active[ObjectIdentifier(touch)] = touch.location(in: self)
        }
        publish()
    }

    private func remove(_ touches: Set<UITouch>) {
        for touch in touches {
            active.removeValue(forKey: ObjectIdentifier(touch))
        }
        publish()
    }

    private func publish() {
        onChange?(Array(active.values))
    }
}
