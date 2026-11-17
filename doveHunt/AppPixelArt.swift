//
//  AppPixelArt.swift
//  doveHunt
//
//  Pixel-art building blocks for the companion app: art sizes, sprites,
//  a 5x7 pixel font, and retro panel styling.
//  Regenerate the art with `python3 -I Tools/generate_pixel_art.py`.
//

import SwiftUI

// MARK: - Palette

extension Color {
    static let pixelCream = Color(red: 1.0, green: 0.965, blue: 0.835)
    static let pixelInk = Color(red: 0.149, green: 0.149, blue: 0.227)
    static let pixelNavy = Color(red: 0.078, green: 0.125, blue: 0.29)
    static let pixelNavyLight = Color(red: 0.13, green: 0.2, blue: 0.42)
    static let pixelOrange = Color(red: 0.95, green: 0.55, blue: 0.16)
}

// MARK: - Art sizes

/// Native sizes of the companion app art, in art pixels.
/// Keep in sync with Tools/generate_pixel_art.py.
enum AppArt {
    static let background = CGSize(width: 90, height: 196)
    /// First row of the grass in the background art.
    static let groundTop: CGFloat = 170
    static let hunter = CGSize(width: 38, height: 48)
    static let dove = CGSize(width: 16, height: 14)
}

/// An asset-catalog sprite scaled with nearest-neighbor sampling so pixels stay crisp.
struct AppSprite: View {
    let name: String
    let size: CGSize
    let scale: CGFloat

    var body: some View {
        Image(name)
            .resizable()
            .interpolation(.none)
            .frame(width: size.width * scale, height: size.height * scale)
            .accessibilityHidden(true)
    }
}

// MARK: - Pixel font

/// A 5x7 bitmap font. Unknown characters render as spaces.
enum PixelFont {
    static let glyphWidth = 5
    static let glyphHeight = 7

    static func glyph(for character: Character) -> [String] {
        glyphs[Character(character.uppercased())] ?? glyphs[" "]!
    }

    private static let glyphs: [Character: [String]] = [
        "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "B": ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
        "C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
        "D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        "E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        "F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
        "G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".####"],
        "H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        "I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "J": ["..###", "...#.", "...#.", "...#.", "#..#.", "#..#.", ".##.."],
        "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
        "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
        "M": ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
        "N": ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "Q": [".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"],
        "R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
        "S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
        "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        "U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "V": ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
        "W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."],
        "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
        "Y": ["#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."],
        "Z": ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
        "0": [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],
        "1": ["..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."],
        "2": [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
        "3": ["#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."],
        "4": ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
        "5": ["#####", "#....", "####.", "....#", "....#", "#...#", ".###."],
        "6": ["..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."],
        "7": ["#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."],
        "8": [".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."],
        "9": [".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        ".": [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
        ",": [".....", ".....", ".....", ".....", ".##..", "..#..", ".#..."],
        "!": ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
        "?": [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
        "-": [".....", ".....", ".....", "#####", ".....", ".....", "....."],
        ":": [".....", ".##..", ".##..", ".....", ".##..", ".##..", "....."],
        "/": ["....#", "...#.", "...#.", "..#..", ".#...", ".#...", "#...."],
        "'": ["..#..", "..#..", ".#...", ".....", ".....", ".....", "....."],
        "#": [".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#."],
        ">": [".#...", "..#..", "...#.", "....#", "...#.", "..#..", ".#..."],
        "<": ["...#.", "..#..", ".#...", "#....", ".#...", "..#..", "...#."],
    ]
}

/// Renders text in the 5x7 pixel font with a 1-pixel drop shadow.
/// The pixel size grows with Dynamic Type (capped so headings still fit).
struct PixelText: View {
    let text: String
    var pixelSize: CGFloat = 3
    var color: Color = .pixelCream
    var shadow: Color? = .pixelInk
    var scalesWithDynamicType = true

    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1

    init(
        _ text: String,
        pixelSize: CGFloat = 3,
        color: Color = .pixelCream,
        shadow: Color? = .pixelInk,
        scalesWithDynamicType: Bool = true
    ) {
        self.text = text
        self.pixelSize = pixelSize
        self.color = color
        self.shadow = shadow
        self.scalesWithDynamicType = scalesWithDynamicType
    }

    var body: some View {
        let pixel = (pixelSize * (scalesWithDynamicType ? min(typeScale, 1.5) : 1)).rounded()
        let glyphs = text.map(PixelFont.glyph(for:))
        let columns = max(0, glyphs.count * (PixelFont.glyphWidth + 1) - 1)

        Canvas { context, _ in
            let layers: [(Color, CGFloat)] = [shadow.map { ($0, pixel) }, (color, 0)].compactMap { $0 }
            for (layerColor, offset) in layers {
                var path = Path()
                for (index, glyph) in glyphs.enumerated() {
                    let originX = CGFloat(index * (PixelFont.glyphWidth + 1)) * pixel
                    for (row, line) in glyph.enumerated() {
                        for (column, mark) in line.enumerated() where mark == "#" {
                            path.addRect(CGRect(
                                x: originX + CGFloat(column) * pixel + offset,
                                y: CGFloat(row) * pixel + offset,
                                width: pixel,
                                height: pixel
                            ))
                        }
                    }
                }
                context.fill(path, with: .color(layerColor))
            }
        }
        .frame(width: CGFloat(columns + 1) * pixel, height: CGFloat(PixelFont.glyphHeight + 1) * pixel)
        .accessibilityElement()
        .accessibilityLabel(Text(text.capitalized))
    }
}

// MARK: - Retro panel styling

/// A square-cornered navy panel with a chunky cream border, like an old game menu.
struct PixelPanel: ViewModifier {
    var fill: Color = .pixelNavy

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
            .background(Rectangle().fill(Color.pixelInk).offset(x: 4, y: 4))
    }
}

extension View {
    func pixelPanel(fill: Color = .pixelNavy) -> some View {
        modifier(PixelPanel(fill: fill))
    }
}

/// Pressable pixel button: cream border, drops into its shadow when pressed.
struct PixelButtonStyle: ButtonStyle {
    var fill: Color = .pixelNavyLight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(fill)
            .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .background(Rectangle().fill(Color.pixelInk).offset(x: 3, y: 3))
            .contentShape(Rectangle())
    }
}
