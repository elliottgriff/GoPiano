//
//  KeyboardRenderer.swift
//  GoPiano
//
//  One drawing routine for the keyboard, shared by the live view, the library
//  preview and the video exporter, so an exported melody looks like what was
//  played rather than drifting away from it.
//
//  Assumes a UIKit-style context: origin top-left, y increasing downwards.
//
//  The look is a real keyboard's, kept restrained: depth comes from proportion
//  - gaps between keys, the front lip of each white key, the felt strip, the
//  shadow under the black keys - rather than from gloss. Watching keys light
//  up is the point of a replay, so the held colour is always the strongest
//  thing on the keyboard and nothing decorative competes with it.
//
//  Every measurement is a fraction of the key or keyboard size, never a fixed
//  number of points. The video is drawn in pixels at a different scale, and it
//  has to come out looking the same.
//

import CoreGraphics
import UIKit

enum KeyboardRenderer {

    // MARK: - Palette

    /// What shows between and behind the keys.
    private static let keyBed = rgb(0.05, 0.04, 0.04)

    /// The case above the keys, where there is room for one: black lacquer,
    /// darkening down to where it meets the felt.
    private static let lacquer = gradient([(0, rgb(0.10, 0.10, 0.11)),
                                           (1, rgb(0.04, 0.04, 0.05))])
    /// The maker's name on the fallboard, the way a piano carries one just
    /// above the keys. Muted gold, never louder than the keys below it.
    private static let nameplate = UIColor(red: 0.78, green: 0.64, blue: 0.40, alpha: 0.7)

    /// The strip along the back of the keys. Pianos run a dark red felt here;
    /// it frames the keys and hides where they disappear into the action.
    private static let felt = gradient([(0, rgb(0.27, 0.03, 0.05)),
                                        (1, rgb(0.45, 0.07, 0.09))])
    /// The shadow the felt and fallboard throw across the backs of the keys.
    private static let feltShadow = gradient([(0, rgb(0, 0, 0, 0.32)),
                                              (1, rgb(0, 0, 0, 0))])

    /// Ivory rather than paper white, brightening towards the player.
    private static let ivory = gradient([(0.00, rgb(0.94, 0.93, 0.90)),
                                         (0.20, rgb(0.985, 0.98, 0.96)),
                                         (1.00, rgb(1.00, 0.995, 0.985))])
    /// The front face of a white key, seen from above and turned away from
    /// the light.
    private static let ivoryLip = gradient([(0, rgb(0.88, 0.87, 0.84)),
                                            (1, rgb(0.74, 0.73, 0.70))])

    private static let ebonyBody = gradient([(0, rgb(0.12, 0.12, 0.13)),
                                             (1, rgb(0.03, 0.03, 0.04))])
    private static let ebonyFace = gradient([(0, rgb(0.20, 0.20, 0.21)),
                                             (1, rgb(0.09, 0.09, 0.10))])

    /// Held keys take the colour of their note: once round the colour wheel per
    /// octave, C red, C sharp orange and on to B in rose. Every C is the same
    /// red in every octave, and notes a semitone apart are neighbouring hues,
    /// so the notes of a chord stay easy to tell apart. Black keys take deeper
    /// shades of theirs, so they still read as black keys. Saturated enough to
    /// stay the strongest thing on the keyboard.
    private struct HeldColours {
        let ivory, ivoryLip, ebonyBody, ebonyFace: CGGradient
    }

    private static let held: [HeldColours] = (0..<12).map { pitchClass in
        let hue = CGFloat(pitchClass) / 12
        return HeldColours(
            ivory: gradient([(0.00, hsb(hue, 0.72, 0.90)),
                             (0.20, hsb(hue, 0.64, 1.00)),
                             (1.00, hsb(hue, 0.54, 1.00))]),
            ivoryLip: gradient([(0, hsb(hue, 0.64, 0.88)),
                                (1, hsb(hue, 0.72, 0.72))]),
            ebonyBody: gradient([(0, hsb(hue, 0.80, 0.60)),
                                 (1, hsb(hue, 0.85, 0.40))]),
            ebonyFace: gradient([(0, hsb(hue, 0.70, 0.96)),
                                 (1, hsb(hue, 0.80, 0.78))]))
    }

    /// With note colours off, every held key takes the one red - C's.
    private static func heldColours(for note: UInt8, colourful: Bool) -> HeldColours {
        held[colourful ? Int(note) % 12 : 0]
    }

    /// Where the note-colours setting is kept. On unless turned off.
    static let coloursKey = "noteColours"
    static var coloursOn: Bool {
        UserDefaults.standard.object(forKey: coloursKey) as? Bool ?? true
    }

