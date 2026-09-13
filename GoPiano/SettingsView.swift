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
        }
        .frame(idealWidth: 320, idealHeight: 260)
    }
}
