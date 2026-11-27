//
//  ScoreView.swift
//  GoPiano
//
//  The page above the keys: the song as sheet music. Played freely, it is
//  written as you go - each key pressed adds its note after the last, chords
//  stacked, lines filling and wrapping - and nothing scrolls away: the page
//  stays on the newest line, and the lines before it are a scroll up. Music
//  that came with its beat, an imported file, is written properly in bars,
//  with note values, rests and ties.
//
//  The engraving itself is SheetMusic's and MeteredMusic's, shared with the
//  PDF, so a shared sheet looks like the page did.
//

import SwiftUI

struct ScoreView: View {
    @Environment(Conductor.self) private var conductor

    var body: some View {
        GeometryReader { proxy in
            // Sized so a line and a half shows at once: the line in hand, and
            // the end of the one before it for context.
            let space = min(proxy.size.height / 20, 16)
            switch conductor.page {
            case .written(let chords):
                WrittenPage(chords: chords,
                            layout: SheetMusic.Layout(space: space, width: proxy.size.width),
                            isLive: conductor.pageIsLive,
                            current: currentChord(in: chords))
            case .metered(let music):
                MeteredPage(music: music,
                            layout: MeteredMusic.Layout(space: space, width: proxy.size.width),
                            current: currentPosition(in: music))
            }
        }
        .background {
            // The same lacquer as the case of the instrument: the page reads
            // as part of the piano, not a card laid over it.
            LinearGradient(colors: [Color(white: 0.10), Color(white: 0.05)],
                           startPoint: .top, endPoint: .bottom)
        }
        // The keys already speak every note to VoiceOver.
        .accessibilityHidden(true)
    }

    // During a replay, what's being played - read when the sounding notes
    // change, which is exactly when it moves on.

    private func currentChord(in chords: [SheetChord]) -> Int? {
        guard conductor.isPlaying, !conductor.replayNotes.isEmpty else { return nil }
        let now = conductor.readoutTime + 0.03
        return chords.lastIndex { $0.time <= now }
    }

    private func currentPosition(in music: MeteredMusic) -> MeteredMusic.Position? {
        guard conductor.isPlaying, !conductor.replayNotes.isEmpty else { return nil }
        return music.position(at: conductor.readoutTime + 0.03)
    }
}

/// Freely played music, written note by note.
private struct WrittenPage: View {
    let chords: [SheetChord]
    let layout: SheetMusic.Layout
    let isLive: Bool
    let current: Int?

    var body: some View {
        let systems = layout.systems(for: chords)
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(systems.enumerated()), id: \.offset) { index, range in
                        let lineChords = Array(chords[range])
                        let highlighted = current.map { $0 - range.lowerBound }
                        let ends = !isLive && index == systems.count - 1
                        Canvas { context, _ in
                            context.withCGContext { cgContext in
                                SheetMusic.drawSystem(lineChords, layout: layout, top: 0,
                                                      style: .screen, highlighted: highlighted,
                                                      endsSong: ends, in: cgContext)
                            }
                        }
                        .frame(height: layout.systemHeight)
                        .id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Writing: keep the newest line in view. A finished song opens at
            // its beginning, where reading starts.
            .onChange(of: chords) {
                reader.scrollTo(isLive ? systems.count - 1 : 0, anchor: isLive ? .bottom : .top)
            }
            .onChange(of: current) {
                guard let current,
                      let line = systems.firstIndex(where: { $0.contains(current) }) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { reader.scrollTo(line, anchor: .center) }
            }
            .onAppear {
                reader.scrollTo(isLive ? systems.count - 1 : 0, anchor: isLive ? .bottom : .top)
            }
        }
    }
}

/// Music that came with its beat, written in bars.
private struct MeteredPage: View {
    let music: MeteredMusic
    let layout: MeteredMusic.Layout
    let current: MeteredMusic.Position?

    var body: some View {
        let systems = layout.systems(for: music)
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(systems.enumerated()), id: \.offset) { index, range in
                        let highlighted = current.flatMap { range.contains($0.measure) ? $0 : nil }
                        Canvas { context, _ in
                            context.withCGContext { cgContext in
                                MeteredMusic.drawSystem(music, measures: range, layout: layout,
                                                        top: 0, style: .screen,
                                                        highlighted: highlighted, in: cgContext)
                            }
                        }
                        .frame(height: layout.systemHeight)
                        .id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onChange(of: music) { reader.scrollTo(0, anchor: .top) }
            .onChange(of: current) {
                guard let current,
                      let line = systems.firstIndex(where: { $0.contains(current.measure) }) else { return }
                withAnimation(.easeInOut(duration: 0.3)) { reader.scrollTo(line, anchor: .center) }
            }
        }
    }
}
