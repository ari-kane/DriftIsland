//
//  ContentView.swift
//  Tiny router. Picks the Mac or iPhone root view based on platform.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MacRootView()
        #else
        PhoneRootView()
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject({
            #if os(macOS)
            return PairingSession(role: .mac)
            #else
            return PairingSession(role: .phone)
            #endif
        }())
}
