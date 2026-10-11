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
                Toggle("Note Names", isOn: $showsLabels)
            } footer: {
                Text("Show the name of each white key.")
            }

            Section {
                HStack {
                    Text("Reverb")
                    Slider(value: Binding(get: { Double(conductor.reverbMix) },
                                          set: { conductor.setReverbMix(Float($0)) }),
                           in: 0...0.6)
                }
            } footer: {
                Text("How much room the piano sounds like it is in.")
            }

            Section("Credits") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Piano samples are from the Piano FF pack by jobro on Freesound, used under the Creative Commons Attribution 3.0 licence. The samples have been modified.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 18) {
                        Link("Piano FF pack", destination: Self.packURL)
                        Link("CC BY 3.0", destination: Self.licenceURL)
                    }
                    .font(.footnote)
                }
                .padding(.vertical, 2)
            }
        }
        // In landscape the screen is only ~400pt tall, so the popover has to
        // stay under that; the form scrolls for the rest.
        .frame(idealWidth: 360, idealHeight: 320)
    }
}
