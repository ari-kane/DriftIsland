//
//  IslandScene.swift
//  iOS-only. Landscape-locked "connected" scene. A capsule-shaped island
//  floats in a bird's-eye-view ocean. Files arrive as glass beads.
//
//  Bead gestures:
//    * Drag within the island  → rearrange (position persists)
//    * Drag into the water     → open on Mac + remove from the island
//    * Double-tap              → remove only (no open)
//
//  Bead positions are stable per item (hash of UUID), so removing one
//  bead doesn't shuffle the rest.
//
//  Bird's-eye realism:
//    * Sand body is procedural granular texture, no gradient.
//    * Ocean uses drifting tonal patches + twinkling sun glints.
//    * Small emoji decorations (palm trees, starfish, shell) sprinkle
//      character onto the island. Palms gently sway in the breeze.
//

#if os(iOS)

import SwiftUI
import UIKit

// MARK: - Scene

struct IslandScene: View {
    @EnvironmentObject var session: PairingSession

    var body: some View {
        GeometryReader { geo in
            sceneBody(geo: geo)
        }
        // Smooth in/out for the toast notification.
        .animation(.spring(response: 0.35, dampingFraction: 0.85),
                   value: session.toastText)
    }

    @ViewBuilder
    private func sceneBody(geo: GeometryProxy) -> some View {
        Group {
            let islandSize = CGSize(
                width: geo.size.width * 0.954,    // 6% larger than 0.90
                height: geo.size.height * 0.6625  // 6% larger than 0.625
            )
            let islandCenter = CGPoint(
                x: geo.size.width / 2,
                y: geo.size.height / 2 + 6
            )

            ZStack {
                // (1) Ocean
                OceanBackground()
                    .ignoresSafeArea()

                // (1b) Turquoise shallows — irregular tinted area in the
                //      water immediately around the island. Several
                //      overlapping blurred ellipses, not a perfect ring.
                TurquoiseShallows(center: islandCenter, island: islandSize)

                // (2) Island — pill silhouette with sand texture
                IslandSurface(size: islandSize)
                    .position(islandCenter)

                // (3) Decorations — palms, starfish, shells
                DecorationsLayer(islandCenter: islandCenter, islandSize: islandSize)

                // (4) File beads
                let visible = Array(session.items.suffix(10))
                ForEach(visible, id: \.id) { item in
                    let pos = beadSpawnPosition(
                        for: item,
                        center: islandCenter,
                        island: islandSize
                    )
                    BeadView(
                        item: item,
                        spawnPosition: pos,
                        islandCenter: islandCenter,
                        islandSize: islandSize
                    )
                    .position(pos)
                }

                // (5) HUD
                hudLayer

                if session.items.isEmpty {
                    emptyHint.position(islandCenter)
                }

                // (6) Transient toast for clipboard copies, etc.
                if let toast = session.toastText {
                    ToastView(text: toast)
                        .padding(.bottom, 22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: HUD

    private var hudLayer: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kAppName)
                        .font(.system(size: 20, weight: .bold, design: .serif))
                        .foregroundStyle(Palette.silkCream)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    if let name = session.peerName {
                        Text("from \(name)")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Palette.silkCream.opacity(0.75))
                    }
                }
                Spacer()
                GlassStatusPill(label: "Connected", isConnected: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            Spacer()

            HStack {
                Spacer()
                Text("Shake to send your clipboard back")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.silkCream.opacity(0.55))
                    .tracking(1.2)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.bottom, 14)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 30))
                .foregroundStyle(Palette.lagoonBlue)
                .shadow(color: Palette.lagoonBlue.opacity(0.7), radius: 10)
            // Drift Island brand font — same serif design as the title.
            Text("Drop something on your Mac.")
                .font(.system(size: 15, weight: .semibold, design: .serif))
                .foregroundStyle(Palette.cacao.opacity(0.88))
            Text("It'll wash up here.")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(Palette.cacao.opacity(0.6))
        }
    }

    // MARK: bead positions
    //
    // Hash-based so each item has a stable spot for its entire lifetime —
    // removing one bead doesn't shuffle the others around the island.

    private func beadSpawnPosition(
        for item: TransferItem,
        center: CGPoint,
        island: CGSize
    ) -> CGPoint {
        let h = abs(item.id.uuidString.hashValue)
        let aBits = (h & 0xFFFF)
        let rBits = (h >> 16) & 0xFFFF
        let angle = Double(aBits) / Double(0xFFFF) * .pi * 2
        // sqrt for uniform area distribution within the disk.
        let radiusNorm = sqrt(Double(rBits) / Double(0xFFFF))
        let maxRadius = Double(island.width) * 0.20
        let radius = radiusNorm * maxRadius
        let raw = CGPoint(
            x: center.x + CGFloat(cos(angle) * radius),
            y: center.y + CGFloat(sin(angle) * radius * 0.32)
        )
        return clampInsidePill(raw, center: center, island: island)
    }

    private func clampInsidePill(
        _ p: CGPoint,
        center: CGPoint,
        island: CGSize
    ) -> CGPoint {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let rx = island.width * 0.42
        let ry = island.height * 0.35
        let d = sqrt((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry))
        if d > 1 {
            return CGPoint(x: center.x + dx / d, y: center.y + dy / d)
        }
        return p
    }
}

