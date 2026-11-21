//
//  PixelArt.swift
//  DoveHuntWidget
//
//  Sizes and helpers for the generated pixel art in Assets.xcassets/PixelArt.
//  Regenerate the art with `python3 -I Tools/generate_pixel_art.py`.
//

import SwiftUI
import WidgetKit

extension ConsoleColor {
    /// The fill for the handheld console shell around the screen.
    var shellColor: Color {
        switch self {
        case .classicBlue: Color(red: 0.2, green: 0.45, blue: 0.85)
        case .cherryRed: Color(red: 0.82, green: 0.18, blue: 0.2)
        case .limeGreen: Color(red: 0.42, green: 0.72, blue: 0.22)
        case .grapePurple: Color(red: 0.45, green: 0.28, blue: 0.7)
        case .sunnyYellow: Color(red: 0.96, green: 0.78, blue: 0.2)
        case .bubblegumPink: Color(red: 0.94, green: 0.5, blue: 0.68)
        case .tangerine: Color(red: 0.95, green: 0.52, blue: 0.16)
        case .tealWave: Color(red: 0.1, green: 0.6, blue: 0.62)
        case .charcoal: Color(red: 0.22, green: 0.23, blue: 0.27)
        case .arcticWhite: Color(red: 0.9, green: 0.91, blue: 0.93)
        case .nes: NESShell.lidGrey
        }
    }

    /// The console shell view. Most colors are a solid fill; NES is two-tone with a black strip.
    @ViewBuilder
    var shell: some View {
        switch self {
        case .nes: NESShell()
        default: shellColor
        }
    }
}

/// The original NES colorway: light grey lid on top, dark grey front below, and the black
/// strip on the right that runs down both halves. The screen covers the middle, so the
/// strip shows in the border above and below it. The lettering and buttons are drawn by
/// `NESDecorations` in the widget content, which knows the exact border sizes.
struct NESShell: View {
    nonisolated static let lidGrey = Color(red: 0.8, green: 0.8, blue: 0.79)
    nonisolated static let frontGrey = Color(red: 0.47, green: 0.47, blue: 0.49)
    nonisolated static let seam = Color(red: 0.33, green: 0.33, blue: 0.35)
    nonisolated static let strip = Color(red: 0.12, green: 0.12, blue: 0.13)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Self.lidGrey
                    Self.seam.frame(height: 2)
                    Self.frontGrey
                }
                Self.strip
                    .frame(width: proxy.size.width * 0.12)
                    .offset(x: proxy.size.width * 0.76)
            }
        }
    }
}

/// NES console details in the border: the red "ENTERTAINMENT SYSTEM" lettering on the lid
/// (top left, inset from the corner) and the POWER and RESET buttons on the front (bottom left).
/// Purely decorative, so it never takes taps away from the shotgun.
struct NESDecorations: View {
    nonisolated static let logoRed = Color(red: 0.78, green: 0.1, blue: 0.14)
    nonisolated static let keyGrey = Color(red: 0.6, green: 0.6, blue: 0.62)
    nonisolated static let keyHighlight = Color(red: 0.74, green: 0.74, blue: 0.76)
    nonisolated static let slotDark = Color(red: 0.2, green: 0.2, blue: 0.22)
    nonisolated static let powerLight = Color(red: 0.86, green: 0.12, blue: 0.12)
    /// The dark red used for the POWER and RESET labels on the real console.
    nonisolated static let labelRed = Color(red: 0.45, green: 0.06, blue: 0.08)

    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        let topBand = max(margins.top, 12)
        let bottomBand = max(margins.bottom, 12)
        let inset = max(margins.leading, 12) + 8

