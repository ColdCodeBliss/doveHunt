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
/// strip shows in the border above and below it.
struct NESShell: View {
    static let lidGrey = Color(red: 0.8, green: 0.8, blue: 0.79)
    static let frontGrey = Color(red: 0.47, green: 0.47, blue: 0.49)
    static let seam = Color(red: 0.33, green: 0.33, blue: 0.35)
    static let strip = Color(red: 0.12, green: 0.12, blue: 0.13)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Self.lidGrey
                    Self.seam.frame(height: 2)
                    Self.frontGrey
                }
                Self.strip
                    .frame(width: size.width * 0.08)
                    .offset(x: size.width * 0.8)
            }
        }
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
