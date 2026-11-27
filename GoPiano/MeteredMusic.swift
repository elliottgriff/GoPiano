//
//  MeteredMusic.swift
//  GoPiano
//
//  Music written with its rhythm: bars, note values from whole notes to
//  sixteenths, rests, ties across bar lines. It needs to know where the beat
//  is, which only music that came with one does - an imported MIDI file stores
//  every note's place in beats - so this is how imports are written out.
//
//  Each staff is written as a single line of notes and rests. Notes struck
//  together are one chord; a note still sounding when the next one starts is
//  cut there, as a pianist reading it would play it; and every position is
//  snapped to the nearest sixteenth. That reads cleanly for most music, at the
//  cost of the inner detail of dense, many-voiced writing, and of triplets.
//

import CoreGraphics
import Foundation
import UIKit

struct MeteredMusic: Equatable {
    /// One thing written on a staff: a chord, or a rest when it has no notes.
    struct Item: Equatable {
        var notes: [UInt8]
        /// Beats from the start of its bar.
        let start: Double
        let value: NoteValue
        var tiedToNext = false
        var tiedFromPrevious = false
        /// A whole bar of silence: written as a whole rest in the middle of the
        /// bar, whatever the time signature.
        var fullBarRest = false
        /// Sharps and naturals to print, worked out across the bar.
        var accidentals: [UInt8: Accidental] = [:]
        /// When it sounds, in seconds, for following along during playback.
        let time: TimeInterval
    }

    struct Measure: Equatable {
        var treble: [Item] = []
        var bass: [Item] = []
    }

    /// A moment in the music, for shading what's being played.
    struct Position: Equatable {
        let measure: Int
        let start: Double
    }

    let signature: TimeSignature
    let measures: [Measure]

    /// The smallest step a note's position or length is snapped to: a
    /// sixteenth.
    static let grid = 0.25

