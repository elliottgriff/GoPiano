//
//  KeyboardRenderer.swift
//  GoPiano
//
//  One drawing routine for the keyboard, shared by the live view and the video
//  exporter, so an exported melody looks like what was played rather than
//  drifting away from it.
//
//  Assumes a UIKit-style context: origin top-left, y increasing downwards.
//

import CoreGraphics
import UIKit

enum KeyboardRenderer {
    static let background = UIColor(white: 0.65, alpha: 1)
    static let whiteKey = UIColor.white
    static let whiteKeyPressed = UIColor(red: 1.0, green: 0.78, blue: 0.76, alpha: 1)
    static let blackKey = UIColor(white: 0.07, alpha: 1)
    static let blackKeyPressed = UIColor(white: 0.5, alpha: 1)
    static let keyBorder = UIColor(white: 0, alpha: 0.25)
    static let label = UIColor(white: 0, alpha: 0.45)

    static func draw(layout: PianoLayout,
                     pressed: Set<UInt8>,
                     showsLabels: Bool,
                     fillsBackground: Bool = false,
                     in context: CGContext) {
        if fillsBackground {
            context.setFillColor(background.cgColor)
            context.fill(CGRect(origin: .zero, size: layout.size))
        }

        for key in layout.whiteKeys {
            let rect = key.frame.insetBy(dx: 0.5, dy: 0)
            let path = roundedPath(rect, radius: 5)
            context.addPath(path)
            context.setFillColor((pressed.contains(key.note) ? whiteKeyPressed : whiteKey).cgColor)
            context.fillPath()

            context.addPath(path)
            context.setStrokeColor(keyBorder.cgColor)
            context.setLineWidth(1)
            context.strokePath()

            if showsLabels {
                drawLabel(PianoLayout.name(for: key.note),
                          in: rect,
                          fontSize: min(15, layout.whiteKeyWidth * 0.34),
                          context: context)
            }
        }

        for key in layout.blackKeys {
            context.addPath(roundedPath(key.frame, radius: 3))
            context.setFillColor((pressed.contains(key.note) ? blackKeyPressed : blackKey).cgColor)
            context.fillPath()
        }
    }

    /// Rounded only at the bottom, the way piano keys are drawn here.
    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        UIBezierPath(roundedRect: rect,
                     byRoundingCorners: [.bottomLeft, .bottomRight],
                     cornerRadii: CGSize(width: radius, height: radius)).cgPath
    }

    private static func drawLabel(_ text: String,
                                  in rect: CGRect,
                                  fontSize: CGFloat,
                                  context: CGContext) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .light),
            .foregroundColor: label,
            .paragraphStyle: style,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = string.size().height
        let target = CGRect(x: rect.minX,
                            y: rect.maxY - height - 10,
                            width: rect.width,
                            height: height)
        UIGraphicsPushContext(context)
        string.draw(in: target)
        UIGraphicsPopContext()
    }
}
