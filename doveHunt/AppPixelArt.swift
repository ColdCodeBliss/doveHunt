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
    /// Height shared by every background variant.
    static let backgroundHeight: CGFloat = 196
    /// Background widths, one per screen shape: phone portrait, tablet/foldable portrait,
    /// open-Duo/iPad landscape, and phone landscape (see `APP_BACKGROUND_SIZES` in the generator).
    static let backgroundWidths: [CGFloat] = [90, 140, 280, 420]
    /// First row of the grass in the background art (the same in every variant).
    static let groundTop: CGFloat = 170

    /// The background whose shape is closest to the screen's, so as little as possible is cropped.
    static func background(for screen: CGSize) -> (name: String, size: CGSize) {
        let screenAspect = screen.width / max(screen.height, 1)
        let width = backgroundWidths.min { a, b in
            abs(log(a / backgroundHeight / screenAspect)) < abs(log(b / backgroundHeight / screenAspect))
        } ?? backgroundWidths[0]
        return ("app_background_\(Int(width))", CGSize(width: width, height: backgroundHeight))
    }
    static let hunter = CGSize(width: 38, height: 48)
    static let dove = CGSize(width: 16, height: 14)
    static let mallard = CGSize(width: 19, height: 14)
    static let pine = CGSize(width: 26, height: 50)
    static let mountains = CGSize(width: 120, height: 34)

    // Adventure sprites (see the "Adventure props" section of the generator).
    static let poof = CGSize(width: 16, height: 14)
    static let muzzleFlash = CGSize(width: 9, height: 5)
    static let tree = CGSize(width: 34, height: 46)
    static let bush = CGSize(width: 22, height: 11)
    static let cabin = CGSize(width: 70, height: 80)
    /// Horizontal center of the cabin's doorway, in cabin-sprite pixels (`CABIN_DOOR`).
    static let cabinDoorCenterX: CGFloat = 22
    /// Horizontal center of the hunter's body, in hunter-sprite pixels.
    static let hunterBodyCenterX: CGFloat = 13
    /// Where the muzzle flash sits relative to the hunter sprite's top-left corner (barrel tip).
    static let hunterMuzzle = CGPoint(x: 38, y: 6)
    /// Walk cycle frames, played at `Adventure.walkFrameRate`.
    static let hunterWalkCycle = ["hunter_walk_a", "hunter", "hunter_walk_b", "hunter"]
    /// Top-center of the cabin's chimney, in cabin-sprite pixels (where the chimney dove perches).
    static let cabinChimneyTop = CGPoint(x: 52, y: 2)

    // Cabin interior (see the "Cabin interior" section of the generator).
    static let interior = CGSize(width: 240, height: 130)
    /// Characters' feet line inside the cabin (`INTERIOR_FEET`).
    static let interiorFeet: CGFloat = 118
    /// The TV's screen, drawn live over the room art (`INTERIOR_TV_SCREEN`).
    static let interiorTVScreen = CGRect(x: 32, y: 69, width: 16, height: 16)
    /// Center of the kitchen's back door (`INTERIOR_BACK_DOOR`).
    static let interiorBackDoorCenterX: CGFloat = 224
    static let anna = CGSize(width: 26, height: 48)
    static let annaBodyCenterX: CGFloat = 12
    static let annaWalkCycle = ["anna_walk_a", "anna", "anna_walk_b", "anna"]

    // Pond scene (see the "Pond scene" section of the generator).
    static let pond = CGSize(width: 52, height: 15)
    static let fishingRod = CGSize(width: 34, height: 30)
    /// Rod grip and tip, in rod-sprite pixels (drawn facing right).
    static let rodGrip = CGPoint(x: 1, y: 28)
    static let rodTip = CGPoint(x: 32, y: 1)
    // Compact versions for narrow screens (`POND_SMALL_SIZE`, `ROD_SHORT_SIZE`).
    static let pondSmall = CGSize(width: 34, height: 12)
    /// The wide-screen pond (landscape phones), reaching left from the fisherman's bank.
    static let pondLarge = CGSize(width: 88, height: 24)
    static let fishingRodShort = CGSize(width: 20, height: 22)
    static let rodShortGrip = CGPoint(x: 1, y: 20)
    static let rodShortTip = CGPoint(x: 18, y: 1)
    static let fisherman = CGSize(width: 28, height: 48)
    /// The fisherman's hand (holding the rod) in his standing sprite, facing right.
    static let fishermanHand = CGPoint(x: 21, y: 22)
    static let fishermanBodyCenterX: CGFloat = 13
    static let fishermanRunCycle = ["fisherman_run_a", "fisherman", "fisherman_run_b", "fisherman"]
    static let dog = CGSize(width: 30, height: 24)
    static let dogRunCycle = ["dog_run_a", "dog_stand", "dog_run_b", "dog_stand"]
    /// Max's collar in his standing sprite, mirrored to face left (where the leash clips on).
    static let dogCollarFacingLeft = CGPoint(x: 6, y: 10)
    /// The fisherman's tackle box (dropped in scene 8, then kept in the inventory).
    static let tackleBox = CGSize(width: 16, height: 12)
    /// The bobbing "tap this" arrow.
    static let arrowDown = CGSize(width: 9, height: 10)
    /// The inventory button's crate.
    static let crate = CGSize(width: 16, height: 16)
    static let poopDrop = CGSize(width: 3, height: 4)
    static let poopSplat = CGSize(width: 6, height: 5)
    /// The bear reared up on its hind legs, and on all fours (`bear_four`, `bear_roar`, `bear_run_a/b`).
    static let bearStanding = CGSize(width: 36, height: 58)
    static let bearFour = CGSize(width: 54, height: 32)
    static let bearRunCycle = ["bear_run_a", "bear_four", "bear_run_b", "bear_four"]
    /// The doe and her fawn (`deer_*` / `fawn_*`: drink, stand, a, b).
    static let deer = CGSize(width: 44, height: 40)
    static let fawn = CGSize(width: 30, height: 28)
    static let mallardFloat = CGSize(width: 19, height: 9)
    static let stream = CGSize(width: 150, height: 18)
    /// The chain-link fence (`fence_closed` / `fence_open`); its gate is the leftmost 26 px.
    static let fence = CGSize(width: 98, height: 40)
    /// The lone mountain behind the restricted gate; its dirt trail starts at `farMountainTrailX`.
    static let farMountain = CGSize(width: 130, height: 76)
    static let farMountainTrailX: CGFloat = 14
    static let fenceGateWidth: CGFloat = 26
    /// Where the padlock hangs on the gate's latch side (fence pixels).
    static let fenceLock = CGPoint(x: 5, y: 21)
    static let padlock = CGSize(width: 9, height: 10)
    static let alienLogo = CGSize(width: 9, height: 9)
    static let signPost = CGSize(width: 4, height: 34)
    static let rv = CGSize(width: 76, height: 40)
    static let campfire = CGSize(width: 16, height: 15)
    /// Campers in camp chairs, facing right, roasting stick held out to the right.
    static let camperDad = CGSize(width: 39, height: 33)
    static let camperKid = CGSize(width: 28, height: 24)
    static let arrowRight = CGSize(width: 11, height: 9)
    /// The flying saucer (`ufo_a` / `ufo_b`, rim lights alternate) and one tractor-beam ring.
    static let ufo = CGSize(width: 40, height: 18)
    static let beamRing = CGSize(width: 24, height: 6)
    /// One tile of the restricted route's dirt trail.
    static let dirtPath = CGSize(width: 64, height: 10)
    /// Aboard the UFO: an alien (faces right; `alien_walk_a/b`), the lab table, and the shotgun lying flat.
    static let alien = CGSize(width: 22, height: 36)
    static let metalTable = CGSize(width: 46, height: 22)
    static let shotgunItem = CGSize(width: 36, height: 7)
    /// One puff of the hunter's, er, gas.
    static let gasPuff = CGSize(width: 14, height: 10)
    /// The seat of the hunter's pants in his sprite (facing right), where the gas comes out.
    static let hunterRear = CGPoint(x: 6, y: 31)
    /// The specimen-vat lab: a vat (`vat_back` / `vat_front` / `vat_broken`), the risen bird
    /// skeletons (`skeleton_dove*`, `skeleton_mallard*`), the scientist alien, and his clipboard.
    static let vat = CGSize(width: 26, height: 48)
    static let skeletonDove = CGSize(width: 18, height: 24)
    static let skeletonMallard = CGSize(width: 22, height: 30)
    static let clipboard = CGSize(width: 12, height: 15)
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
        "(": ["...#.", "..#..", ".#...", ".#...", ".#...", "..#..", "...#."],
        ")": [".#...", "..#..", "...#.", "...#.", "...#.", "..#..", ".#..."],
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
            .background(fill, ignoresSafeAreaEdges: [])
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
            .background(fill, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .background(Rectangle().fill(Color.pixelInk).offset(x: 3, y: 3))
            .contentShape(Rectangle())
    }
}
