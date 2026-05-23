//
//  DriftIsland.swift
//  iOS-only. The signature feature: a "Drift Island" that morphs at the top
//  of the screen like Apple's Dynamic Island, showing incoming transfers in
//  real time. Three live phases — peeking, expanded, complete — driven off
//  the PairingSession's published item stream.
//
//  Visual stack:
//    * deep black body (matches the device's Dynamic Island silhouette)
//    * top specular sheen (the "wet glass" lip)
//    * inner radial caustic in the active accent color
//    * an animated TIDE wave at the bottom that rises with file progress
//    * an outer halo of the accent color, gently pulsing
//
//  Coupled to HapticPour: a file transfer starts a continuous low pour,
//  ramps with bytes, and ends in a "thunk" on completion.
//

#if os(iOS)

import SwiftUI
import UIKit

// MARK: - Phase

enum DriftIslandPhase: Equatable {
    case dormant   // hidden
    case peeking   // small pill: "Incoming…"
    case expanded  // full pill: icon · name · progress ring
    case complete  // shrunk to a checkmark, lagoon-blue glow
}

// MARK: - Host
//
// Drop this view at the TOP of the iPhone screen as an overlay. It owns the
// phase state, schedules auto-dismiss timers, and drives the haptic engine.

struct DriftIslandHost: View {
    @EnvironmentObject var session: PairingSession
    @StateObject private var haptic = HapticPour()

    @State private var phase: DriftIslandPhase = .dormant
    @State private var shownID: UUID?
    @State private var dismissTask: Task<Void, Never>?

    private var shownItem: TransferItem? {
        guard let id = shownID else { return nil }
        return session.items.first(where: { $0.id == id })
    }

