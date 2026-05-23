//
//  ShakeListener.swift
//  iOS-only. Hooks `motionShake` into SwiftUI as a `.onShake { ... }`
//  modifier. Used by the iPhone root to send the clipboard contents back
//  to the Mac when the user shakes the device.
//

#if os(iOS)

import SwiftUI
import UIKit

extension View {
    /// Fires `perform` each time the device detects a shake gesture.
    func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeReceiver(action: action).allowsHitTesting(false))
    }
}

// MARK: - Internals

private struct ShakeReceiver: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> ShakeUIView {
        ShakeUIView(action: action)
    }

    func updateUIView(_ uiView: ShakeUIView, context: Context) {
        uiView.action = action
    }
}

// A zero-size UIView that becomes first responder so it can receive the
// `motionShake` event. Doesn't display anything and ignores touch input.
private final class ShakeUIView: UIView {
    var action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            becomeFirstResponder()
        }
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            action()
        }
    }
}

#endif
