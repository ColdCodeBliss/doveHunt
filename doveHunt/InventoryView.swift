//
//  InventoryView.swift
//  doveHunt
//
//  The Hunter's Quest inventory: a crate button in the top-right corner opens a pixel grid of
//  everything picked up on this run. Tap an item to read about it.
//

import SwiftUI

/// The top-right inventory button: a wooden crate, with a dot when there's something new.
struct InventoryButton: View {
    let itemCount: Int
    let hasNewItem: Bool
    let action: () -> Void

    var body: some View {
        Button(action: { action() }) {
            AppSprite(name: "crate_icon", size: AppArt.crate, scale: 2)
                .frame(width: 48, height: 48)
                .background(Color.pixelNavy, ignoresSafeAreaEdges: [])
                .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
                .background(Rectangle().fill(Color.pixelInk).offset(x: 3, y: 3))
                .overlay(alignment: .topTrailing) {
                    if hasNewItem {
                        Rectangle()
                            .fill(Color.pixelOrange)
                            .frame(width: 10, height: 10)
                            .overlay(Rectangle().strokeBorder(Color.pixelInk, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inventory")
        .accessibilityValue(itemCount == 1 ? "1 item" : "\(itemCount) items")
    }
}

/// The inventory panel: a grid of slots, and the selected item's description.
struct InventoryView: View {
    let items: [InventoryItem]
    let onClose: () -> Void

    @State private var selected: InventoryItem?

    init(items: [InventoryItem], selected: InventoryItem? = nil, onClose: @escaping () -> Void) {
        self.items = items
        self.onClose = onClose
        _selected = State(initialValue: selected)
    }
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private static let columns = 4
    private static let rows = 2
    private static let slotSize: CGFloat = 60
    private static let slotSpacing: CGFloat = 8
    /// Width of the description column (beside the grid on short screens, below it otherwise).
    private static let detailsWidth: CGFloat = 240

    var body: some View {
        // Short (landscape phone) screens put the description beside the grid so it all fits.
        let sideBySide = verticalSizeClass == .compact
        let gridWidth = CGFloat(Self.columns) * Self.slotSize + CGFloat(Self.columns - 1) * Self.slotSpacing
        let layout = sideBySide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PixelText("INVENTORY", pixelSize: 3, color: .pixelOrange)
                Spacer()
                Button {
                    onClose()
                } label: {
                    PixelText("X", pixelSize: 3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close inventory")
            }

            layout {
                grid
                details(width: sideBySide ? Self.detailsWidth : gridWidth)
            }
        }
        .padding(20)
        .fixedSize()
        .background(Color.pixelNavy, ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
        .background(Rectangle().fill(Color.pixelInk).offset(x: 4, y: 4))
    }

    private var grid: some View {
        Grid(horizontalSpacing: Self.slotSpacing, verticalSpacing: Self.slotSpacing) {
            ForEach(0..<Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<Self.columns, id: \.self) { column in
                        slot(index: row * Self.columns + column)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func slot(index: Int) -> some View {
        let size = Self.slotSize
        if items.indices.contains(index) {
            let item = items[index]
            let isSelected = selected == item
            Button {
                selected = item
            } label: {
                AppSprite(name: item.spriteName, size: item.spriteSize, scale: 3)
                    .frame(width: size, height: size)
                    .background(Color.pixelNavyLight, ignoresSafeAreaEdges: [])
                    .overlay(Rectangle().strokeBorder(isSelected ? Color.pixelOrange : Color.pixelCream, lineWidth: 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name.capitalized)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            Rectangle()
                .fill(Color.pixelInk.opacity(0.5))
                .frame(width: size, height: size)
                .overlay(Rectangle().strokeBorder(Color.pixelCream.opacity(0.35), lineWidth: 3))
                .accessibilityHidden(true)
        }
    }

    private func details(width: CGFloat) -> some View {
        let pixel: CGFloat = 2
        // Characters per line at this width (each glyph is 6 pixels wide, including spacing).
        let maxChars = max(10, Int(width / (6 * pixel)))
        return VStack(alignment: .leading, spacing: 3 * pixel) {
            if let selected {
                PixelText(selected.name, pixelSize: 3, color: .pixelOrange)
                    .padding(.bottom, 4)
                let lines = DialogText.wrap(selected.details, maxCharacters: maxChars)
                ForEach(lines.indices, id: \.self) { index in
                    PixelText(lines[index], pixelSize: pixel)
                }
            } else {
                let hint = items.isEmpty ? "Nothing here yet." : "Tap an item to inspect it."
                let lines = DialogText.wrap(hint, maxCharacters: maxChars)
                ForEach(lines.indices, id: \.self) { index in
                    PixelText(lines[index], pixelSize: pixel, color: .pixelCream.opacity(0.7))
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Inventory") {
    ZStack {
        Color.pixelInk.ignoresSafeArea()
        InventoryView(items: [.tackleBox], onClose: {})
    }
}
#endif