    var body: some View {
        DriftIslandView(item: shownItem, phase: phase, onTap: handleTap)
            .padding(.top, 10)
            .onChange(of: session.lastReceivedID) { _, newID in
                guard let id = newID else { return }
                present(id: id)
            }
            .onChange(of: shownItem?.progress ?? 0) { _, p in
                guard let item = shownItem, item.kind == .file else { return }
                haptic.updatePour(progress: p)
                if p >= 1.0 && phase != .complete && phase != .dormant {
                    haptic.stopWithThunk()
                    transition(to: .complete)
                    scheduleDismiss(after: 1.7)
                }
            }
            // If the item we're currently showing gets removed mid-download
            // (double-tap remove, toss into water, etc.), the lookup
            // returns nil. Dismiss the pill immediately so we don't leave
            // an empty black Dynamic-Island-shaped artifact hanging at
            // the top of the screen.
            .onChange(of: shownItem == nil) { _, isNil in
                if isNil && phase != .dormant {
                    dismissTask?.cancel()
                    haptic.cancel()
                    transition(to: .dormant, response: 0.5, damping: 0.88)
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.6))
                        shownID = nil
                    }
                }
            }
    }

    private func present(id: UUID) {
        dismissTask?.cancel()
        shownID = id
        let kind = session.items.first(where: { $0.id == id })?.kind
        if kind == .file {
            haptic.startPour()
        } else {
            // URL items get a single soft tap so arrivals still feel haptic.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        transition(to: .peeking, response: 0.42, damping: 0.72)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            transition(to: .expanded)
            if kind == .url {
                scheduleDismiss(after: 3.2)
            }
        }
    }

    private func transition(to next: DriftIslandPhase, response: Double = 0.55, damping: Double = 0.78) {
        withAnimation(.spring(response: response, dampingFraction: damping)) {
            phase = next
        }
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            transition(to: .dormant, response: 0.6, damping: 0.88)
        }
    }

    private func handleTap() {
        guard let item = shownItem else { return }
        let target: String? = (item.kind == .url) ? item.urlString : item.macSourcePath
        guard let s = target else { return }
        session.requestOpen(s)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - View

private struct DriftIslandView: View {
    let item: TransferItem?
    let phase: DriftIslandPhase
    let onTap: () -> Void

    @State private var haloPulse: Bool = false

    var body: some View {
        let w = width(for: phase)
        let h = height(for: phase)

        ZStack {
            // (1) Ambient outer halo — pulses subtly, colored by phase.
            Capsule()
                .fill(haloColor.opacity(phase == .dormant ? 0 : 0.50))
                .frame(width: w + 70, height: h + 60)
                .blur(radius: 28)
                .scaleEffect(haloPulse ? 1.04 : 0.96)
                .animation(
                    .easeInOut(duration: 1.7).repeatForever(autoreverses: true),
                    value: haloPulse
                )

            // (2) Body capsule — deep black with layered glass overlays.
            ZStack {
                Capsule().fill(.black)
                bodyOverlays
                tideWave
                rim
            }
            .frame(width: w, height: h)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.75), radius: 22, x: 0, y: 14)
            .shadow(color: haloColor.opacity(0.55), radius: 30, x: 0, y: 0)

            // (3) Content layered on top of the glass.
            content
                .frame(width: w, height: h)
                .clipShape(Capsule())
        }
        .scaleEffect(phase == .dormant ? 0.55 : 1.0)
        .opacity(phase == .dormant ? 0 : 1)
        .contentShape(Capsule())
        .onTapGesture { onTap() }
        .allowsHitTesting(phase == .expanded || phase == .complete)
        .onAppear { haloPulse = true }
    }

    // MARK: layered visuals

    private var bodyOverlays: some View {
        ZStack {
            // Top sheen — the wet glass lip
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.22), location: 0.0),
                            .init(color: .white.opacity(0.05), location: 0.20),
                            .init(color: .clear,               location: 0.50),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .blendMode(.screen)

            // Inner caustic — warm refraction rising from below
            Capsule()
                .fill(
                    RadialGradient(
                        colors: [haloColor.opacity(0.22), .clear],
                        center: UnitPoint(x: 0.5, y: 1.10),
                        startRadius: 0, endRadius: 220
                    )
                )
                .blendMode(.plusLighter)
        }
    }

    private var rim: some View {
        Capsule().stroke(
            LinearGradient(
                colors: [.white.opacity(0.55), .white.opacity(0.05), .black.opacity(0.4)],
                startPoint: .top, endPoint: .bottom
            ),
            lineWidth: 1
        )
    }

    @ViewBuilder
    private var tideWave: some View {
        if let item, item.kind == .file, item.progress < 1.0, phase == .expanded {
            TideWaveView(progress: item.progress, tint: haloColor)
                .opacity(0.95)
        }
    }

    // MARK: content per phase

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .dormant:
            EmptyView()
        case .peeking:
            HStack(spacing: 9) {
                Circle()
                    .fill(Palette.lagoonBlue)
                    .frame(width: 8, height: 8)
                    .shadow(color: Palette.lagoonBlue, radius: 4)
                Text("Incoming")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.silkCream)
                    .tracking(0.5)
            }
            .transition(.opacity)
        case .expanded:
            if let item {
                HStack(spacing: 12) {
                    iconBubble(for: item)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.silkCream)
                            .lineLimit(1)
                        Text(subtitle(for: item))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.silkCream.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    trailing(for: item)
                }
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        case .complete:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.lagoonBlue)
                    .shadow(color: Palette.lagoonBlue, radius: 8)
                Text("Landed")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.silkCream)
                    .tracking(0.5)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func iconBubble(for item: TransferItem) -> some View {
        ZStack {
            Circle()
                .fill(Palette.cacao)
                .frame(width: 50, height: 50)
            Circle()
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
                .frame(width: 50, height: 50)
            if let data = item.iconPNG, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
            } else if item.kind == .url {
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Palette.spicedOrange)
            } else {
                Image(systemName: "doc.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.silkCream.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private func trailing(for item: TransferItem) -> some View {
        if item.kind == .file, item.progress < 1.0 {
            GlassProgressRing(progress: item.progress, diameter: 38)
        } else {
            Image(systemName: "hand.tap")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.lagoonBlue.opacity(0.95))
                .padding(.trailing, 4)
        }
    }

    private func subtitle(for item: TransferItem) -> String {
        switch item.kind {
        case .url:
            return item.urlString ?? "Link"
        case .file:
            if item.progress < 1.0 {
                return "\(item.formattedSize) · \(Int(item.progress * 100))%"
            }
            return "\(item.formattedSize) · tap to open on Mac"
        }
    }

    // MARK: sizing & color

    private func width(for p: DriftIslandPhase) -> CGFloat {
        switch p {
        case .dormant:  return 140
        case .peeking:  return 170
        case .expanded: return 340
        case .complete: return 220
        }
    }

    private func height(for p: DriftIslandPhase) -> CGFloat {
        switch p {
        case .dormant:  return 38
        case .peeking:  return 40
        case .expanded: return 82
        case .complete: return 50
        }
    }

    private var haloColor: Color {
        // Lagoon blue throughout — both in-transit and on completion. The
        // landed-state still reads as success because it pairs with the
        // checkmark icon and the brief shrink to the "Landed" pill.
        Palette.lagoonBlue
    }
}

// MARK: - Tide wave
//
// Animated sine-wave fill at the bottom of the island. The water level rises
// with file progress; two stacked sines give it an organic shimmer. Drawn
// procedurally via Canvas inside TimelineView so it stays smooth regardless
// of SwiftUI's re-render rate.

private struct TideWaveView: View {
    var progress: Double
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let level = size.height * CGFloat(1.0 - min(1.0, max(0.0, progress)))
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                let step: CGFloat = 3
                var x: CGFloat = 0
                while x <= size.width {
                    let phase1 = sin(Double(x) * 0.045 + t * 1.9) * 3.0
                    let phase2 = sin(Double(x) * 0.072 + t * 2.7) * 1.8
                    let y = level + CGFloat(phase1 + phase2)
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += step
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()

                ctx.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [tint.opacity(0.0), tint.opacity(0.55)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
        }
    }
}

#endif
