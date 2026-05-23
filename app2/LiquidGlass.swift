//
//  LiquidGlass.swift
//  Heavy, skeuomorphic "Artisan Confectionery" Liquid Glass design system.
//
//  Everything visual lives in this one file so the dev can tweak the look
//  without touching networking or window plumbing.
//
//  The aesthetic: poured warm-brown glass with a wet, glossy top edge,
//  inner refraction near the bottom, a thick specular rim, and a soft
//  color-tinted ambient glow underneath. Every surface in the app should
//  feel like a hand-poured piece of confectionery glass.
//

import SwiftUI

// MARK: - Palette
//
// "Tide & Sand" — an island palette. Warm beige browns instead of dark
// cacao, sky-blue lagoon for active/success states instead of forest
// green, sandy orange-beige for highlights, coconut cream for text.
// All colors derive from the brief — change a hex, the whole app reskins.
enum Palette {
    /// #2A1F15 — Wet Sand. Primary canvas / mobile background.
    static let cacao            = Color(red: 0x2A/255, green: 0x1F/255, blue: 0x15/255)
    /// #5C4836 — Driftwood Beige. Container base under glass.
    static let roastedEarth     = Color(red: 0x5C/255, green: 0x48/255, blue: 0x36/255)
    /// #E3A874 — Spiced Sand. Active accents, selection rings, codes.
    static let spicedOrange     = Color(red: 0xE3/255, green: 0xA8/255, blue: 0x74/255)
    /// #5BA8D9 — Lagoon Sky. Success / active-connection sky blue.
    static let lagoonBlue       = Color(red: 0x5B/255, green: 0xA8/255, blue: 0xD9/255)
    /// #F7EFE9 — Coconut Cream. Readable text on dark glass.
    static let silkCream        = Color(red: 0xF7/255, green: 0xEF/255, blue: 0xE9/255)

    /// Background gradient used app-wide (wet sand -> deeper sand).
    static var canvasGradient: LinearGradient {
        LinearGradient(
            colors: [cacao, Color(red: 0x1C/255, green: 0x14/255, blue: 0x0C/255)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

// MARK: - Liquid Glass surface modifier
//
// Rendering trick stack (top to bottom):
//   1. A tinted RoundedRectangle base — gives the glass its "body color".
//   2. .ultraThinMaterial — picks up real blur of content behind.
//   3. A vertical LinearGradient (white -> clear -> dark) — fakes glass body
//      with light coming from above.
//   4. A top-anchored specular highlight (white -> clear) — the "wet" top edge.
//   5. A bottom radial refraction tint — colored caustic at the lower-inner
//      area, like light bending through poured glass.
//   6. A 2pt stroke using a top-lit gradient — the thick rim of the slab.
//   7. Two stacked drop shadows outside: a deep dark blur + a tinted
//      ambient glow.
//
// All numbers are tuned, not arbitrary. Tweak `tint` and `cornerRadius` from
// the call site; the rest is baked in for visual consistency.
struct LiquidGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 28
    var tint: Color = Palette.roastedEarth
    var glowTint: Color = Palette.spicedOrange
    var glowStrength: CGFloat = 0.35
    var depth: CGFloat = 1.0  // multiplier for shadow strength

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .background {
                ZStack {
                    // (1) tinted body — slightly darker than the requested tint
                    // for the underbelly so the highlights can pop on top.
                    shape.fill(tint.opacity(0.92))

                    // (2) real blur of whatever is behind the view
                    shape.fill(.ultraThinMaterial)

                    // (3) vertical body gradient — top is lit, bottom is in shade
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.22), location: 0.00),
                                .init(color: .white.opacity(0.06), location: 0.18),
                                .init(color: .clear,               location: 0.55),
                                .init(color: .black.opacity(0.22), location: 1.00),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    // (4) specular sheen at the top — the wet, glossy lip
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.55), location: 0.00),
                                .init(color: .white.opacity(0.10), location: 0.08),
                                .init(color: .clear,               location: 0.20),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .blendMode(.screen)
                    )