    /// Nil when the score has no beat to write it against - anything played
    /// freely rather than imported.
    init?(score: MelodyScore) {
        guard let signature = score.timeSignature else { return nil }
        let spans = score.spans.filter { $0.beat != nil && $0.beats != nil }
        guard !spans.isEmpty else { return nil }
        self.signature = signature

        let bar = signature.barLength
        func snap(_ beat: Double) -> Double { (beat / Self.grid).rounded() * Self.grid }

        // Seconds at any beat, from the notes' own onsets: playback runs in
        // seconds, and the file may change tempo along the way.
        let anchors = Dictionary(grouping: spans, by: { snap($0.beat!) })
            .map { (beat: $0.key, seconds: $0.value.map(\.start).min() ?? 0) }
            .sorted { $0.beat < $1.beat }
        func seconds(at beat: Double) -> TimeInterval {
            guard let first = anchors.first else { return 0 }
            guard anchors.count > 1 else { return first.seconds + (beat - first.beat) * 0.5 }
            var lower = anchors[0]
            var upper = anchors[1]
            for index in 1..<anchors.count {
                lower = anchors[index - 1]
                upper = anchors[index]
                if upper.beat >= beat { break }
            }
            let span = upper.beat - lower.beat
            guard span > 0 else { return lower.seconds }
            return lower.seconds + (beat - lower.beat) * (upper.seconds - lower.seconds) / span
        }

        let lastEnd = spans.map { snap($0.beat! + $0.beats!) - 1e-9 }.max() ?? bar
        let barCount = max(1, Int((lastEnd / bar - 1e-9).rounded(.up)))
        var measures = Array(repeating: Measure(), count: barCount)
        let total = Double(barCount) * bar

        for treble in [true, false] {
            // The staff as one line of chords and the silences between them.
            let chords = Dictionary(grouping: spans.filter { ($0.note >= 60) == treble },
                                    by: { snap($0.beat!) })
                .sorted { $0.key < $1.key }
            var segments: [(start: Double, end: Double, notes: [UInt8])] = []
            var cursor = 0.0
            for (index, chord) in chords.enumerated() {
                let onset = chord.key
                let rawHeld = chord.value.map { $0.beat! + $0.beats! }.max() ?? onset
                // The next thing on this staff: its next note, or for the last
                // note, the end of the bar it's let go in - held over a bar
                // line, it's tied into the next bar, not cut off at it.
                let next = index + 1 < chords.count
                    ? chords[index + 1].key
                    : min(total, max(((onset / bar + 1e-9).rounded(.down) + 1) * bar,
                                     (rawHeld / bar - 1e-9).rounded(.up) * bar))
                var held = snap(rawHeld)
                // Players let go a little early, and files often store notes a
                // touch short of their full value. A note released just before
                // the next one is written to it - otherwise a whole note held
                // for 95% of the bar came out as a dotted half, an eighth and
                // a sliver of rest. Only a real gap becomes a rest.
                let gap = next - rawHeld
                if gap > 0, gap <= max(Self.grid, (rawHeld - onset) * 0.25) {
                    held = next
                }
                let end = max(onset + Self.grid, min(held, next))
                if onset > cursor + 1e-9 { segments.append((cursor, onset, [])) }
                segments.append((onset, end, Array(Set(chord.value.map(\.note))).sorted()))
                cursor = end
            }
            if total > cursor + 1e-9 { segments.append((cursor, total, [])) }

            // Each stretch written as note values, split at bar lines, with
            // ties joining the pieces of a note.
            for segment in segments {
                var pieces: [(bar: Int, start: Double, value: NoteValue, fullBar: Bool)] = []
                var position = segment.start
                while position < segment.end - 1e-9 {
                    let barIndex = Int(position / bar + 1e-9)
                    let barStart = Double(barIndex) * bar
                    var remaining = min(segment.end, barStart + bar) - position
                    if segment.notes.isEmpty, abs(remaining - bar) < 1e-9 {
                        pieces.append((barIndex, 0, .whole, true))
                        position += remaining
                        continue
                    }
                    while remaining > 1e-9 {
                        let value = NoteValue.all.first { $0.length <= remaining + 1e-9 } ?? .sixteenth
                        pieces.append((barIndex, position - barStart, value, false))
                        position += value.length
                        remaining -= value.length
                    }
                }
                for (index, piece) in pieces.enumerated() where piece.bar < measures.count {
                    var item = Item(notes: segment.notes,
                                    start: piece.start,
                                    value: piece.value,
                                    time: seconds(at: Double(piece.bar) * bar + piece.start))
                    item.fullBarRest = piece.fullBar
                    if !segment.notes.isEmpty {
                        item.tiedToNext = index < pieces.count - 1
                        item.tiedFromPrevious = index > 0
                    }
                    if treble {
                        measures[piece.bar].treble.append(item)
                    } else {
                        measures[piece.bar].bass.append(item)
                    }
                }
            }
        }

        // Accidentals last for the rest of their bar, so a sharp is printed
        // the first time a note needs it, and a natural when the same line
        // goes back to its plain note - without one, an F after an F sharp in
        // the same bar would be read as another F sharp.
        for index in measures.indices {
            measures[index].treble = Self.markAccidentals(measures[index].treble)
            measures[index].bass = Self.markAccidentals(measures[index].bass)
        }
        self.measures = measures
    }

    private static func markAccidentals(_ items: [Item]) -> [Item] {
        var sharpened: [Int: Bool] = [:]
        return items.map { item in
            var item = item
            for note in item.notes {
                let position = Staff.position(of: note)
                let sharp = Staff.isSharp(note)
                defer { sharpened[position] = sharp }
                // A tied continuation carries its accidental over, unprinted.
                guard !item.tiedFromPrevious else { continue }
                if sharp, sharpened[position] != true {
                    item.accidentals[note] = .sharp
                } else if !sharp, sharpened[position] == true {
                    item.accidentals[note] = .natural
                }
            }
            return item
        }
    }

    /// During playback, the note being played: the last one struck at or
    /// before this moment.
    func position(at seconds: TimeInterval) -> Position? {
        var best: (time: TimeInterval, position: Position)?
        for (index, measure) in measures.enumerated() {
            for item in measure.treble + measure.bass
            where !item.notes.isEmpty && !item.tiedFromPrevious && item.time <= seconds {
                if best == nil || item.time >= best!.time {
                    best = (item.time, Position(measure: index, start: item.start))
                }
            }
        }
        return best?.position
    }

    // MARK: - Layout

    struct Layout {
        /// One staff space; everything is measured in these.
        let space: CGFloat
        let width: CGFloat
        /// Each note's letter name in a strip under the staff.
        var showsNames = false