// MARK: - Ocean

private struct OceanBackground: View {
    var body: some View {
        ZStack {
            // Same darker-blue gradient as the pairing screens.
            LinearGradient(
                colors: [
                    Color(red: 0x05/255, green: 0x0F/255, blue: 0x1C/255),
                    Color(red: 0x0A/255, green: 0x25/255, blue: 0x40/255),
                    Color(red: 0x02/255, green: 0x08/255, blue: 0x10/255),
                ],
                startPoint: .top, endPoint: .bottom
            )

            // Slowly rotating water — an angular gradient with subtle
            // navy stops, heavily blurred so it reads as gentle shifting
            // colour rather than visible spokes. ~144s per revolution.
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                AngularGradient(
                    colors: [
                        Color.clear,
                        Color(red: 0x12/255, green: 0x40/255, blue: 0x60/255).opacity(0.45),
                        Color.clear,
                        Color(red: 0x10/255, green: 0x35/255, blue: 0x55/255).opacity(0.35),
                        Color.clear,
                        Color(red: 0x18/255, green: 0x48/255, blue: 0x68/255).opacity(0.30),
                        Color.clear,
                    ],
                    center: .center,
                    angle: .degrees(t * 2.5)
                )
                .blur(radius: 90)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }

            // Lagoon-blue ambient glow from the top, matching the login.
            RadialGradient(
                colors: [Palette.lagoonBlue.opacity(0.22), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
            .allowsHitTesting(false)
        }
    }
}

private struct WaterTexture: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { c, size in
                // Drifting tonal patches — big soft ovals that translate slowly.
                var rng = SeededGenerator(seed: 0xAABBCCDD)
                let patchCount = 40
                for i in 0..<patchCount {
                    let baseX = Double.random(in: -160...Double(size.width + 160), using: &rng)
                    let baseY = Double.random(in: 0...Double(size.height), using: &rng)
                    let r = Double.random(in: 110...220, using: &rng)
                    let drift = Double.random(in: 3.5...9.0, using: &rng)
                    let bright = Double.random(in: -0.10...0.10, using: &rng)
                    let phase = Double.random(in: 0...(.pi * 2), using: &rng)

                    let span = Double(size.width) + r * 2
                    var x = (baseX + t * drift).truncatingRemainder(dividingBy: span)
                    if x < -r { x += span }
                    let y = baseY + sin(t * 0.25 + phase + Double(i)) * 6

                    let alpha = max(0, 0.07 + bright * 0.5)
                    let tint: Color = bright >= 0
                        ? .white.opacity(alpha)
                        : .black.opacity(alpha * 0.6)
                    c.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r * 0.45)),
                        with: .color(tint)
                    )
                }

                // Sparse twinkling glints — sun on the water surface.
                var rng2 = SeededGenerator(seed: 0x11223344)
                let glintCount = 260
                for _ in 0..<glintCount {
                    let x = Double.random(in: 0...Double(size.width), using: &rng2)
                    let y = Double.random(in: 0...Double(size.height), using: &rng2)
                    let r = Double.random(in: 0.6...1.6, using: &rng2)
                    let twinkleOffset = Double.random(in: 0...(.pi * 2), using: &rng2)
                    let twinkleRate = Double.random(in: 1.0...2.2, using: &rng2)
                    let pulse = sin(t * twinkleRate + twinkleOffset) * 0.5 + 0.5
                    let alpha = pulse * 0.32

                    let depthFactor = 0.45 + min(1.0, y / Double(size.height)) * 0.7
                    c.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                        with: .color(.white.opacity(alpha * depthFactor))
                    )
                }
            }
            .blendMode(.plusLighter)
            .opacity(0.95)
        }
    }
}

