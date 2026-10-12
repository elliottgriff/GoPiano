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

    // The samples are CC BY 3.0, which is not attribution-optional: it wants
    // the author, the work, a link to the licence, and a note that the work was
    // changed. Ours are resampled, retuned and remapped, so they certainly are.
    private static let packURL = URL(string: "https://freesound.org/people/jobro/packs/2489/")!
    private static let licenceURL = URL(string: "https://creativecommons.org/licenses/by/3.0/")!

    var body: some View {
        Form {
            Section {
                // "Note Names" and "Reverb" say what they do; a caption under
                // each only costs height the popover does not have.
                Toggle("Note Names", isOn: $showsLabels)

                HStack {
                    Text("Reverb")
                    Slider(value: Binding(get: { Double(conductor.reverbMix) },
                                          set: { conductor.setReverbMix(Float($0)) }),
                           in: 0...0.6)
                        .accessibilityLabel("Reverb")
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
            }
        }
        // Sized to hold every section at once. An iPhone in landscape is only
        // ~400pt tall, so this has to stay well under that, which is why the
        // contents above are kept short rather than the box made taller.
        .frame(idealWidth: 340, idealHeight: 300)
    }
}