                    // (5) inner refraction — a soft warm caustic near the bottom
                    shape.fill(
                        RadialGradient(
                            colors: [glowTint.opacity(0.25), .clear],
                            center: UnitPoint(x: 0.5, y: 1.05),
                            startRadius: 0, endRadius: 220
                        )
                        .blendMode(.plusLighter)
                    )
                }
                .compositingGroup()
            }
            // (6) thick top-lit rim — the edge of the poured slab
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.85),
                            .white.opacity(0.15),
                            .black.opacity(0.35),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            }
            .clipShape(shape)
            // (7a) deep underneath shadow — gives the slab weight
            .shadow(color: .black.opacity(0.55 * depth), radius: 24 * depth, x: 0, y: 14 * depth)
            // (7b) tinted ambient glow — the color "bleeds" through the glass
            .shadow(color: glowTint.opacity(glowStrength), radius: 32 * depth, x: 0, y: 0)
    }
}

// MARK: - Liquid Glass key/button modifier
//
// For small interactive elements (keypad keys, action chips). Same idea as
// the surface, but rounder, more "bubble"-like with a stronger top sheen
// and an explicit pressed state. The dev can apply this anywhere.
struct LiquidGlassKey: ViewModifier {
    var tint: Color = Palette.roastedEarth
    var accent: Color = Palette.spicedOrange
    var isPressed: Bool = false
    var diameter: CGFloat = 78

    func body(content: Content) -> some View {
        let shape = Circle()

        return content
            .frame(width: diameter, height: diameter)
            .background {
                ZStack {
                    // (1) bubble body
                    shape.fill(tint)

                    // (2) bottom-half darkening — implies a curved underside
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear,               location: 0.45),
                                .init(color: .black.opacity(0.28), location: 1.00),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    // (3) glossy top-cap highlight — the dome of the bubble
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.65), location: 0.00),
                                .init(color: .white.opacity(0.10), location: 0.18),
                                .init(color: .clear,               location: 0.38),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .blendMode(.screen)
                    )

                    // (4) tiny specular spot — that single point of "wetness"
                    Circle()
                        .fill(.white.opacity(0.55))
                        .frame(width: diameter * 0.28, height: diameter * 0.12)
                        .blur(radius: 4)
                        .offset(y: -diameter * 0.30)
                        .blendMode(.screen)

                    // (5) accent halo when pressed
                    if isPressed {
                        shape.stroke(accent, lineWidth: 2)
                            .blur(radius: 0.5)
                    }
                }
                .compositingGroup()
            }
            // outer rim — top-lit
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.7), .white.opacity(0.05), .black.opacity(0.35)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
            }
            // press shrink + extra glow for tactile feedback
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .shadow(color: .black.opacity(0.5), radius: isPressed ? 6 : 12, x: 0, y: isPressed ? 3 : 8)
            .shadow(color: accent.opacity(isPressed ? 0.6 : 0.0), radius: 18, x: 0, y: 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: isPressed)
    }
}

// MARK: - Drop box glass (macOS drop activator)
//
// Horizontal capsule of poured glass that lives near the bottom-right
// corner of the screen. Dimmed at rest, ignites bright orange when a
// drag enters. Heavy top sheen + accent glow underneath sell the
// "wet candy" feel even at this tiny size.
struct LiquidDropBox: ViewModifier {
    var isActive: Bool
    var accent: Color = Palette.spicedOrange

