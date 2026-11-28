//
//  SettingsView.swift
//  GoPiano
//
//  Small enough to be a popover: a whole screen for two controls would be
//  more navigation than it is worth, and in landscape it would cover the
//  keyboard for no reason.
//

import SwiftUI

struct SettingsView: View {
    @Environment(Conductor.self) private var conductor
    @Binding var showsLabels: Bool
    @AppStorage("touchDynamics") private var touchDynamics = true
    @AppStorage(KeyboardRenderer.coloursKey) private var noteColours = true
    @AppStorage(SheetMusic.namesKey) private var sheetNoteNames = false
    @AppStorage(Conductor.metronomeKey) private var metronome = false
    @AppStorage(Conductor.tempoKey) private var tempo = 100
    @AppStorage(Conductor.beatsPerBarKey) private var beatsPerBar = 4

    // The samples are CC BY 3.0, which is not attribution-optional: it wants
    // the author, the work, a link to the licence, and a note that the work was
    // changed. Ours are resampled, retuned and remapped, so they certainly are.
    private static let packURL = URL(string: "https://freesound.org/people/jobro/packs/2489/")!
    private static let licenceURL = URL(string: "https://creativecommons.org/licenses/by/3.0/")!
    private static let ePianoURL = URL(string: "https://github.com/sfzinstruments/GregSullivan.E-Pianos")!
    private static let guitarURL = URL(string: "https://github.com/facebookincubator/Meta-open-sound")!

    /// Only an iPad has music written above the keys; a phone's keys take the
    /// whole height. So on a phone the staff is only ever in a PDF, which is
    /// printed in black ink whatever the colours setting says.
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        Form {
            Section {
                // "Note Names" and "Reverb" say what they do; a caption under
                // each only costs height the popover does not have.
                Toggle("Note Names", isOn: $showsLabels)

                Toggle(isOn: $noteColours) {
                    Text("Note Colours")
                    Text(isPad ? "Each note its own colour, on the keys and the music"
                               : "Each note its own colour on the keys")
                }

                Toggle(isOn: $sheetNoteNames) {
                    Text("Names on Sheet Music")
                    Text(isPad ? "Each note's letter under the staff, above the keys and in PDFs"
                               : "Each note's letter under the staff in sheet music PDFs")
                }

                // This one does need its line: "Touch Dynamics" alone doesn't
                // say what the touch is measured by.
                Toggle(isOn: $touchDynamics) {
                    Text("Touch Dynamics")
                    Text("Louder at the front of the key")
                }

                HStack {
                    Text("Reverb")
                    Slider(value: Binding(get: { Double(conductor.reverbMix) },
                                          set: { conductor.setReverbMix(Float($0)) }),
                           in: 0...0.6)
                        .accessibilityLabel("Reverb")
                }
            }

            Section {
                Toggle(isOn: $metronome) {
                    Text("Metronome")
                    Text("Counts you in and clicks while you record, so takes are written in bars")
                }
                if metronome {
                    Stepper("Tempo  \(tempo)", value: $tempo, in: 40...220, step: 4)
                    Picker("Time", selection: $beatsPerBar) {
                        Text("2/4").tag(2)
                        Text("3/4").tag(3)
                        Text("4/4").tag(4)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Credits") {
                // The links sit inside the sentence rather than on a row of
                // their own: the row was what pushed them off the bottom of
                // the popover, taking the licence link with it.
                Text("Piano samples: [Piano FF](\(Self.packURL)) by jobro on Freesound, used under [CC BY 3.0](\(Self.licenceURL)) and modified.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The same licence as the piano, so the same credit: author,
                // work, licence, and that it was changed.
                Text("Electric piano samples: [Wurlitzer EP200](\(Self.ePianoURL)) by Greg Sullivan, used under [CC BY 3.0](\(Self.licenceURL)) and modified.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Guitar samples: [Meta Steel Guitar](\(Self.guitarURL)) from Meta Open Sound, public domain (CC0).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Sized to hold every section at once. An iPhone in landscape is only
        // ~400pt tall, so this has to stay well under that, which is why the
        // contents above are kept short rather than the box made taller.
        // Wide enough that the dynamics line stays on one line: on two, it
        // pushed the end of the licence credit below the popover's edge.
        // Scrolls on a phone in landscape; a popover can't be taller than that.
        .frame(idealWidth: 370, idealHeight: 600)
        // Dark like the instrument it sits over, not a bright card on top.
    }
}
