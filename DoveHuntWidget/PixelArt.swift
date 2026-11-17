//
//  PixelArt.swift
//  DoveHuntWidget
//
//  Sizes and helpers for the generated pixel art in Assets.xcassets/PixelArt.
//  Regenerate the art with `python3 -I Tools/generate_pixel_art.py`.
//

import SwiftUI
import WidgetKit

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

/// Every sprite in the asset catalog, with its native size in art pixels.
enum Sprite {
    case doveWingsUp
    case doveWingsDown
    case featherPoof
    case shotgunIdle
    case shotgunFire
    case digit(Character)

    var imageName: String {
        switch self {
        case .doveWingsUp: "dove_wings_up"
        case .doveWingsDown: "dove_wings_down"
        case .featherPoof: "feather_poof"
        case .shotgunIdle: "shotgun_idle"
        case .shotgunFire: "shotgun_fire"
        case .digit(let character): "digit_\(character)"
        }
    }

    var size: CGSize {
        switch self {
        case .doveWingsUp, .doveWingsDown, .featherPoof: CGSize(width: 16, height: 14)
        case .shotgunIdle, .shotgunFire: CGSize(width: 9, height: 24)
        case .digit: CGSize(width: 4, height: 6)
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