    /// A note's colour on its own, for anything that shows notes away from
    /// the keys - the score above them uses it, so a note looks the same on
    /// the staff as on the key that played it.
    static func noteColour(for note: UInt8) -> CGColor {
        hsb(CGFloat(Int(note) % 12) / 12, 0.6, 1.0)
    }

    /// A faint streak down each black key, the way light catches the lacquer.
    private static let sheen = gradient([(0.0, rgb(1, 1, 1, 0)),
                                         (0.3, rgb(1, 1, 1, 0.10)),
                                         (1.0, rgb(1, 1, 1, 0))])

    private static let label = UIColor(white: 0, alpha: 0.38)

    // MARK: - Drawing

    static func draw(layout: PianoLayout,
                     pressed: Set<UInt8>,
                     showsLabels: Bool,
                     colourful: Bool = true,
                     in context: CGContext) {
        let size = layout.size
        let whiteWidth = layout.whiteKeyWidth
        // Proportions follow the keys rather than the canvas, which can be
        // taller than the keys are (see PianoLayout.keyTop).
        let height = layout.keyLength
        let top = layout.keyTop
        guard whiteWidth > 0, height > 0 else { return }

        let gap = max(1, whiteWidth * 0.035)
        // Detail scales with a key's width, as on a real keyboard, so long
        // keys don't grow a heavy felt and front edge. Each is also held to a
        // share of the length, so short, wide keys stay in proportion too.
        let lip = min(whiteWidth * 0.27, height * 0.06)
        let feltHeight = max(2, min(whiteWidth * 0.21, height * 0.04))
        let hairline = max(0.5, whiteWidth * 0.018)

        context.setFillColor(keyBed)
        context.fill(CGRect(origin: .zero, size: size))

        if top > 0 {
            drawCase(above: top, width: size.width, keyLength: height, context: context)
        }

        // White keys.
        for key in layout.whiteKeys {
            let held = pressed.contains(key.note)
            let rect = key.frame.insetBy(dx: gap / 2, dy: 0)
            let body = bottomRounded(rect, radius: whiteWidth * 0.07)
            let colours = heldColours(for: key.note, colourful: colourful)
            fill(body, in: rect, with: held ? colours.ivory : ivory, context: context)

            // A held key has sunk: less of its front face shows.
            let lipHeight = held ? lip * 0.35 : lip
            let lipRect = CGRect(x: rect.minX, y: rect.maxY - lipHeight,
                                 width: rect.width, height: lipHeight)
            fill(body, in: lipRect, with: held ? colours.ivoryLip : ivoryLip, context: context)

            context.setFillColor(rgb(0, 0, 0, 0.10))
            context.fill(CGRect(x: rect.minX, y: lipRect.minY,
                                width: rect.width, height: hairline))

            // Labels stay put when a key is held. Following the shortened
            // lip down made a held key's name jump, which read as a glitch.
            if showsLabels {
                drawLabel(PianoLayout.name(for: key.note),
                          above: rect.maxY - lip - min(whiteWidth * 0.18, height * 0.03),
                          in: rect,
                          fontSize: min(15, whiteWidth * 0.30),
                          context: context)
            }
        }

        // The black keys' shadow falls across the white keys first, so every
        // black key sits on top of every shadow. Drawn as a few soft layers
        // rather than with a CG shadow, whose offset ignores the flipped
        // context the video draws into.
        // Cast towards the player and a touch to the right, not spread evenly
        // all round - an even spread reads as a grey halo, not a shadow.
        for key in layout.blackKeys {
            let width = key.frame.width
            let base = CGRect(x: key.frame.minX + width * 0.06,
                              y: key.frame.minY,
                              width: width,
                              height: key.frame.height + min(whiteWidth * 0.12, height * 0.02))
            context.setFillColor(rgb(0, 0, 0, 0.06))
            for step in 0..<3 {
                let spread = CGFloat(step) * width * 0.035
                let layer = CGRect(x: base.minX - spread * 0.5,
                                   y: base.minY,
                                   width: base.width + spread,
                                   height: base.height + spread * 1.5)
                context.addPath(bottomRounded(layer, radius: width * 0.15 + spread))
                context.fillPath()
            }
        }

        // Black keys: a body, a raised top face, and below it the slope down
        // towards the player, which a held key mostly hides.
        for key in layout.blackKeys {
            let held = pressed.contains(key.note)
            let frame = key.frame
            let width = frame.width

            let body = bottomRounded(frame, radius: width * 0.10)
            let colours = heldColours(for: key.note, colourful: colourful)
            fill(body, in: frame, with: held ? colours.ebonyBody : ebonyBody, context: context)

            let slope = frame.height * (held ? 0.05 : 0.10)
            let face = CGRect(x: frame.minX + width * 0.10,
                              y: frame.minY,
                              width: width * 0.80,
                              height: frame.height - slope)
            fill(bottomRounded(face, radius: width * 0.08), in: face,
                 with: held ? colours.ebonyFace : ebonyFace, context: context)

            let streak = CGRect(x: face.minX + face.width * 0.16,
                                y: face.minY,
                                width: max(1, width * 0.06),
                                height: face.height * 0.9)
            fill(CGPath(rect: streak, transform: nil), in: streak, with: sheen, context: context)

            context.setFillColor(rgb(1, 1, 1, held ? 0.20 : 0.12))
            context.fill(CGRect(x: face.minX, y: face.maxY - hairline,
                                width: face.width, height: hairline))
        }

        // Felt last, over the backs of every key, with its shadow beneath.
        let shadow = CGRect(x: 0, y: top + feltHeight, width: size.width,
                            height: min(whiteWidth * 0.36, height * 0.06))
        fill(CGPath(rect: shadow, transform: nil), in: shadow, with: feltShadow, context: context)
        let strip = CGRect(x: 0, y: top, width: size.width, height: feltHeight)
        fill(CGPath(rect: strip, transform: nil), in: strip, with: felt, context: context)
        context.setFillColor(rgb(0, 0, 0, 0.45))
        context.fill(CGRect(x: 0, y: top + feltHeight - hairline,
                            width: size.width, height: hairline))
    }