    func body(content: Content) -> some View {
        let shape = Capsule()
        return content
            .background {
                ZStack {
                    // Body — warm brown, semi-translucent
                    shape.fill(Palette.roastedEarth.opacity(isActive ? 0.95 : 0.65))

                    // Top specular sheen — the wet glossy top of the pill
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(isActive ? 0.65 : 0.30), location: 0.00),
                                .init(color: .white.opacity(0.06),                   location: 0.45),
                                .init(color: .clear,                                  location: 0.85),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                        .blendMode(.screen)
                    )

                    // Active glow — warm orange-beige caustic from the bottom
                    shape.fill(
                        LinearGradient(
                            colors: [.clear, accent.opacity(isActive ? 0.45 : 0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .blendMode(.plusLighter)
                    )
                }
                .compositingGroup()
            }
            // Glossy rim
            .overlay {
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.85), .white.opacity(0.10), .black.opacity(0.45)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            // Soft ambient glow — radiates upward from the box when active
            .shadow(color: accent.opacity(isActive ? 0.75 : 0.30), radius: isActive ? 28 : 14, x: 0, y: -4)
            .animation(.easeInOut(duration: 0.22), value: isActive)
    }
}

// MARK: - View extension sugar
//
// Apply these like `.liquidGlassSurface()` so call sites stay readable.
extension View {
    func liquidGlassSurface(
        cornerRadius: CGFloat = 28,
        tint: Color = Palette.roastedEarth,
        glowTint: Color = Palette.spicedOrange,
        glowStrength: CGFloat = 0.35,
        depth: CGFloat = 1.0
    ) -> some View {
        modifier(LiquidGlassSurface(
            cornerRadius: cornerRadius,
            tint: tint,
            glowTint: glowTint,
            glowStrength: glowStrength,
            depth: depth
        ))
    }

    func liquidGlassKey(
        tint: Color = Palette.roastedEarth,
        accent: Color = Palette.spicedOrange,
        isPressed: Bool = false,
        diameter: CGFloat = 78
    ) -> some View {
        modifier(LiquidGlassKey(
            tint: tint, accent: accent, isPressed: isPressed, diameter: diameter
        ))
    }

    func liquidDropBox(isActive: Bool, accent: Color = Palette.spicedOrange) -> some View {
        modifier(LiquidDropBox(isActive: isActive, accent: accent))
    }
}

// MARK: - Reusable shared components
//
// A handful of components that show up in both Mac & iPhone UIs. Putting
// them here keeps the platform-specific view files focused on layout.

/// Big chunky brand title — uses the dynamic `kAppName` and looks like it's
/// etched into a sheet of warm glass.
struct GlassBrandTitle: View {
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            Text(kAppName)
                .font(.system(size: 38, weight: .bold, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Palette.silkCream, Palette.spicedOrange.opacity(0.9)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                .shadow(color: Palette.spicedOrange.opacity(0.35), radius: 18)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.silkCream.opacity(0.6))
                    .tracking(2)
                    .textCase(.uppercase)
            }
        }
    }
}

/// Tiny status pill — uses velvet-forest tint when connected, otherwise muted.
struct GlassStatusPill: View {
    var label: String
    var isConnected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Palette.spicedOrange : Palette.silkCream.opacity(0.4))
                .frame(width: 8, height: 8)
                .shadow(color: isConnected ? Palette.spicedOrange : .clear, radius: 6)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.silkCream.opacity(0.9))
                .tracking(1)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .liquidGlassSurface(
            cornerRadius: 999,
            tint: isConnected ? Palette.lagoonBlue : Palette.roastedEarth,
            glowTint: isConnected ? Palette.lagoonBlue : Palette.spicedOrange,
            glowStrength: isConnected ? 0.55 : 0.20,
            depth: 0.6
        )
    }
}

/// A circular progress ring carved into glass — used for file transfer progress.
struct GlassProgressRing: View {
    var progress: Double  // 0...1
    var diameter: CGFloat = 64

    var body: some View {
        ZStack {
            // Track — dark inset
            Circle()
                .stroke(.black.opacity(0.45), lineWidth: 6)
                .frame(width: diameter, height: diameter)

            // Progress arc — bright spiced-orange with glow
            Circle()
                .trim(from: 0, to: max(0.001, min(1.0, progress)))
                .stroke(
                    LinearGradient(
                        colors: [Palette.spicedOrange, Palette.silkCream],
                        startPoint: .top, endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .shadow(color: Palette.spicedOrange.opacity(0.7), radius: 8)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Palette.silkCream)
        }
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}
