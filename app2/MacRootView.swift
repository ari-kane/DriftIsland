//
//  MacRootView.swift
//  The Mac main window — a heavy glass dashboard showing the 4-digit
//  pairing code in giant letters, plus a list of items dropped today.
//  The actual drop happens at the screen edge (see EdgeDropWindow), not
//  in this window.
//

#if os(macOS)

import SwiftUI

struct MacRootView: View {
    @EnvironmentObject var session: PairingSession

    var body: some View {
        ZStack {
            // Dark-blue backdrop, matching the iOS pairing screen.
            LinearGradient(
                colors: [
                    Color(red: 0x05/255, green: 0x0F/255, blue: 0x1C/255),
                    Color(red: 0x0A/255, green: 0x25/255, blue: 0x40/255),
                    Color(red: 0x02/255, green: 0x08/255, blue: 0x10/255),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Lagoon-blue ambient glow at the top, replacing the old
            // orange-beige vignette.
            RadialGradient(
                colors: [Palette.lagoonBlue.opacity(0.22), .clear],
                center: .top, startRadius: 0, endRadius: 600
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                GlassBrandTitle(subtitle: "Desktop Companion")
                    .padding(.top, 18)

                pairingCard
                statusRow
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 320, minHeight: 280)
        .onAppear { session.start() }
    }

    // MARK: Pairing code card — the marquee element

    private var pairingCard: some View {
        VStack(spacing: 14) {
            Text("Pair on your iPhone")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.silkCream.opacity(0.6))
                .tracking(1.8)
                .textCase(.uppercase)

            // Digits laid out as four glass tiles for a confectionery feel.
            HStack(spacing: 12) {
                ForEach(Array(session.pairingCode), id: \.self) { ch in
                    Text(String(ch))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Palette.silkCream, Palette.lagoonBlue],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 60, height: 80)
                        .liquidGlassSurface(
                            cornerRadius: 16,
                            tint: Color(red: 0x12/255, green: 0x32/255, blue: 0x4D/255),
                            glowTint: Palette.lagoonBlue,
                            glowStrength: 0.45
                        )
                }
            }

            Text("Drag a file or link to the RIGHT EDGE.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Palette.silkCream.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .liquidGlassSurface(
            cornerRadius: 28,
            tint: Color(red: 0x12/255, green: 0x32/255, blue: 0x4D/255),
            glowTint: Palette.lagoonBlue
        )
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: 12) {
            GlassStatusPill(
                label: statusLabel,
                isConnected: session.state == .connected
            )
            Spacer()
            if let name = session.peerName {
                Text(name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.silkCream.opacity(0.65))
            }
        }
        .padding(.horizontal, 6)
    }

    private var statusLabel: String {
        switch session.state {
        case .idle:       return "Idle"
        case .searching:  return "Advertising"
        case .connecting: return "Connecting"
        case .connected:  return "Connected"
        }
    }

}

#endif
