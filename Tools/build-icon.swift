// Draws GoPiano's app icon, 1024 x 1024 with no alpha, in three appearances:
// the usual one, Dark and Tinted.
//
// Five keys - F to C, so the three black keys read at a glance - under the
// red felt and the black lacquer of the case, as the app draws them. A, in the
// middle, is lit in its note colour, and above it on the lacquer is the note
// itself, joined to its key by a beam of the same colour: what you play or
// sing lights up and is written down. Colours and key proportions are the
// app's own (KeyboardRenderer). Square and full-bleed: iOS rounds the corners.
//
// Usage: swift Tools/build-icon.swift GoPiano/Assets.xcassets/AppIcon.appiconset \
//            GoPiano/Assets.xcassets/Logo.imageset
//
// The second folder, if given, gets Logo.png: the icon at 256 px, which the
// sheet music PDF prints beside "Made with GoPiano" at the foot of each page.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
let S: CGFloat = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

enum Look { case light, dark, tinted }

func draw(_ look: Look) -> CGImage {
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [r, g, b, a])!
    }
    func hsb(_ h: CGFloat, _ s: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        let c = NSColor(hue: h, saturation: s, brightness: b, alpha: a).usingColorSpace(.sRGB)!
        return rgb(c.redComponent, c.greenComponent, c.blueComponent, a)
    }
    func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
        CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
    }

    let context = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.translateBy(x: 0, y: S)
    context.scaleBy(x: 1, y: -1)

    func fillVertical(_ rect: CGRect, _ g: CGGradient, clip: CGPath? = nil) {
        context.saveGState()
        context.addPath(clip ?? CGPath(rect: rect, transform: nil))
        context.clip()
        context.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.minY),
                                   end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        context.restoreGState()
    }
    func bottomRounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: radius)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: radius)
        p.closeSubpath()
        return p
    }

    // A, as on the keys and the staff: hue by pitch class, 9 of 12.
    let hue: CGFloat = 9.0 / 12
    // In Dark, the ivory dims so the icon doesn't glare on a dark home
    // screen; the lit key and its note keep their colour.
    // In Tinted, where the system colours the icon by brightness alone, the
    // other keys dim and the lit key and its note go nearly white, so they
    // stay the brightest things in it.
    let ivoryScale: CGFloat = look == .dark ? 0.62 : (look == .tinted ? 0.5 : 1)
    func accent(_ saturation: CGFloat, _ brightness: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        look == .tinted ? hsb(hue, saturation * 0.12, min(1, brightness + 0.1), alpha)
                        : hsb(hue, saturation, brightness, alpha)
    }

    // The case.
    fillVertical(CGRect(x: 0, y: 0, width: S, height: S),
                 gradient([(0, rgb(0.13, 0.13, 0.14)), (1, rgb(0.04, 0.04, 0.05))]))

    // Keys.
    let keyTop: CGFloat = 512
    let whiteWidth = S / 5
    let keyLength = S - keyTop + 40          // runs off the bottom
    let gap = whiteWidth * 0.035
    let lip = whiteWidth * 0.27
    let hairline = whiteWidth * 0.018
    func ivoryStop(_ v: CGFloat) -> CGColor { rgb(v * ivoryScale, v * ivoryScale * 0.995, v * ivoryScale * 0.975) }
    let ivory = gradient([(0.00, ivoryStop(0.94)), (0.20, ivoryStop(0.985)), (1.00, ivoryStop(1.0))])
    let ivoryLip = gradient([(0, ivoryStop(0.88)), (1, ivoryStop(0.74))])
    let held = gradient([(0.00, accent(0.72, 0.90)), (0.20, accent(0.64, 1.00)), (1.00, accent(0.54, 1.00))])
    let heldLip = gradient([(0, accent(0.64, 0.88)), (1, accent(0.72, 0.72))])

    context.setFillColor(rgb(0.05, 0.04, 0.04))
    context.fill(CGRect(x: 0, y: keyTop, width: S, height: S - keyTop))
    var litRect = CGRect.zero
    for index in 0..<5 {                     // F G A B C
        let rect = CGRect(x: CGFloat(index) * whiteWidth, y: keyTop, width: whiteWidth, height: keyLength)
            .insetBy(dx: gap / 2, dy: 0)
        let lit = index == 2
        if lit { litRect = rect }
        let body = bottomRounded(rect, whiteWidth * 0.07)
        fillVertical(rect, lit ? held : ivory, clip: body)
        let lipHeight = lit ? lip * 0.35 : lip
        let lipRect = CGRect(x: rect.minX, y: rect.maxY - lipHeight, width: rect.width, height: lipHeight)
        fillVertical(lipRect, lit ? heldLip : ivoryLip, clip: body)
    }

    // F#, G#, A#: on the boundaries after F, G and A.
    let blackWidth = whiteWidth * 0.62
    let blackHeight = (S - keyTop) * 0.58
    let ebonyBody = gradient([(0, rgb(0.12, 0.12, 0.13)), (1, rgb(0.03, 0.03, 0.04))])
    let ebonyFace = gradient([(0, rgb(0.22, 0.22, 0.23)), (1, rgb(0.09, 0.09, 0.10))])
    let sheen = gradient([(0.0, rgb(1, 1, 1, 0)), (0.3, rgb(1, 1, 1, 0.10)), (1.0, rgb(1, 1, 1, 0))])
    let blacks = (1...3).map { CGRect(x: CGFloat($0) * whiteWidth - blackWidth / 2, y: keyTop,
                                      width: blackWidth, height: blackHeight) }
    for frame in blacks {
        context.setFillColor(rgb(0, 0, 0, 0.07))
        for step in 0..<3 {
            let spread = CGFloat(step) * blackWidth * 0.04
            let layer = CGRect(x: frame.minX + blackWidth * 0.06 - spread * 0.5, y: frame.minY,
                               width: frame.width + spread, height: frame.height + whiteWidth * 0.10 + spread * 1.5)
            context.addPath(bottomRounded(layer, blackWidth * 0.15 + spread))
            context.fillPath()
        }
    }
    for frame in blacks {
        fillVertical(frame, ebonyBody, clip: bottomRounded(frame, blackWidth * 0.10))
        let face = CGRect(x: frame.minX + blackWidth * 0.10, y: frame.minY,
                          width: blackWidth * 0.80, height: frame.height * 0.90)
        fillVertical(face, ebonyFace, clip: bottomRounded(face, blackWidth * 0.08))
        fillVertical(CGRect(x: face.minX + face.width * 0.16, y: face.minY,
                            width: blackWidth * 0.07, height: face.height * 0.9), sheen)
        context.setFillColor(rgb(1, 1, 1, 0.12))
        context.fill(CGRect(x: face.minX, y: face.maxY - hairline * 2, width: face.width, height: hairline * 2))
    }

    // The felt, and its shadow on the keys.
    let feltHeight: CGFloat = 40
    fillVertical(CGRect(x: 0, y: keyTop + feltHeight, width: S, height: 70),
                 gradient([(0, rgb(0, 0, 0, 0.32)), (1, rgb(0, 0, 0, 0))]))
    fillVertical(CGRect(x: 0, y: keyTop, width: S, height: feltHeight),
                 gradient([(0, rgb(0.30, 0.03, 0.05)), (1, rgb(0.50, 0.08, 0.10))]))
    context.setFillColor(rgb(0, 0, 0, 0.45))
    context.fill(CGRect(x: 0, y: keyTop + feltHeight - 3, width: S, height: 3))

    // The note, written above its key.
    let head = CGPoint(x: S / 2 - 18, y: 318)
    let headSize = CGSize(width: 176, height: 124)

    // The beam from note to key, soft-edged, and a glow at each end.
    let beamTop = head.y
    for layer in 0..<24 {
        let width = litRect.width * (1.5 - CGFloat(layer) * 0.058)
        let beam = CGRect(x: S / 2 - width / 2, y: beamTop, width: width, height: keyTop - beamTop)
        fillVertical(beam, gradient([(0.0, accent(0.6, 1, 0)), (0.5, accent(0.6, 1, 0.014)),
                                     (1.0, accent(0.6, 1, 0.03))]))
    }
    for (point, radius, alpha) in [(head, CGFloat(250), CGFloat(0.42)),
                                   (CGPoint(x: S / 2, y: keyTop + 20), CGFloat(230), CGFloat(0.30))] {
        let glow = gradient([(0, accent(0.6, 1, alpha)), (1, accent(0.6, 1, 0))])
        context.drawRadialGradient(glow, startCenter: point, startRadius: 0, endCenter: point,
                                   endRadius: radius, options: [])
    }

    // Stem up from the right of the head, then the head, tilted as an
    // engraved one is.
    context.setFillColor(rgb(1, 1, 1, look == .dark ? 0.80 : 0.92))
    let stemX = head.x + headSize.width * 0.43
    context.addPath(CGPath(roundedRect: CGRect(x: stemX - 10, y: 92, width: 20, height: head.y - 92 - 6),
                           cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.fillPath()
    context.saveGState()
    context.translateBy(x: head.x, y: head.y)
    context.rotate(by: -0.36)
    context.setFillColor(accent(0.6, 1.0))
    context.fillEllipse(in: CGRect(x: -headSize.width / 2, y: -headSize.height / 2,
                                   width: headSize.width, height: headSize.height))
    context.restoreGState()

    let image = context.makeImage()!
    guard look == .tinted else { return image }

    // Tinted is handed over in grey: the system brings its own colour.
    let grey = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    grey.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
    return grey.makeImage()!
}

func write(_ image: CGImage, _ name: String, to directory: URL = outDirectory) {
    let url = directory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
    print("wrote", name, image.width, "x", image.height)
}

let icon = draw(.light)
write(icon, "AppIcon.png")
write(draw(.dark), "AppIcon-Dark.png")
write(draw(.tinted), "AppIcon-Tinted.png")

if CommandLine.arguments.count > 2 {
    let side = 256
    let small = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    small.interpolationQuality = .high
    small.draw(icon, in: CGRect(x: 0, y: 0, width: side, height: side))
    write(small.makeImage()!, "Logo.png", to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
