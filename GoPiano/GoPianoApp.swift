//
//  GoPianoApp.swift
//  GoPiano
//

import SwiftUI

@main
struct GoPianoApp: App {
    @State private var conductor = Conductor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(conductor)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        }
    }
}
