//
//  SheetMusic.swift
//  GoPiano
//
//  A song written down as sheet music. One set of routines engraves it -
//  grand staves, clefs, noteheads, stems, flags, dots, sharps and naturals,
//  ledger lines - and both the page above the keys and the shared PDF draw
//  with it, so what is shared is what was on screen.
//
//  Music comes in two kinds. Music that came with a beat - an imported MIDI
//  file - is written properly, in bars with real note values, rests and ties
//  (MeteredMusic). Music played freely has no beat to measure rhythm against,
//  and a guessed rhythm would be written wrong, so it is written as the notes
//  in the order they were played, every one the same value, chords stacked,
//  lines wrapping like a page of music. Pitch and order are exact either way.
//

import CoreGraphics
import Foundation
import UIKit

/// Notes struck together, written as one chord.
struct SheetChord: Equatable {
    var notes: [UInt8]
    /// When it was struck, so a replay can follow along on the page.
    let time: TimeInterval
}

/// What the page above the keys holds.
enum SheetPage: Equatable {
    /// Notes in the order played, all one value: music with no beat.
    case written([SheetChord])
    /// Bars, note values and rests: music that came with its beat.
    case metered(MeteredMusic)

    init(score: MelodyScore) {
        if let music = MeteredMusic(score: score) {
            self = .metered(music)
        } else {
            self = .written(SheetMusic.chords(from: score))
        }
    }
}

/// A written length: whole, half, quarter, eighth or sixteenth, any of them
/// dotted to last half as long again.
struct NoteValue: Equatable {
    /// In quarter-note beats: 4 for a whole note, down to a quarter of a beat
    /// for a sixteenth.
    let base: Double
    let dotted: Bool

    var length: Double { dotted ? base * 1.5 : base }
    /// Half and whole notes have hollow heads.
    var isOpen: Bool { base >= 2 }
    var hasStem: Bool { base < 4 }
    var flags: Int { base == 0.5 ? 1 : base == 0.25 ? 2 : 0 }

    static let whole = NoteValue(base: 4, dotted: false)
    static let quarter = NoteValue(base: 1, dotted: false)
    static let sixteenth = NoteValue(base: 0.25, dotted: false)

    /// Longest first, for writing a length as the fewest values.
    static let all: [NoteValue] = [
        NoteValue(base: 4, dotted: false),
        NoteValue(base: 2, dotted: true),
        NoteValue(base: 2, dotted: false),
        NoteValue(base: 1, dotted: true),
        NoteValue(base: 1, dotted: false),
        NoteValue(base: 0.5, dotted: true),
        NoteValue(base: 0.5, dotted: false),
        NoteValue(base: 0.25, dotted: false),
    ]
}

enum Accidental: Equatable {
    case sharp
    case natural

    var glyph: String { self == .sharp ? "♯" : "♮" }
}

enum SheetMusic {
    /// Notes struck within this long of each other are one chord. A hand
    /// never lands a chord perfectly together; this is about as far apart as
    /// its notes spread.
    static let together: TimeInterval = 0.06

    static func chords(from score: MelodyScore) -> [SheetChord] {
        var chords: [SheetChord] = []
        for span in score.spans.sorted(by: { $0.start < $1.start }) {
            add(span.note, at: span.start, to: &chords)
        }
        return chords
    }

    /// Writes the next note: into the last chord if it was struck with it,
    /// otherwise as a new chord after it.
    static func add(_ note: UInt8, at time: TimeInterval, to chords: inout [SheetChord]) {
        if let last = chords.last, time - last.time <= together {
            if !last.notes.contains(note) { chords[chords.count - 1].notes.append(note) }
        } else {
            chords.append(SheetChord(notes: [note], time: time))
        }
    }

    // MARK: - Layout of freely played music

    struct Layout {
        /// One staff space, the gap between two staff lines. Everything on
        /// the page is measured in these, so it scales to any size.
        let space: CGFloat
        let width: CGFloat

        /// A grand staff, with room above and below for ledger lines.
        var systemHeight: CGFloat { space * 18 }
        var margin: CGFloat { space * 1.2 }
        /// Where the first note goes, after the clefs.
        var notesStart: CGFloat { margin + space * 5 }

