//
//  DoveHuntWidget.swift
//  DoveHuntWidget
//
//  Created by Ryan Bliss on 11/16/26.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Model

struct Dove: Identifiable, Hashable {
    let id: String
    /// Center of the sprite, in art pixels on the screen's pixel grid.
    let x: CGFloat
    let y: CGFloat
    let facesRight: Bool
    let wingsUp: Bool
}

/// Deterministic RNG so a given wave always lays out the same doves.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension WidgetFamily {
    var waveSize: Int {
        switch self {
        case .systemSmall: 2
        case .systemMedium: 3
        default: 5
        }
    }
}

enum WaveFactory {
    /// Lays out a wave of doves in the sky, keeping clear of the score plate,
    /// the shotgun, and each other.
    static func doves(wave: Int, family: WidgetFamily) -> [Dove] {
        let spec = ArtSpec.forFamily(family)
        let half = Sprite.doveWingsUp.size
        let xRange = (half.width / 2)...(spec.width - half.width / 2)
        let yRange = (half.height / 2 + 1)...(spec.groundTop - half.height / 2 - 2)
        let gunSize = Sprite.shotgunIdle.size
        // Includes the muzzle-flash rows so a dove never sits in the flash.
        let gunTop = spec.height - gunSize.height * spec.gunMultiplier - 2
        let gunHalfWidth = gunSize.width * spec.gunMultiplier / 2 + half.width / 2 + 2

        var rng = SplitMix64(seed: UInt64(wave) &* 31 &+ UInt64(family.waveSize))
        var doves: [Dove] = []

        for index in 0..<family.waveSize {
            var candidate = CGPoint(x: xRange.lowerBound, y: yRange.lowerBound)
            for _ in 0..<40 {
                candidate = CGPoint(
                    x: CGFloat.random(in: xRange, using: &rng).rounded(),
                    y: CGFloat.random(in: yRange, using: &rng).rounded()
                )
                let hitsScore = candidate.x > spec.width - 36 && candidate.y < 18
                let hitsGun = abs(candidate.x - spec.width / 2) < gunHalfWidth && candidate.y + half.height / 2 > gunTop
                let crowded = doves.contains { hypot($0.x - candidate.x, $0.y - candidate.y) < 18 }
                if !hitsScore && !hitsGun && !crowded { break }
            }
            doves.append(Dove(
                id: "\(wave)-\(index)",
                x: candidate.x,
                y: candidate.y,
                facesRight: Bool.random(using: &rng),
                wingsUp: Bool.random(using: &rng)
            ))
        }
        return doves
    }

    /// Finds a dove by ID, even if it belongs to an earlier wave (used to place the poof).
    static func dove(id: String, family: WidgetFamily) -> Dove? {
        guard let wave = id.split(separator: "-").first.flatMap({ Int($0) }) else { return nil }
        return doves(wave: wave, family: family).first { $0.id == id }
    }
}

// MARK: - Timeline