// MARK: - Island surface

private struct IslandSurface: View {
    let size: CGSize

    var body: some View {
        // 7pt of shore on every side of the sand pill.
        let shoreSize = CGSize(width: size.width + 14, height: size.height + 14)
        // Capsule's implicit corner is height/2. Reduce by 6pt so the
        // ends read slightly squarer than a perfect pill.
        let cornerRadius = (size.height / 2) - 6

        ZStack {
            // Shore — medium-dark brown ring.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0x5B/255, green: 0x3D/255, blue: 0x24/255))
                .frame(width: shoreSize.width, height: shoreSize.height)

            // Sand — lighter, warm brown.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(red: 0x9D/255, green: 0x6E/255, blue: 0x45/255))
                .frame(width: size.width, height: size.height)

            // Sheen
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.30), location: 0.0),
                            .init(color: .white.opacity(0.04), location: 0.20),
                            .init(color: .clear,               location: 0.55),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .blendMode(.screen)
                .frame(width: size.width, height: size.height)

            // Outer rim
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.05), .black.opacity(0.30)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.4
                )
                .frame(width: size.width, height: size.height)
        }
    }
}

// MARK: - Decorations
//
// Tiny emoji decorations scattered around the edges of the island. Palms
// gently sway. All sized small so they read as background detail.

private struct DecorationsLayer: View {
    let islandCenter: CGPoint
    let islandSize: CGSize

    var body: some View {
        ZStack {
            // Asymmetric palm scatter — varied sizes, none mirroring
            // another's position, so the island doesn't read as a grid.
            SwayingPalm(size: 28, position: pos(-0.36, -0.24))   // upper-left, big
            SwayingPalm(size: 16, position: pos( 0.08, -0.34))   // upper-mid, small
            SwayingPalm(size: 22, position: pos(-0.18,  0.32))   // lower-mid-left
            SwayingPalm(size: 20, position: pos( 0.38,  0.14))   // mid-right cap area

            // Starfish: spread around different beach segments.
            StaticDecoration(emoji: "⭐", size: 12, position: pos(-0.44,  0.06))   // left cap
            StaticDecoration(emoji: "⭐", size: 11, position: pos( 0.26, -0.18))   // upper-right inside
            StaticDecoration(emoji: "⭐", size: 10, position: pos( 0.12,  0.38))   // lower-right beach

            // Shells: a couple along the beaches.
            StaticDecoration(emoji: "🐚", size: 13, position: pos(-0.10, -0.18))   // upper-left inside
            StaticDecoration(emoji: "🐚", size: 11, position: pos( 0.42, -0.10))   // right cap

            // Hibiscus on the lower-left beach.
            StaticDecoration(emoji: "🌺", size: 14, position: pos(-0.30,  0.20))
        }
    }

    private func pos(_ xFrac: CGFloat, _ yFrac: CGFloat) -> CGPoint {
        CGPoint(
            x: islandCenter.x + islandSize.width  * xFrac,
            y: islandCenter.y + islandSize.height * yFrac
        )
    }
}

private struct SwayingPalm: View {
    let size: CGFloat
    let position: CGPoint
    @State private var sway: CGFloat = 0

    var body: some View {
        Text("🌴")
            .font(.system(size: size))
            .rotationEffect(.degrees(Double(sway)), anchor: .bottom)
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1.5)
            .position(position)
            .onAppear {
                let amplitude: CGFloat = CGFloat.random(in: 1.8...3.2)
                let period:    Double  = Double.random(in: 3.6...5.4)
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    sway = amplitude
                }
            }
    }
}

private struct StaticDecoration: View {
    let emoji: String
    let size: CGFloat
    let position: CGPoint

    var body: some View {
        Text(emoji)
            .font(.system(size: size))
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
            .position(position)
    }
}

// MARK: - Bead
//
// Tint-free liquid glass orb. Persistent rearrange offset; toss into the
// water to open on Mac; double-tap to remove.

private struct BeadView: View {
    @EnvironmentObject var session: PairingSession
    let item: TransferItem
    let spawnPosition: CGPoint
    let islandCenter: CGPoint
    let islandSize: CGSize