        func width(of chord: SheetChord) -> CGFloat {
            space * (chord.notes.contains(where: Staff.isSharp) ? 3.8 : 3.0)
        }

        /// The chords split into lines, each filled before the next begins.
        /// There is always at least one, so an empty page still shows a staff.
        func systems(for chords: [SheetChord]) -> [Range<Int>] {
            var systems: [Range<Int>] = []
            var start = 0
            var x = notesStart
            for (index, chord) in chords.enumerated() {
                let chordWidth = width(of: chord)
                if x + chordWidth > width - margin, index > start {
                    systems.append(start..<index)
                    start = index
                    x = notesStart
                }
                x += chordWidth
            }
            systems.append(start..<chords.count)
            return systems
        }
    }

    struct Style {
        /// Clefs, stems, flags, rests and accidentals.
        let ink: CGColor
        let staff: CGColor
        /// Noteheads in their key's colour, or all in ink.
        let colouredNotes: Bool
        let highlight: CGColor

        /// Light on the lacquer above the keys, notes in their key colours.
        static let screen = Style(ink: UIColor(white: 1, alpha: 0.85).cgColor,
                                  staff: UIColor(white: 1, alpha: 0.3).cgColor,
                                  colouredNotes: true,
                                  highlight: UIColor(white: 1, alpha: 0.12).cgColor)
        /// Black ink on white, as printed music is.
        static let print = Style(ink: UIColor.black.cgColor,
                                 staff: UIColor(white: 0, alpha: 0.7).cgColor,
                                 colouredNotes: false,
                                 highlight: UIColor.clear.cgColor)
    }

    /// Draws one line of freely played music - a grand staff, its clefs and its
    /// chords, every one the same value - with its top edge at `top`. Assumes a
    /// UIKit-style context, origin top-left.
    static func drawSystem(_ chords: [SheetChord],
                           layout: Layout,
                           top: CGFloat,
                           style: Style,
                           highlighted: Int? = nil,
                           endsSong: Bool = false,
                           in context: CGContext) {
        let space = layout.space
        let staff = Staff(space: space, top: top)
        let left = layout.margin
        let right = layout.width - layout.margin
        let line = lineWidth(for: space)

        // A finished song's staff stops at its final double bar, as printed
        // music does, rather than running on empty to the edge.
        let notesEnd = chords.reduce(layout.notesStart) { $0 + layout.width(of: $1) }
        let closes = endsSong && !chords.isEmpty
        let finalBar = min(notesEnd + space * 1.1, right)

        var x = layout.notesStart
        for (index, chord) in chords.enumerated() {
            let chordWidth = layout.width(of: chord)
            if index == highlighted {
                drawHighlight(x: x, width: chordWidth, staff: staff, style: style, in: context)
            }
            x += chordWidth
        }

        drawStaves(staff, left: left, right: closes ? finalBar : right, style: style, line: line, in: context)

        x = layout.notesStart
        for chord in chords {
            let hasSharp = chord.notes.contains(where: Staff.isSharp)
            let noteX = x + space * (hasSharp ? 1.3 : 0.6)
            let treble = chord.notes.filter { $0 >= 60 }
            let bass = chord.notes.filter { $0 < 60 }
            if !treble.isEmpty {
                drawStack(treble, treble: true, x: noteX, staff: staff, style: style, line: line, in: context)
            }
            if !bass.isEmpty {
                drawStack(bass, treble: false, x: noteX, staff: staff, style: style, line: line, in: context)
            }
            x += layout.width(of: chord)
        }

        if closes {
            drawFinalBar(at: finalBar, staff: staff, style: style, line: line, in: context)
        }
    }

    // MARK: - Engraving, shared by both kinds of music

    static func lineWidth(for space: CGFloat) -> CGFloat { max(0.5, space * 0.1) }