struct DoveHuntEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let score: Int
    let doves: [Dove]
    /// A dove that was just hit and should render as a feather poof.
    let poofDoveID: String?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DoveHuntEntry {
        DoveHuntEntry(
            date: .now,
            configuration: ConfigurationAppIntent(),
            score: 0,
            doves: WaveFactory.doves(wave: 0, family: context.family),
            poofDoveID: nil
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> DoveHuntEntry {
        makeEntry(date: .now, configuration: configuration, family: context.family, showPoof: false)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<DoveHuntEntry> {
        let now = Date.now
        var entries: [DoveHuntEntry] = []

        // Show the poof briefly right after a hit, then clear it.
        if let hit = GameStore.lastHit, now.timeIntervalSince(hit.date) < 2 {
            entries.append(makeEntry(date: now, configuration: configuration, family: context.family, showPoof: true))
            entries.append(makeEntry(date: now.addingTimeInterval(0.8), configuration: configuration, family: context.family, showPoof: false))
        } else {
            entries.append(makeEntry(date: now, configuration: configuration, family: context.family, showPoof: false))
        }

        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
    }

    private func makeEntry(date: Date, configuration: ConfigurationAppIntent, family: WidgetFamily, showPoof: Bool) -> DoveHuntEntry {
        let shot = GameStore.shotDoveIDs
        let doves = WaveFactory.doves(wave: GameStore.wave, family: family)
            .filter { !shot.contains($0.id) }
        return DoveHuntEntry(
            date: date,
            configuration: configuration,
            score: GameStore.score,
            doves: doves,
            poofDoveID: showPoof ? GameStore.lastHit?.doveID : nil
        )
    }
}

// MARK: - Views

struct DoveHuntWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let spec = ArtSpec.forFamily(family)

        GeometryReader { proxy in
            // One art pixel in points; the art fills the screen and the overflow is clipped.
            let scale = max(proxy.size.width / spec.width, proxy.size.height / spec.height)
            let origin = CGPoint(
                x: (proxy.size.width - spec.width * scale) / 2,
                y: (proxy.size.height - spec.height * scale) / 2
            )
            let point = { (x: CGFloat, y: CGFloat) in
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }

            ZStack {
                Image(spec.landscapeImageName(entry.configuration.landscape))
                    .resizable()
                    .interpolation(.none)
                    .widgetAccentedRenderingMode(.fullColor)
                    .frame(width: spec.width * scale, height: spec.height * scale)
                    .position(point(spec.width / 2, spec.height / 2))

                ForEach(entry.doves) { dove in
                    Button(intent: ShootDoveIntent(doveID: dove.id, waveSize: family.waveSize)) {
                        PixelSprite(sprite: dove.wingsUp ? .doveWingsUp : .doveWingsDown, scale: scale)
                            .scaleEffect(x: dove.facesRight ? 1 : -1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dove")
                    .position(point(dove.x, dove.y))
                }

                if let poofID = entry.poofDoveID, let dove = WaveFactory.dove(id: poofID, family: family) {
                    PixelSprite(sprite: .featherPoof, scale: scale)
                        .position(point(dove.x, dove.y))
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .id(poofID)
                }

                shotgun(spec: spec, scale: scale, point: point)
                scorePlate(spec: spec, scale: scale, point: point)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black, lineWidth: 3))
    }

    /// The shotgun sits bottom-center and kicks down one (sprite) pixel when firing.
    private func shotgun(spec: ArtSpec, scale: CGFloat, point: (CGFloat, CGFloat) -> CGPoint) -> some View {
        let firing = entry.poofDoveID != nil
        let multiplier = spec.gunMultiplier
        let size = CGSize(width: Sprite.shotgunIdle.size.width * multiplier, height: Sprite.shotgunIdle.size.height * multiplier)
        let left = ((spec.width - size.width) / 2).rounded(.down)
        let centerY = spec.height - size.height / 2 + (firing ? multiplier : 0)
        return PixelSprite(sprite: firing ? .shotgunFire : .shotgunIdle, scale: scale * multiplier)
            .position(point(left + size.width / 2, centerY))
            .allowsHitTesting(false)
    }

    /// Six-digit arcade score in the top-right corner, drawn with the pixel font.
    private func scorePlate(spec: ArtSpec, scale: CGFloat, point: (CGFloat, CGFloat) -> CGPoint) -> some View {
        let digits = Array(String(format: "%06d", min(entry.score, 999_999)))
        let digitSize = Sprite.digit("0").size
        let plateWidth = digitSize.width * CGFloat(digits.count) + 2
        let plateHeight = digitSize.height + 2

        return HStack(spacing: 0) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, character in
                PixelSprite(sprite: .digit(character), scale: scale)
            }
        }
        .frame(width: plateWidth * scale, height: plateHeight * scale)
        .background(Color.black.opacity(0.35))
        .position(point(spec.width - 1 - plateWidth / 2, 1 + plateHeight / 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(entry.score)")
    }
}

// MARK: - Widget

struct DoveHuntWidget: Widget {
    let kind: String = "DoveHuntWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            DoveHuntWidgetEntryView(entry: entry)
                // The blue "console" shell around the screen, like a mini handheld.
                .containerBackground(Color(red: 0.2, green: 0.45, blue: 0.85), for: .widget)
        }
        .configurationDisplayName("Dove Hunt")
        .description("Tap the doves to bag them!")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension ConfigurationAppIntent {
    fileprivate static func with(_ landscape: Landscape) -> ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.landscape = landscape
        return intent
    }
}

#Preview("Small", as: .systemSmall) {
    DoveHuntWidget()
} timeline: {
    DoveHuntEntry(date: .now, configuration: .with(.meadow), score: 300, doves: WaveFactory.doves(wave: 0, family: .systemSmall), poofDoveID: nil)
}

#Preview("Medium", as: .systemMedium) {
    DoveHuntWidget()
} timeline: {
    DoveHuntEntry(date: .now, configuration: .with(.nightWoods), score: 1200, doves: WaveFactory.doves(wave: 4, family: .systemMedium), poofDoveID: nil)
    DoveHuntEntry(date: .now, configuration: .with(.nightWoods), score: 1300, doves: Array(WaveFactory.doves(wave: 4, family: .systemMedium).dropFirst()), poofDoveID: "4-0")
}

#Preview("Large", as: .systemLarge) {
    DoveHuntWidget()
} timeline: {
    DoveHuntEntry(date: .now, configuration: .with(.sunsetMarsh), score: 4500, doves: WaveFactory.doves(wave: 7, family: .systemLarge).filter { $0.id != "7-2" }, poofDoveID: "7-2")
}
