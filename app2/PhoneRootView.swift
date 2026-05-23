//
//  PhoneRootView.swift
//  iOS root. Landscape-only.
//    * Pre-connection — a landscape liquid-glass keypad. Brand + digit
//      slots on the left, 3×4 number pad on the right.
//    * Post-connection — IslandScene: a literal island of glass-bead files
//      floating in a lagoon-blue ocean.
//
//  Also wires `.onShake` at the root, so shaking the device sends the
//  iPhone's clipboard text/URL straight to the Mac (which auto-opens it).
//

#if os(iOS)

import SwiftUI
import UIKit

// MARK: - Root

struct PhoneRootView: View {
    @EnvironmentObject var session: PairingSession

    var body: some View {
        ZStack {
            Group {
                if session.state == .connected {
                    IslandScene()
                } else {
                    PairingKeypadLandscape()
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.85), value: session.state)
        }
        // Drift Island morphing pill — anchored near the top of the safe area.
        .overlay(alignment: .top) {
            DriftIslandHost()
        }
        .onAppear { session.start() }
        // Shake-to-paste: ship the iPhone's clipboard to the Mac, which
        // auto-opens it if it's a URL. Light feedback so the user knows
        // their shake registered.
        .onShake { sendClipboardToMac() }
    }

    private func sendClipboardToMac() {
        let raw = UIPasteboard.general.string ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, session.state == .connected else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        let item = TransferItem(
            name: String(trimmed.prefix(60)),
            kind: .url,
            urlString: trimmed
        )
        session.sendToMac(item)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Landscape pairing keypad

struct PairingKeypadLandscape: View {
    @EnvironmentObject var session: PairingSession
    @State private var digits: String = ""

    var body: some View {
        ZStack {
            // Darker blue backdrop — deep navy top to near-black bottom.
            LinearGradient(
                colors: [
                    Color(red: 0x05/255, green: 0x0F/255, blue: 0x1C/255),
                    Color(red: 0x0A/255, green: 0x25/255, blue: 0x40/255),
                    Color(red: 0x02/255, green: 0x08/255, blue: 0x10/255),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Palette.lagoonBlue.opacity(0.24), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
            .ignoresSafeArea()

            HStack(spacing: 28) {
                leftPanel
                Spacer(minLength: 0)
                keypadPanel
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
        }
        .onChange(of: digits) { _, newValue in
            if newValue.count == 4 {
                session.submitCode(newValue)
            }
        }
    }

    // MARK: left panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            GlassBrandTitle(subtitle: "Mobile Companion")

            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { idx in
                    digitSlot(at: idx)
                }
            }

            Text(statusText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.silkCream.opacity(0.6))
                .tracking(1.5)
                .textCase(.uppercase)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func digitSlot(at idx: Int) -> some View {
        let chars = Array(digits)
        let value: String = idx < chars.count ? String(chars[idx]) : ""
        let isActive = idx == chars.count

        return Text(value)
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Palette.silkCream, Palette.lagoonBlue],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .frame(width: 52, height: 70)
            .liquidGlassSurface(
                cornerRadius: 14,
                tint: Color(red: 0x12/255, green: 0x32/255, blue: 0x4D/255),
                glowTint: Palette.lagoonBlue,
                glowStrength: isActive ? 0.65 : 0.20,
                depth: 0.75
            )
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle()
                        .fill(Palette.lagoonBlue)
                        .frame(height: 2)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                        .shadow(color: Palette.lagoonBlue.opacity(0.85), radius: 6)
                }
            }
    }

    // MARK: keypad panel

    private let rows: [[KeypadButton]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.spacer,     .digit("0"), .backspace],
    ]

    private var keypadPanel: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 14) {
                    ForEach(0..<rows[r].count, id: \.self) { c in
                        keyView(rows[r][c])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyView(_ button: KeypadButton) -> some View {
        switch button {
        case .digit(let d):
            DigitKey(label: d) {
                guard digits.count < 4 else { return }
                digits.append(d)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        case .backspace:
            DigitKey(label: "⌫") {
                guard !digits.isEmpty else { return }
                digits.removeLast()
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        case .spacer:
            Color.clear.frame(width: 60, height: 60)
        }
    }

    private var statusText: String {
        switch session.state {
        case .idle:       return "Type the code shown on your Mac"
        case .searching:  return "Type the code shown on your Mac"
        case .connecting: return "Connecting…"
        case .connected:  return "Connected"
        }
    }

    private enum KeypadButton {
        case digit(String)
        case backspace
        case spacer
    }
}

// MARK: - Keypad bubble

/// Standalone keypad key — a bubble of poured glass that reacts on touch.
/// Slightly smaller than the portrait version to fit the landscape layout.
private struct DigitKey: View {
    let label: String
    let action: () -> Void
    @State private var isPressed: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [Palette.silkCream, Palette.silkCream.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .liquidGlassKey(
                tint: Color(red: 0x12/255, green: 0x32/255, blue: 0x4D/255),
                accent: Palette.lagoonBlue,
                isPressed: isPressed,
                diameter: 60
            )
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isPressed { isPressed = true } }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
    }
}

#endif