    /// The five lines of each staff, the line joining them into one system, and
    /// the clefs.
    static func drawStaves(_ staff: Staff,
                           left: CGFloat,
                           right: CGFloat,
                           style: Style,
                           line: CGFloat,
                           in context: CGContext) {
        let space = staff.space
        context.setStrokeColor(style.staff)
        context.setLineWidth(line)
        for index in 0..<5 {
            for staffTop in [staff.trebleTop, staff.bassTop] {
                let y = staffTop + CGFloat(index) * space
                context.move(to: CGPoint(x: left, y: y))
                context.addLine(to: CGPoint(x: right, y: y))
            }
        }
        context.move(to: CGPoint(x: left, y: staff.trebleTop))
        context.addLine(to: CGPoint(x: left, y: staff.bassBottom))
        context.strokePath()

        // The treble clef curls round G, the second line up, standing about
        // seven spaces tall; the bass clef's dots sit either side of F.
        drawText("𝄞", size: space * 9.6,
                 centre: CGPoint(x: left + space * 1.9, y: staff.trebleBottom - space * 2.0),
                 colour: style.ink, in: context)
        drawText("𝄢", size: space * 3.6,
                 centre: CGPoint(x: left + space * 1.9, y: staff.bassTop + space * 1.45),
                 colour: style.ink, in: context)
    }

    /// Shades the column of whatever is being played.
    static func drawHighlight(x: CGFloat, width: CGFloat, staff: Staff, style: Style, in context: CGContext) {
        let space = staff.space
        let column = CGRect(x: x, y: staff.trebleTop - space * 2.5,
                            width: width,
                            height: staff.bassBottom - staff.trebleTop + space * 5)
        context.setFillColor(style.highlight)
        context.addPath(UIBezierPath(roundedRect: column, cornerRadius: space * 0.8).cgPath)
        context.fillPath()
    }

    /// A thin line, then a thick one: the end of the piece.
    static func drawFinalBar(at x: CGFloat, staff: Staff, style: Style, line: CGFloat, in context: CGContext) {
        let space = staff.space
        context.setStrokeColor(style.ink)
        context.setLineWidth(line)
        context.move(to: CGPoint(x: x - space * 0.6, y: staff.trebleTop))
        context.addLine(to: CGPoint(x: x - space * 0.6, y: staff.bassBottom))
        context.strokePath()
        context.setLineWidth(space * 0.45)
        context.move(to: CGPoint(x: x - space * 0.22, y: staff.trebleTop))
        context.addLine(to: CGPoint(x: x - space * 0.22, y: staff.bassBottom))
        context.strokePath()
    }