    /// The fallboard above the keys: lacquer, a catch of light along its
    /// lower edge, and the name just above the felt where a maker's would be.
    private static func drawCase(above top: CGFloat,
                                 width: CGFloat,
                                 keyLength: CGFloat,
                                 context: CGContext) {
        let panel = CGRect(x: 0, y: 0, width: width, height: top)
        fill(CGPath(rect: panel, transform: nil), in: panel, with: lacquer, context: context)
        context.setFillColor(rgb(1, 1, 1, 0.08))
        context.fill(CGRect(x: 0, y: top - max(1, keyLength * 0.004),
                            width: width, height: max(1, keyLength * 0.004)))

        let fontSize = min(max(width * 0.016, 11), 34)
        // Only where there is clearly room: squeezed against the felt it
        // would read as a label, not a nameplate.
        guard top > fontSize * 4 else { return }
        var font = UIFont.systemFont(ofSize: fontSize, weight: .medium)
        if let serif = font.fontDescriptor.withDesign(.serif) {
            font = UIFont(descriptor: serif, size: fontSize)
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let name = NSAttributedString(string: "GoPiano", attributes: [
            .font: font,
            .foregroundColor: nameplate,
            .kern: fontSize * 0.18,
            .paragraphStyle: style,
        ])
        let textHeight = name.size().height
        let target = CGRect(x: 0, y: top - textHeight - fontSize * 1.4,
                            width: width, height: textHeight)
        UIGraphicsPushContext(context)
        name.draw(in: target)
        UIGraphicsPopContext()
    }

    // MARK: - Helpers

    /// Fills `path`, clipped to `rect`, with a gradient running top to bottom
    /// across `rect`. Gradients follow the context's transform, so this draws
    /// the same in the flipped video context as on screen.
    private static func fill(_ path: CGPath,
                             in rect: CGRect,
                             with gradient: CGGradient,
                             context: CGContext) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.clip(to: rect)
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.midX, y: rect.minY),
                                   end: CGPoint(x: rect.midX, y: rect.maxY),
                                   options: [])
        context.restoreGState()
    }

    /// Rounded only at the bottom: keys disappear under the felt at the back.
    private static func bottomRounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        return UIBezierPath(roundedRect: rect,
                            byRoundingCorners: [.bottomLeft, .bottomRight],
                            cornerRadii: CGSize(width: radius, height: radius)).cgPath
    }

    private static func drawLabel(_ text: String,
                                  above baseline: CGFloat,
                                  in rect: CGRect,
                                  fontSize: CGFloat,
                                  context: CGContext) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: label,
            .paragraphStyle: style,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = string.size().height
        let target = CGRect(x: rect.minX, y: baseline - height,
                            width: rect.width, height: height)
        UIGraphicsPushContext(context)
        string.draw(in: target)
        UIGraphicsPopContext()
    }

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat,
                            _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
    }

    private static func hsb(_ hue: CGFloat, _ saturation: CGFloat,
                            _ brightness: CGFloat) -> CGColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return rgb(red, green, blue)
    }

    private static func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: colorSpace,
                   colors: stops.map(\.1) as CFArray,
                   locations: stops.map(\.0))!
    }
}