        GeometryReader { proxy in
        // The lettering stays clear of the black strip (which starts at 76% of the width).
        let lidSpace = proxy.size.width * 0.76 - inset - 6

        VStack(alignment: .leading, spacing: 0) {
            // Wide, slanted capitals like the NES lid logo; shrinks to fit on the small widget.
            Text("ENTERTAINMENT SYSTEM")
                .font(.system(size: min(topBand * 0.4, 7.5), weight: .heavy).width(.expanded).italic())
                .tracking(0.5)
                .foregroundStyle(Self.logoRed)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: lidSpace, alignment: .leading)
                .transformEffect(CGAffineTransform(a: 1, b: 0, c: -0.18, d: 1, tx: 0, ty: 0))
                .frame(height: topBand)
                .padding(.leading, inset)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                // The little square power light, lit red.
                Rectangle()
                    .fill(Self.powerLight)
                    .frame(width: 3, height: 3)
                    .overlay(Rectangle().stroke(Self.slotDark, lineWidth: 0.5))
                consoleButton("POWER", bandHeight: bottomBand)
                consoleButton("RESET", bandHeight: bottomBand)
            }
            .frame(height: bottomBand)
            .padding(.leading, inset - 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A wide grey key set into a dark recessed slot, with a light bevel along its top edge
    /// and a small dark red label, like the NES front panel.
    private func consoleButton(_ label: String, bandHeight: CGFloat) -> some View {
        let height = min(bandHeight * 0.6, 10.5)
        return Text(label)
            .font(.system(size: height * 0.46, weight: .heavy).width(.expanded))
            .foregroundStyle(Self.labelRed)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .frame(minWidth: height * 3.2, minHeight: height)
            .background(
                Self.keyGrey
                    .overlay(alignment: .top) { Self.keyHighlight.frame(height: 1) }
            )
            .padding(1.25)
            .background(Self.slotDark)
    }
}

/// Native resolution of the console screen art for each widget family, in art pixels.
/// Keep in sync with `SCREEN_SIZES` in Tools/generate_pixel_art.py.
struct ArtSpec {
    let width: CGFloat
    let height: CGFloat
    let suffix: String
    /// Whole-number upscale for the shotgun so it stays proportional on the tall large screen
    /// while still landing on the art-pixel grid.
    var gunMultiplier: CGFloat = 1

    /// First row of the ground, in art pixels (matches `ground_line()` in the generator).
    var groundTop: CGFloat { height - max(12, (height * 0.22).rounded()) }

    static func forFamily(_ family: WidgetFamily) -> ArtSpec {
        switch family {
        case .systemSmall: ArtSpec(width: 64, height: 64, suffix: "small")
        case .systemMedium: ArtSpec(width: 144, height: 60, suffix: "medium")
        default: ArtSpec(width: 144, height: 152, suffix: "large", gunMultiplier: 2)
        }
    }

    func landscapeImageName(_ landscape: Landscape) -> String {
        "\(landscape.rawValue)_\(suffix)"
    }
}

/// Which way the shotgun points.
enum GunAim: String, Hashable {
    case left
    case front
    case right

    /// Shots within this many degrees of straight up keep the gun facing front.
    static let frontTolerance: Double = 18

    /// The aim toward a target (in art pixels), measured from the gun's grip at bottom-center.
    static func toward(_ target: CGPoint?, spec: ArtSpec) -> GunAim {
        guard let target else { return .front }
        let grip = CGPoint(
            x: spec.width / 2,
            y: spec.height - Sprite.shotgun(aim: .front, firing: false).size.height * spec.gunMultiplier * 0.25
        )
        let degrees = atan2(target.x - grip.x, grip.y - target.y) * 180 / .pi
        if degrees > frontTolerance { return .right }
        if degrees < -frontTolerance { return .left }
        return .front
    }
}

/// Every sprite in the asset catalog, with its native size in art pixels.
enum Sprite {
    case doveWingsUp
    case doveWingsDown
    case featherPoof
    case shotgun(aim: GunAim, firing: Bool)
    case digit(Character)

    var imageName: String {
        switch self {
        case .doveWingsUp: "dove_wings_up"
        case .doveWingsDown: "dove_wings_down"
        case .featherPoof: "feather_poof"
        case .shotgun(let aim, let firing):
            aim == .front
                ? "shotgun_\(firing ? "fire" : "idle")"
                : "shotgun_\(aim.rawValue)_\(firing ? "fire" : "idle")"
        case .digit(let character): "digit_\(character)"
        }
    }

    var size: CGSize {
        switch self {
        case .doveWingsUp, .doveWingsDown, .featherPoof: CGSize(width: 16, height: 14)
        // Aimed guns are the upright sprite sheared sideways (see `shotgun_aimed` in the generator).
        case .shotgun(let aim, _): CGSize(width: aim == .front ? 9 : 21, height: 24)
        case .digit: CGSize(width: 4, height: 6)
        }
    }

    /// For shotguns: how far the stock's left edge sits from the sprite's left edge, in art pixels.
    /// Aligning on the stock keeps the gun planted at bottom-center whichever way it points.
    var stockOffset: CGFloat {
        switch self {
        case .shotgun(.left, _): size.width - 9
        default: 0
        }
    }
}

/// Draws a sprite scaled up with nearest-neighbor sampling so pixels stay crisp.
struct PixelSprite: View {
    let sprite: Sprite
    let scale: CGFloat

    var body: some View {
        Image(sprite.imageName)
            .resizable()
            .interpolation(.none)
            .widgetAccentedRenderingMode(.fullColor)
            .frame(width: sprite.size.width * scale, height: sprite.size.height * scale)
    }
}