    /// The notes of a chord that share a staff, on one stem, written as
    /// `value`. Returns where each notehead was drawn, for ties, and which way
    /// the stem went. Without `accidentals`, every black key takes a sharp.
    @discardableResult
    static func drawStack(_ notes: [UInt8],
                          treble: Bool,
                          x: CGFloat,
                          staff: Staff,
                          style: Style,
                          line: CGFloat,
                          value: NoteValue = .quarter,
                          accidentals: [UInt8: Accidental]? = nil,
                          in context: CGContext) -> (heads: [UInt8: CGPoint], stemUp: Bool) {
        let space = staff.space
        let headWidth = space * (value.base >= 4 ? 1.55 : 1.25)
        let entries = notes
            .map { (note: $0, position: Staff.position(of: $0)) }
            .sorted { $0.position < $1.position }
        guard let low = entries.first?.position, let high = entries.last?.position else {
            return ([:], true)
        }

        // Stems point away from whichever note strays furthest from the
        // middle line - up when the chord sits low, down when it sits high.
        let middle = treble ? 34 : 22
        let stemUp = (middle - low) > (high - middle)

        // Notes a step apart can't share a column, so every other one moves to
        // the far side of the stem.
        var offsets = [CGFloat](repeating: 0, count: entries.count)
        if stemUp {
            for index in entries.indices.dropFirst()
            where entries[index].position - entries[index - 1].position == 1 && offsets[index - 1] == 0 {
                offsets[index] = headWidth * 0.92
            }
        } else {
            for index in entries.indices.dropLast().reversed()
            where entries[index + 1].position - entries[index].position == 1 && offsets[index + 1] == 0 {
                offsets[index] = -headWidth * 0.92
            }
        }
        let leftmost = offsets.min() ?? 0
        let rightmost = offsets.max() ?? 0

        context.setStrokeColor(style.staff)
        context.setLineWidth(line)
        let ledgers = Set(Staff.ledgers(for: low, treble: treble) + Staff.ledgers(for: high, treble: treble))
        for ledger in ledgers {
            let y = staff.y(for: ledger, treble: treble)
            context.move(to: CGPoint(x: x + leftmost - space * 0.35, y: y))
            context.addLine(to: CGPoint(x: x + headWidth + rightmost + space * 0.35, y: y))
        }
        context.strokePath()

        var heads: [UInt8: CGPoint] = [:]
        for (index, entry) in entries.enumerated() {
            let centre = CGPoint(x: x + offsets[index] + headWidth / 2,
                                 y: staff.y(for: entry.position, treble: treble))
            let colour = style.colouredNotes ? KeyboardRenderer.noteColour(for: entry.note) : style.ink
            drawHead(at: centre, value: value, space: space, colour: colour, in: context)
            heads[entry.note] = centre
        }

        if value.hasStem {
            // Flags need a longer stem to hang from.
            let stemLength = space * (value.flags > 1 ? 4.0 : 3.5)
            let lowY = staff.y(for: low, treble: treble)
            let highY = staff.y(for: high, treble: treble)
            let stemX = stemUp ? x + headWidth - line / 2 : x + line / 2
            let tip = stemUp ? highY - stemLength : lowY + stemLength
            context.setStrokeColor(style.ink)
            context.setLineWidth(line * 1.2)
            context.move(to: CGPoint(x: stemX, y: stemUp ? lowY : highY))
            context.addLine(to: CGPoint(x: stemX, y: tip))
            context.strokePath()
            if value.flags > 0 {
                drawFlags(value.flags, stemX: stemX, tip: tip, stemUp: stemUp,
                          space: space, colour: style.ink, in: context)
            }
        }

        if value.dotted {
            // A dot sits in a space; a note on a line has its dot nudged up
            // into the space above.
            context.setFillColor(style.ink)
            let dotX = x + rightmost + headWidth + space * 0.5
            for entry in entries {
                let onLine = entry.position % 2 == 0
                let y = staff.y(for: entry.position, treble: treble) - (onLine ? space / 2 : 0)
                let radius = space * 0.2
                context.fillEllipse(in: CGRect(x: dotX - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
            }
        }

        // Accidentals in front of their notes, stepping further left when two
        // would otherwise collide.
        var column = 0
        var lastMarked: Int?
        for entry in entries.reversed() {
            let mark = accidentals.map { $0[entry.note] }
                ?? (Staff.isSharp(entry.note) ? .sharp : nil)
            guard let mark else { continue }
            if let last = lastMarked, last - entry.position < 6 { column += 1 } else { column = 0 }
            lastMarked = entry.position
            drawText(mark.glyph, size: space * 1.8,
                     centre: CGPoint(x: x + leftmost - space * 0.75 - CGFloat(column) * space * 0.9,
                                     y: staff.y(for: entry.position, treble: treble)),
                     colour: style.ink, in: context)
        }

        return (heads, stemUp)
    }

    /// Filled for quarter notes and shorter, hollow for halves and wholes.
    private static func drawHead(at centre: CGPoint,
                                 value: NoteValue,
                                 space: CGFloat,
                                 colour: CGColor,
                                 in context: CGContext) {
        let whole = value.base >= 4
        let path = CGMutablePath()
        path.addPath(ellipse(width: space * (whole ? 1.55 : 1.25), height: space * (whole ? 0.95 : 0.9),
                             angle: whole ? 0 : -0.33, centre: centre))
        if value.isOpen {
            // The hollow inside, tilted further than the head so its rim is
            // thick at the sides and thin top and bottom, as engraved.
            path.addPath(ellipse(width: space * (whole ? 0.72 : 1.0), height: space * (whole ? 0.5 : 0.42),
                                 angle: whole ? 0.9 : -0.55, centre: centre))
        }
        context.addPath(path)
        context.setFillColor(colour)
        context.fillPath(using: .evenOdd)
    }

    private static func ellipse(width: CGFloat, height: CGFloat, angle: CGFloat, centre: CGPoint) -> CGPath {
        var transform = CGAffineTransform(translationX: centre.x, y: centre.y).rotated(by: angle)
        return CGPath(ellipseIn: CGRect(x: -width / 2, y: -height / 2, width: width, height: height),
                      transform: &transform)
    }

    /// Flags always point right; they hang from an up-stem and rise from a
    /// down-stem.
    private static func drawFlags(_ count: Int,
                                  stemX: CGFloat,
                                  tip: CGFloat,
                                  stemUp: Bool,
                                  space: CGFloat,
                                  colour: CGColor,
                                  in context: CGContext) {
        let direction: CGFloat = stemUp ? 1 : -1
        context.setFillColor(colour)
        for index in 0..<count {
            let y = tip + direction * CGFloat(index) * space * 0.85
            let flag = CGMutablePath()
            flag.move(to: CGPoint(x: stemX, y: y))
            flag.addCurve(to: CGPoint(x: stemX + space * 0.95, y: y + direction * space * 2.2),
                          control1: CGPoint(x: stemX + space * 0.15, y: y + direction * space * 0.9),
                          control2: CGPoint(x: stemX + space * 1.25, y: y + direction * space * 1.2))
            flag.addCurve(to: CGPoint(x: stemX, y: y + direction * space * 0.8),
                          control1: CGPoint(x: stemX + space * 0.95, y: y + direction * space * 1.5),
                          control2: CGPoint(x: stemX + space * 0.3, y: y + direction * space * 1.1))
            flag.closeSubpath()
            context.addPath(flag)
            context.fillPath()
        }
    }

    static func drawText(_ text: String,
                         size: CGFloat,
                         centre: CGPoint,
                         colour: CGColor,
                         weight: UIFont.Weight = .regular,
                         in context: CGContext) {
        let string = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: UIColor(cgColor: colour),
        ])
        let bounds = string.size()
        UIGraphicsPushContext(context)
        string.draw(at: CGPoint(x: centre.x - bounds.width / 2, y: centre.y - bounds.height / 2))
        UIGraphicsPopContext()
    }
}