    @State private var bob: CGFloat = 0
    @State private var entryProgress: CGFloat = 0
    @State private var savedOffset: CGSize = .zero
    @GestureState private var drag: CGSize = .zero
    @State private var thrown: Bool = false
    @State private var throwOffset: CGSize = .zero
    @State private var dismissed: Bool = false
    @State private var showCustomizer: Bool = false

    private let beadDiameter: CGFloat = 64
    private let beadCornerRadius: CGFloat = 28

    private var entryOffset: CGSize {
        let t = 1.0 - entryProgress
        let hash = abs(item.id.uuidString.hashValue)
        let angle = Double(hash % 360) * .pi / 180
        return CGSize(
            width:  CGFloat(cos(angle) * 280) * t,
            height: CGFloat(sin(angle) * 180) * t
        )
    }

    var body: some View {
        ZStack {
            iconView
            if item.kind == .file, item.progress < 1.0 {
                RoundedRectangle(cornerRadius: beadCornerRadius, style: .continuous)
                    .fill(.black.opacity(0.30))
                GlassProgressRing(progress: item.progress, diameter: 44)
            }
        }
        .frame(width: beadDiameter, height: beadDiameter)
        // Rounded-square (squircle) — same proportions as an iOS app icon.
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: beadCornerRadius, style: .continuous))
        .offset(thrown
            ? CGSize(width: savedOffset.width + throwOffset.width,
                     height: savedOffset.height + throwOffset.height)
            : CGSize(width: savedOffset.width + drag.width + entryOffset.width,
                     height: savedOffset.height + drag.height + entryOffset.height)
        )
        .offset(y: thrown || dismissed ? 0 : bob)
        .scaleEffect(thrown || dismissed ? 0.35 : (0.55 + entryProgress * 0.45))
        .opacity(thrown || dismissed ? 0 : Double(entryProgress))
        .gesture(
            DragGesture(minimumDistance: 5)
                .updating($drag) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in handleDragEnd(value) }
        )
        // Double-tap first so SwiftUI's recognizer can wait for the
        // second tap before falling through to the single-tap action.
        .onTapGesture(count: 2) { remove() }
        .onTapGesture(count: 1) { tap() }
        // Long-press → customizer sheet. `.onLongPressGesture` fires its
        // perform action the moment the threshold is reached.
        .onLongPressGesture(minimumDuration: 0.45) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showCustomizer = true
        }
        // Compact popover — not a full sheet.
        .popover(isPresented: $showCustomizer) {
            BeadCustomizer(item: item, isShowing: $showCustomizer)
                .environmentObject(session)
        }
        .onAppear {
            withAnimation(.spring(response: 1.05, dampingFraction: 0.80)) {
                entryProgress = 1.0
            }
            let period = Double.random(in: 2.0...2.8)
            let dist = CGFloat.random(in: 5...8)
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                bob = -dist
            }
        }
    }

    // MARK: icon

    @ViewBuilder
    private var iconView: some View {
        // A user-chosen SF Symbol (via long-press customizer) wins over
        // both the network-supplied iconPNG and the default per-kind glyph.
        if let symbol = session.customIcons[item.id] {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(session.customColors[item.id] ?? defaultIconColor)
                .shadow(color: (session.customColors[item.id] ?? defaultIconColor).opacity(0.65),
                        radius: 6)
        } else if let data = item.iconPNG, let ui = UIImage(data: data) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
        } else if item.kind == .url {
            Image(systemName: "link")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(session.customColors[item.id] ?? Palette.lagoonBlue)
                .shadow(color: (session.customColors[item.id] ?? Palette.lagoonBlue).opacity(0.7),
                        radius: 6)
        } else {
            Image(systemName: "doc.fill")
                .font(.system(size: 22))
                .foregroundStyle(session.customColors[item.id] ?? Palette.cacao.opacity(0.85))
        }
    }

    private var defaultIconColor: Color {
        item.kind == .url ? Palette.lagoonBlue : Palette.cacao.opacity(0.85)
    }

    // MARK: gestures

    private func handleDragEnd(_ value: DragGesture.Value) {
        let finalScreen = CGPoint(
            x: spawnPosition.x + savedOffset.width + value.translation.width,
            y: spawnPosition.y + savedOffset.height + value.translation.height
        )
        if isInsideIsland(finalScreen, grace: 12) {
            // Rearrange — persist offset, no animation needed since drag
            // resets to .zero in the same tick.
            savedOffset = CGSize(
                width:  savedOffset.width  + value.translation.width,
                height: savedOffset.height + value.translation.height
            )
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } else {
            tossOff(direction: value.translation)
        }
    }

    private func isInsideIsland(_ point: CGPoint, grace: CGFloat) -> Bool {
        let dx = point.x - islandCenter.x
        let dy = point.y - islandCenter.y
        let halfH = islandSize.height / 2 + grace
        let straightHalfW = max(0, (islandSize.width - islandSize.height) / 2)
        if abs(dx) <= straightHalfW {
            return abs(dy) <= halfH
        }
        let capCenterX: CGFloat = dx > 0 ? straightHalfW : -straightHalfW
        let localDX = dx - capCenterX
        return (localDX * localDX + dy * dy) <= (halfH * halfH)
    }

    private func tossOff(direction: CGSize) {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        // Persist the final drag position so the toss animates from where
        // the user let go, not from the bead's pre-drag spot.
        savedOffset = CGSize(
            width:  savedOffset.width  + direction.width,
            height: savedOffset.height + direction.height
        )
        withAnimation(.easeIn(duration: 0.55)) {
            thrown = true
            throwOffset = CGSize(width: direction.width * 3, height: direction.height * 3)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            openOnPhone()
            session.removeItem(item.id)
        }
    }

    /// Drag-off-island = open on the PHONE (not the Mac). For URL items
    /// with a scheme the phone can handle, opens in the phone's default
    /// app (Safari / Mail / a registered app). For anything else
    /// (file paths from the Mac, plain text, hex colours), falls back
    /// to copying the string to the phone's clipboard.
    private func openOnPhone() {
        let target = item.kind == .url ? item.urlString : item.macSourcePath
        guard let s = target else { return }

        if let url = URL(string: s),
           let scheme = url.scheme,
           !scheme.isEmpty,
           UIApplication.shared.canOpenURL(url)
        {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }

        UIPasteboard.general.string = s
        session.showToast("Copied to phone clipboard")
    }

    private func remove() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        withAnimation(.easeIn(duration: 0.35)) {
            dismissed = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            session.removeItem(item.id)
        }
    }

    private func tap() {
        let target = item.kind == .url ? item.urlString : item.macSourcePath
        guard let s = target else { return }
        session.requestOpen(s)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Predict whether this'll fall through to a clipboard copy on
        // the Mac — anything that isn't a real URL with a scheme will.
        if item.kind == .url {
            let hasScheme: Bool = {
                guard let url = URL(string: s),
                      let scheme = url.scheme,
                      !scheme.isEmpty
                else { return false }
                return true
            }()
            if !hasScheme {
                session.showToast("Copied to clipboard")
            }
        }
    }
}

