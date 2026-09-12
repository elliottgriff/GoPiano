//
//  TouchTracker.swift
//  GoPiano
//
//  SwiftUI gestures track one finger at a time, which is no use for a piano,
//  so touches are tracked directly and every active location handed back.
//
//  This is a gesture recognizer rather than a UIView's own touch methods on
//  purpose: raw view touches get cancelled out from under us when an ancestor
//  recognizer claims the sequence, which silently cut the first note of every
//  take short. A recognizer that claims the touch itself keeps receiving it.
//

import SwiftUI
import UIKit

struct TouchTracker: UIViewRepresentable {
    /// Called with the locations of all touches currently down.
    var onChange: ([CGPoint]) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let recognizer = MultiTouchRecognizer(target: nil, action: nil)
        recognizer.onChange = onChange
        recognizer.delegate = context.coordinator
        // Let everything else carry on; we only want to observe.
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        view.addGestureRecognizer(recognizer)
        context.coordinator.recognizer = recognizer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.recognizer?.onChange = onChange
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var recognizer: MultiTouchRecognizer?

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

final class MultiTouchRecognizer: UIGestureRecognizer {
    var onChange: (([CGPoint]) -> Void)?

    private var active: [ObjectIdentifier: UITouch] = [:]

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches { active[ObjectIdentifier(touch)] = touch }
        // Claiming the sequence immediately is what stops it being cancelled.
        state = .began
        publish()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
        publish()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func reset() {
        super.reset()
        active.removeAll()
        publish()
    }

    private func finish(_ touches: Set<UITouch>) {
        for touch in touches { active.removeValue(forKey: ObjectIdentifier(touch)) }
        publish()
        if active.isEmpty { state = .ended }
    }

    private func publish() {
        guard let view else { return }
        onChange?(active.values.map { $0.location(in: view) })
    }
}