/// Where things go on a grand staff.
struct Staff {
    let space: CGFloat
    let trebleTop: CGFloat
    let trebleBottom: CGFloat
    let bassTop: CGFloat
    let bassBottom: CGFloat

    /// A grand staff whose system starts at `top`: four spaces of room for
    /// ledger lines, the treble staff, a gap, the bass staff, and room below.
    init(space: CGFloat, top: CGFloat) {
        self.space = space
        trebleTop = top + space * 4
        trebleBottom = trebleTop + space * 4
        bassTop = trebleBottom + space * 3
        bassBottom = bassTop + space * 4
    }

    /// Steps up the staff, counting every line and space: C4 is 28, and each
    /// octave adds seven. Black keys share their letter and take a sharp.
    static func position(of note: UInt8) -> Int {
        let letters = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
        return (Int(note) / 12 - 1) * 7 + letters[Int(note) % 12]
    }

    static func isSharp(_ note: UInt8) -> Bool {
        [1, 3, 6, 8, 10].contains(Int(note) % 12)
    }

    /// Middle C and up on the treble staff, everything below on the bass.
    /// Treble lines run E4 (30) to F5 (38); bass lines G2 (18) to A3 (26).
    func y(for position: Int, treble: Bool) -> CGFloat {
        treble
            ? trebleBottom - CGFloat(position - 30) * space / 2
            : bassBottom - CGFloat(position - 18) * space / 2
    }

    static func ledgers(for position: Int, treble: Bool) -> [Int] {
        if treble {
            if position <= 28 { return Array(stride(from: 28, through: position, by: -2)) }
            if position >= 40 { return Array(stride(from: 40, through: position, by: 2)) }
        } else {
            if position <= 16 { return Array(stride(from: 16, through: position, by: -2)) }
            if position >= 28 { return Array(stride(from: 28, through: position, by: 2)) }
        }
        return []
    }
}

// MARK: - PDF

enum SheetMusicError: LocalizedError {
    case noNotes
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noNotes:
            "There are no notes to write out. Melodies saved before GoPiano recorded which keys were played have only their sound."
        case .writeFailed:
            "The sheet music could not be written."
        }
    }
}