// MARK: - Turquoise shallows
//
// Soft, irregular turquoise tint in the water immediately around the
// island. Built from several blurred, overlapping ellipses placed at
// asymmetric offsets so it reads as organic shallows rather than a
// uniform halo or perfect ring.

private struct TurquoiseShallows: View {
    let center: CGPoint
    let island: CGSize

    private let tint = Color(red: 0x4F/255, green: 0xCB/255, blue: 0xC2/255)

    var body: some View {
        ZStack {
            blob(dx: -0.34, dy: -0.10, sx: 0.55, sy: 0.70, alpha: 0.38)
            blob(dx:  0.36, dy:  0.05, sx: 0.50, sy: 0.65, alpha: 0.34)
            blob(dx: -0.04, dy: -0.34, sx: 0.65, sy: 0.50, alpha: 0.30)
            blob(dx: -0.18, dy:  0.36, sx: 0.55, sy: 0.45, alpha: 0.36)
            blob(dx:  0.22, dy: -0.30, sx: 0.45, sy: 0.40, alpha: 0.26)
            blob(dx:  0.10, dy:  0.32, sx: 0.40, sy: 0.50, alpha: 0.28)
        }
        .blur(radius: 26)
        .allowsHitTesting(false)
    }

    private func blob(dx: CGFloat, dy: CGFloat,
                      sx: CGFloat, sy: CGFloat,
                      alpha: Double) -> some View {
        Ellipse()
            .fill(tint.opacity(alpha))
            .frame(width: island.width * sx, height: island.height * sy)
            .position(
                x: center.x + island.width  * dx,
                y: center.y + island.height * dy
            )
    }
}

// MARK: - Toast

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.silkCream)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.black.opacity(0.62), in: Capsule())
            .overlay(
                Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
    }
}

// MARK: - Seeded RNG

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed | 1 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

#endif