        var systemHeight: CGFloat { space * (18 + (showsNames ? SheetMusic.nameStrip : 0)) }

        /// A line's height: the usual, and deeper when its lowest notes hang
        /// further below the bass staff than the usual leaves room for.
        func height(of music: MeteredMusic, measures: Range<Int>) -> CGFloat {
            let notes = measures.flatMap { music.measures[$0].bass.flatMap(\.notes) }
            let depth = SheetMusic.depthBelowBass(notes)
            return systemHeight + space * SheetMusic.extraDepth(depth, showsNames: showsNames)
        }
        var margin: CGFloat { space * 1.2 }
        var notesStart: CGFloat { margin + space * 5 }
        var timeSignatureWidth: CGFloat { space * 3 }
        var measurePadding: CGFloat { space * 1.2 }

        /// A moment in a bar where something starts on either staff, and the
        /// room it gets.
        struct Column {
            let start: Double
            let width: CGFloat
            let accidentalRoom: Bool
        }

        /// Longer notes get more room, though not in proportion - a whole note
        /// would otherwise take sixteen times a sixteenth's width.
        func columns(of measure: Measure) -> [Column] {
            let items = measure.treble + measure.bass
            return Set(items.map(\.start)).sorted().map { start in
                let here = items.filter { $0.start == start }
                let shortest = here.map { $0.fullBarRest ? 4 : $0.value.length }.min() ?? 1
                let accidental = here.contains { !$0.accidentals.isEmpty }
                let room: CGFloat = switch shortest {
                case 4...: 6.2
                case 3..<4: 5.6
                case 2..<3: 4.8
                case 1.5..<2: 4.2
                case 1..<1.5: 3.6
                case 0.75..<1: 3.2
                case 0.5..<0.75: 2.8
                default: 2.4
                }
                return Column(start: start, width: space * (room + (accidental ? 1 : 0)),
                              accidentalRoom: accidental)
            }
        }

        func width(of measure: Measure) -> CGFloat {
            measurePadding + columns(of: measure).reduce(0) { $0 + $1.width } + space * 0.6
        }

        /// The bars split into lines, each filled before the next begins. The
        /// first line also carries the time signature.
        func systems(for music: MeteredMusic) -> [Range<Int>] {
            var systems: [Range<Int>] = []
            var start = 0
            var x = notesStart + timeSignatureWidth
            for (index, measure) in music.measures.enumerated() {
                let measureWidth = width(of: measure)
                if x + measureWidth > width - margin, index > start {
                    systems.append(start..<index)
                    start = index
                    x = notesStart
                }
                x += measureWidth
            }
            systems.append(start..<music.measures.count)
            return systems
        }
    }

    // MARK: - Engraving

