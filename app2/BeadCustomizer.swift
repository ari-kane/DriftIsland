//
//  BeadCustomizer.swift
//  iOS-only. A landscape-oriented popover shown on long-press of a bead.
//  Wider than tall: a single row of 8 colour swatches and 16 SF Symbols
//  laid out in 2 rows of 8. Customisations are stored on PairingSession
//  per item.id — iPhone-local, never sent to the Mac.
//

#if os(iOS)

import SwiftUI
import UIKit

struct BeadCustomizer: View {
    @EnvironmentObject var session: PairingSession
    let item: TransferItem
    @Binding var isShowing: Bool

    private let palette: [Color] = [
        Palette.lagoonBlue,
        Palette.spicedOrange,
        .red,
        .pink,
        .purple,
        .green,
        .yellow,
        .white,
    ]

    private let symbols: [String] = [
        "doc.fill", "doc.text.fill", "photo.fill", "music.note",
        "video.fill", "link", "tag.fill", "bookmark.fill",
        "star.fill", "heart.fill", "leaf.fill", "flame.fill",
        "bolt.fill", "sparkles", "paperclip", "ticket.fill",
    ]

    // 8 columns so the icon grid is 2 rows of 8 — wide rather than tall.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Colour")
            HStack(spacing: 10) {
                ForEach(palette, id: \.self) { color in
                    swatch(color)
                }
            }

            sectionLabel("Icon")
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(symbols, id: \.self) { sym in
                    symbolButton(sym)
                }
            }

            HStack {
                Button(role: .destructive) {
                    session.customColors.removeValue(forKey: item.id)
                    session.customIcons.removeValue(forKey: item.id)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Text("Reset")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                Spacer()
                Button {
                    isShowing = false
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: 380)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func swatch(_ color: Color) -> some View {
        let isSelected = session.customColors[item.id] == color
        return Circle()
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.primary : Color.black.opacity(0.15),
                            lineWidth: isSelected ? 2 : 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .contentShape(Circle())
            .onTapGesture {
                session.customColors[item.id] = color
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }

    private func symbolButton(_ sym: String) -> some View {
        let isSelected = session.customIcons[item.id] == sym
        return Image(systemName: sym)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.15) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture {
                session.customIcons[item.id] = sym
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
    }
}

#endif