enum SheetMusicPDF {
    /// Writes `score` as printable sheet music and returns the file, ready for
    /// the share sheet: the title at the top, then as many lines of music as
    /// the song needs, over as many pages. Music that came with its beat is
    /// written in bars with real note values; anything else, note by note.
    static func write(_ score: MelodyScore, named name: String, subtitle: String) throws -> URL {
        guard !score.isEmpty else { throw SheetMusicError.noNotes }

        // Letter where it's the norm, A4 everywhere else.
        let paper = Locale.current.measurementSystem == .us
            ? CGSize(width: 612, height: 792)
            : CGSize(width: 595, height: 842)
        let margin: CGFloat = 54
        let space: CGFloat = 6.5
        let inset = margin - space * 1.2
        let width = paper.width - inset * 2

        let systemCount: Int
        let systemHeight: CGFloat
        let drawSystem: (Int, CGFloat, CGContext) -> Void
        switch SheetPage(score: score) {
        case .metered(let music):
            let layout = MeteredMusic.Layout(space: space, width: width)
            let systems = layout.systems(for: music)
            systemCount = systems.count
            systemHeight = layout.systemHeight
            drawSystem = { index, top, context in
                MeteredMusic.drawSystem(music, measures: systems[index], layout: layout,
                                        top: top, style: .print, in: context)
            }
        case .written(let chords):
            let layout = SheetMusic.Layout(space: space, width: width)
            let systems = layout.systems(for: chords)
            systemCount = systems.count
            systemHeight = layout.systemHeight
            drawSystem = { index, top, context in
                SheetMusic.drawSystem(Array(chords[systems[index]]), layout: layout, top: top,
                                      style: .print, endsSong: index == systems.count - 1,
                                      in: context)
            }
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: name,
                               kCGPDFContextCreator as String: "GoPiano"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: paper),
                                             format: format)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeFileName(name))
            .appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: url)

        do {
            try renderer.writePDF(to: url) { pdf in
                let context = pdf.cgContext
                var index = 0
                var page = 0
                while index < systemCount {
                    pdf.beginPage()
                    page += 1
                    var y = margin
                    if page == 1 {
                        y = drawTitle(name, subtitle: subtitle, width: paper.width, top: y)
                    }
                    while index < systemCount, y + systemHeight <= paper.height - margin - 16 {
                        context.saveGState()
                        context.translateBy(x: inset, y: 0)
                        drawSystem(index, y, context)
                        context.restoreGState()
                        y += systemHeight
                        index += 1
                    }
                    drawFooter(page: page, size: paper, margin: margin)
                }
            }
        } catch {
            throw SheetMusicError.writeFailed
        }
        return url
    }

    /// The song's name, centred, with a line beneath saying where it came from.
    private static func drawTitle(_ name: String, subtitle: String, width: CGFloat, top: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        var titleFont = UIFont.systemFont(ofSize: 22, weight: .semibold)
        if let serif = titleFont.fontDescriptor.withDesign(.serif) {
            titleFont = UIFont(descriptor: serif, size: 22)
        }
        let title = NSAttributedString(string: name, attributes: [
            .font: titleFont, .foregroundColor: UIColor.black, .paragraphStyle: style,
        ])
        let detail = NSAttributedString(string: subtitle, attributes: [
            .font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.darkGray,
            .paragraphStyle: style,
        ])
        let titleHeight = title.size().height
        title.draw(in: CGRect(x: 0, y: top, width: width, height: titleHeight))
        detail.draw(in: CGRect(x: 0, y: top + titleHeight + 4, width: width, height: 14))
        return top + titleHeight + 34
    }

    private static func drawFooter(page: Int, size: CGSize, margin: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let footer = NSAttributedString(string: "\(page)", attributes: [
            .font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray,
            .paragraphStyle: style,
        ])
        footer.draw(in: CGRect(x: 0, y: size.height - margin + 10, width: size.width, height: 12))
    }

    private static func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || cleaned.hasPrefix(".") ? "Sheet Music" : cleaned
    }
}