    /// Draws one line of bars with its top edge at `top`. Full lines are
    /// stretched to the margin, as printed music is; the last line keeps its
    /// natural width and ends at the final double bar.
    static func drawSystem(_ music: MeteredMusic,
                           measures range: Range<Int>,
                           layout: Layout,
                           top: CGFloat,
                           style: SheetMusic.Style,
                           highlighted: Position? = nil,
                           in context: CGContext) {
        let space = layout.space
        let staff = Staff(space: space, top: top)
        let left = layout.margin
        let right = layout.width - layout.margin
        let line = SheetMusic.lineWidth(for: space)
        let opensPiece = range.lowerBound == 0
        let endsPiece = range.upperBound == music.measures.count

        let startX = layout.notesStart + (opensPiece ? layout.timeSignatureWidth : 0)
        let natural = range.map { layout.width(of: music.measures[$0]) }
        let naturalWidth = natural.reduce(0, +)
        let fill = naturalWidth > 0 ? (right - startX) / naturalWidth : 1
        let stretch = (!endsPiece || fill < 1.34) ? fill : 1
        let systemRight = startX + naturalWidth * stretch

        SheetMusic.drawStaves(staff, left: left, right: systemRight, style: style, line: line, in: context)

        if opensPiece {
            let x = layout.notesStart + space * 1.4
            for middle in [staff.trebleTop + space * 2, staff.bassTop + space * 2] {
                SheetMusic.drawText("\(music.signature.beats)", size: space * 2.9,
                                    centre: CGPoint(x: x, y: middle - space),
                                    colour: style.ink, weight: .bold, in: context)
                SheetMusic.drawText("\(music.signature.unit)", size: space * 2.9,
                                    centre: CGPoint(x: x, y: middle + space),
                                    colour: style.ink, weight: .bold, in: context)
            }
        }

        // Ties waiting for the next chord on their staff, which may be in the
        // next bar.
        var pendingTies: [Bool: (heads: [UInt8: CGPoint], below: Bool)] = [:]
        // Names by bar and beat, both staves together; a note carried on by a
        // tie was named where it was struck.
        var names: [Int: [Double: (x: CGFloat, notes: [UInt8])]] = [:]

        var x = startX
        for (offset, index) in range.enumerated() {
            let measure = music.measures[index]
            let measureWidth = natural[offset] * stretch
            let columns = layout.columns(of: measure)
            var columnX: [Double: (x: CGFloat, width: CGFloat, accidentalRoom: Bool)] = [:]
            var cursor = x + layout.measurePadding * stretch
            for column in columns {
                columnX[column.start] = (cursor, column.width * stretch, column.accidentalRoom)
                cursor += column.width * stretch
            }

            if let highlighted, highlighted.measure == index, let column = columnX[highlighted.start] {
                SheetMusic.drawHighlight(x: column.x - space * 0.3, width: column.width,
                                         staff: staff, style: style, in: context)
            }

            for treble in [true, false] {
                for item in treble ? measure.treble : measure.bass {
                    guard let column = columnX[item.start] else { continue }
                    let noteX = column.x + space * (column.accidentalRoom ? 1.1 : 0.3)
                    if item.notes.isEmpty {
                        let restX = item.fullBarRest ? x + measureWidth / 2 - space * 0.6 : noteX
                        drawRest(item, x: restX, treble: treble, staff: staff, style: style, in: context)
                        continue
                    }
                    if !item.tiedFromPrevious {
                        let centre = noteX + space * (item.value.base >= 4 ? 0.775 : 0.625)
                        names[index, default: [:]][item.start, default: (centre, [])].notes += item.notes
                    }
                    let drawn = SheetMusic.drawStack(item.notes, treble: treble, x: noteX,
                                                     staff: staff, style: style, line: line,
                                                     value: item.value,
                                                     accidentals: item.accidentals, in: context)
                    if let tie = pendingTies.removeValue(forKey: treble) {
                        for (note, from) in tie.heads {
                            if let to = drawn.heads[note] {
                                drawTie(from: from, to: to, below: tie.below, space: space,
                                        colour: style.ink, in: context)
                            }
                        }
                    }
                    if item.tiedToNext {
                        pendingTies[treble] = (drawn.heads, drawn.stemUp)
                    }
                }
            }

            x += measureWidth
            if endsPiece && index == range.upperBound - 1 {
                SheetMusic.drawFinalBar(at: x, staff: staff, style: style, line: line, in: context)
            } else {
                context.setStrokeColor(style.staff)
                context.setLineWidth(line)
                context.move(to: CGPoint(x: x, y: staff.trebleTop))
                context.addLine(to: CGPoint(x: x, y: staff.bassBottom))
                context.strokePath()
            }
        }

        if layout.showsNames {
            // Every note in the line counts, tied-over ones included.
            let depth = SheetMusic.depthBelowBass(range.flatMap { music.measures[$0].bass.flatMap(\.notes) })
            SheetMusic.drawNames(names.values.flatMap(\.values), depth: depth,
                                 staff: staff, style: style, in: context)
        }

        // A tie that carries over to the next line runs off the end of this one.
        for tie in pendingTies.values {
            for from in tie.heads.values {
                drawTie(from: from, to: CGPoint(x: systemRight + space * 0.8, y: from.y),
                        below: tie.below, space: space, colour: style.ink, in: context)
            }
        }
    }

