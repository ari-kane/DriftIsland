//
//  app2App.swift
//  App entry. Wires up the shared PairingSession and — on macOS — installs
//  the always-on-top edge-of-screen drop window via an NSApplicationDelegate.
//

import SwiftUI

@main
struct app2App: App {

    #if os(macOS)
    // Build the session once. Both the menu-bar UI and the edge window share it.
    @StateObject private var session = PairingSession(role: .mac)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(kAppName) {
            ContentView()
                .environmentObject(session)
                .onAppear { appDelegate.attach(session: session) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 320, height: 300)
    }
    #else
    @StateObject private var session = PairingSession(role: .phone)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
    #endif
}

// MARK: - macOS app delegate
//
// Owns the edge-drop window controller. Created lazily on launch so the
// SwiftUI scene can attach the shared PairingSession into it.
#if os(macOS)
import AppKit

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    private let edgeController = EdgeDropWindowController()
    private var attached = false

    func attach(session: PairingSession) {
        guard !attached else { return }
        attached = true
        edgeController.install(session: session)
    }
}
#endif