    /// Whole and half rests are blocks - hanging from the fourth line, and
    /// sitting on the middle one. The shorter rests are drawn from their glyphs.
    private static func drawRest(_ item: Item,
                                 x: CGFloat,
                                 treble: Bool,
                                 staff: Staff,
                                 style: SheetMusic.Style,
                                 in context: CGContext) {
        let space = staff.space
        let middle = treble ? 34 : 22
        let middleY = staff.y(for: middle, treble: treble)
        context.setFillColor(style.ink)
        switch item.value.base {
        case 4:
            context.fill(CGRect(x: x, y: staff.y(for: middle + 2, treble: treble),
                                width: space * 1.2, height: space * 0.5))
        case 2:
            context.fill(CGRect(x: x, y: middleY - space * 0.5, width: space * 1.2, height: space * 0.5))
        case 1:
            drawQuarterRest(x: x, middleY: middleY, space: space, colour: style.ink, in: context)
        default:
            drawFlaggedRest(flags: item.value.base == 0.5 ? 1 : 2, x: x, middleY: middleY,
                            space: space, colour: style.ink, in: context)
        }
        if item.value.dotted {
            let radius = space * 0.2
            context.fillEllipse(in: CGRect(x: x + space * 1.7 - radius, y: middleY - space * 0.5 - radius,
                                           width: radius * 2, height: radius * 2))
        }
    }

    // The shorter rests are drawn rather than set as text: the system font
    // has the clefs but not these, and printed them as boxes.

    /// The quarter rest's zigzag, with its hooked foot.
    private static func drawQuarterRest(x: CGFloat,
                                        middleY: CGFloat,
                                        space: CGFloat,
                                        colour: CGColor,
                                        in context: CGContext) {
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: x + dx * space, y: middleY + dy * space)
        }
        let rest = CGMutablePath()
        rest.move(to: point(0.35, -1.5))
        rest.addLine(to: point(1.0, -0.7))
        rest.addLine(to: point(0.45, 0.0))
        rest.addLine(to: point(1.0, 0.65))
        rest.addQuadCurve(to: point(0.6, 1.45), control: point(0.15, 0.75))
        context.addPath(rest)
        context.setStrokeColor(colour)
        context.setLineWidth(space * 0.3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    /// An eighth rest - a dot with a stroke falling from it - or a sixteenth,
    /// with a second dot further down the same stroke.
    private static func drawFlaggedRest(flags: Int,
                                        x: CGFloat,
                                        middleY: CGFloat,
                                        space: CGFloat,
                                        colour: CGColor,
                                        in context: CGContext) {
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: x + dx * space, y: middleY + dy * space)
        }
        context.setFillColor(colour)
        context.setStrokeColor(colour)
        context.setLineWidth(space * 0.16)
        context.setLineCap(.round)
        let bottom: CGFloat = flags > 1 ? 1.9 : 1.0
        let stem = CGMutablePath()
        stem.move(to: point(1.15, -0.75))
        stem.addLine(to: point(1.15 - 0.4 * (bottom + 0.75), bottom))
        context.addPath(stem)
        context.strokePath()
        for index in 0..<flags {
            let drop = CGFloat(index)
            let radius = space * 0.3
            let dot = point(0.4 - drop * 0.35, -0.55 + drop)
            context.fillEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius,
                                           width: radius * 2, height: radius * 2))
            let arm = CGMutablePath()
            arm.move(to: CGPoint(x: dot.x + radius * 0.4, y: dot.y + radius * 0.6))
            arm.addQuadCurve(to: point(1.15 - drop * 0.4, -0.75 + drop),
                             control: point(0.85 - drop * 0.35, -0.2 + drop))
            context.addPath(arm)
            context.strokePath()
        }
    }

    /// A tie curves away from the stems: under notes whose stems go up, over
    /// notes whose stems go down.
    private static func drawTie(from start: CGPoint,
                                to end: CGPoint,
                                below: Bool,
                                space: CGFloat,
                                colour: CGColor,
                                in context: CGContext) {
        let direction: CGFloat = below ? 1 : -1
        let from = CGPoint(x: start.x + space * 0.5, y: start.y + direction * space * 0.5)
        let to = CGPoint(x: end.x - space * 0.5, y: end.y + direction * space * 0.5)
        guard to.x > from.x else { return }
        let bow = min(space * 1.1, (to.x - from.x) * 0.25)
        let middle = CGPoint(x: (from.x + to.x) / 2, y: from.y + direction * bow)
        let tie = CGMutablePath()
        tie.move(to: from)
        tie.addQuadCurve(to: to, control: middle)
        tie.addQuadCurve(to: from, control: CGPoint(x: middle.x, y: middle.y - direction * space * 0.3))
        tie.closeSubpath()
        context.addPath(tie)
        context.setFillColor(colour)
        context.fillPath()
    }
}
