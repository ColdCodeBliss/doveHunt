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
    /// Center of the dove's flight loop, in art pixels.
    let center: CGPoint
    /// Half-width and half-height of the loop, in art pixels.
    let amplitude: CGSize
    /// Angular speed along each axis, in radians per flight frame (see `Flight.frameInterval`).
    let frequency: CGSize
    /// Offsets this dove's path and wing beat so the flock doesn't move in lockstep.
    let phase: Double
    let wingsUp: Bool

    /// Where the dove is at a given flight frame: a Lissajous loop that sweeps the sky.
    /// Snapped to whole art pixels so every resting frame sits on the pixel grid.
    func position(atTick tick: Int) -> CGPoint {
        let t = Double(tick)
        return CGPoint(
            x: (center.x + amplitude.width * sin(frequency.width * t + phase)).rounded(),
            y: (center.y + amplitude.height * sin(frequency.height * t + phase * 1.7)).rounded()
        )
    }

    /// Doves face the way they're flying.
    func facesRight(atTick tick: Int) -> Bool {
        cos(frequency.width * Double(tick) + phase) >= 0
    }
}

/// Precomputed flight frames. Widgets can't run a live animation loop, so the timeline
/// carries a run of frames on a fixed wall-clock grid. Each frame moves every dove along
/// its flight path (animated smoothly between frames) and alternates its wings.
enum Flight {
    /// Time between flight frames (one wing beat per frame). Matched to how often the Home
    /// Screen actually redraws a widget (measured at ~1.4–1.8 s on the simulator): shorter
    /// frames get skipped, which made doves glide briefly then freeze. Each frame's linear
    /// glide lasts the whole interval, so movement stays continuous.
    static let frameInterval: TimeInterval = 1.5
    /// How long the flock keeps flying after each refresh or shot before coming to rest.
    static let duration: TimeInterval = 30

    static var frameCount: Int { Int(duration / frameInterval) }

    static func wingsUp(_ dove: Dove, tick: Int) -> Bool {
        dove.wingsUp != tick.isMultiple(of: 2)
    }

    /// Base angular speed ranges (radians per second) for the horizontal and vertical sweeps.
    /// At Normal, a dove takes roughly 10–17 s to cross the sky and back.
    static let horizontalSpeed: ClosedRange<Double> = 0.18...0.32
    static let verticalSpeed: ClosedRange<Double> = 0.24...0.48

    /// Speed multiplier: the chosen difficulty, ramping up with each wave cleared in the current hunt.
    static func speed(wave: Int, difficulty: Difficulty) -> Double {
        let wavesThisHunt = max(0, wave - GameStore.huntStartWave)
        return difficulty.speedMultiplier * (1 + Double(min(wavesThisHunt, 20)) * 0.04)
    }
}

/// Maps time to the flight frame actually on screen. A timeline plays `frames` frames starting
/// at `baseTick` on `baseDate`, then the flock rests on the last one. The next timeline starts
/// from wherever this one is at that moment, so doves never jump, and a shot can be mapped to
/// the exact frame that was showing when it happened, which keeps the poof on the dove.
struct FlightClock: Codable {
    var baseTick: Int
    var baseDate: Date
    var frames: Int

    func tick(at date: Date) -> Int {
        let elapsed = Int((date.timeIntervalSince(baseDate) / Flight.frameInterval).rounded(.down))
        return baseTick + min(max(elapsed, 0), frames)
    }

    func date(forFrame frame: Int) -> Date {
        baseDate.addingTimeInterval(Double(frame) * Flight.frameInterval)
    }

    /// The clock for a new timeline, picking up exactly where `previous` is at `now`.
    ///
    /// While the flock is flying, the new clock keeps the previous frame schedule: it starts
    /// on the frame that's showing and the next frame lands when it was already due. Starting
    /// over at `now` instead would repeat the current frame for a full interval on every
    /// reload, so rapid shooting (one reload per tap) froze the doves in place.
    ///
    /// `shotTick` is the frame the player actually tapped. If the saved clock disagrees with
    /// it by more than a frame (WidgetKit built a timeline it never showed), trust the tap.
    static func continuing(_ previous: FlightClock, at now: Date, shotTick: Int?, frames: Int) -> FlightClock {
        let elapsed = Int((now.timeIntervalSince(previous.baseDate) / Flight.frameInterval).rounded(.down))
        let isFlying = elapsed >= 0 && elapsed < previous.frames
        var clock = isFlying
            ? FlightClock(baseTick: previous.baseTick + elapsed, baseDate: previous.date(forFrame: elapsed), frames: frames)
            : FlightClock(baseTick: previous.tick(at: now), baseDate: now, frames: frames)
        if let shotTick, abs(shotTick - clock.baseTick) > 1 {
            clock = FlightClock(baseTick: shotTick, baseDate: now, frames: frames)
        }
        return clock
    }

    /// Stored per widget size in the extension's own defaults. Only the timeline provider uses it.
    private static func key(for family: WidgetFamily) -> String { "flightClock-\(family)" }

    static func load(for family: WidgetFamily) -> FlightClock? {
        guard let data = UserDefaults.standard.data(forKey: key(for: family)) else { return nil }
        return try? JSONDecoder().decode(FlightClock.self, from: data)
    }

    func save(for family: WidgetFamily) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(for: family))
    }
}

/// Deterministic RNG so a given wave always produces the same flight paths.
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
    /// Gives each dove in a wave its own flight loop inside the sky.
    static func doves(wave: Int, family: WidgetFamily, difficulty: Difficulty = .normal) -> [Dove] {
        let spec = ArtSpec.forFamily(family)
        let sprite = Sprite.doveWingsUp.size
        // The sky band the dove's center can reach while staying fully on screen.
        let xBounds = (sprite.width / 2 + 1)...(spec.width - sprite.width / 2 - 1)
        let yBounds = (sprite.height / 2 + 1)...(spec.groundTop - sprite.height / 2 - 2)
        let halfWidth = (xBounds.upperBound - xBounds.lowerBound) / 2
        let halfHeight = (yBounds.upperBound - yBounds.lowerBound) / 2
        let speed = Flight.speed(wave: wave, difficulty: difficulty)

        var rng = SplitMix64(seed: UInt64(wave) &* 31 &+ UInt64(family.waveSize))
        let count = family.waveSize
        return (0..<count).map { index in
            let amplitude = CGSize(
                width: (halfWidth * CGFloat.random(in: 0.55...1, using: &rng)).rounded(),
                height: (halfHeight * CGFloat.random(in: 0.4...1, using: &rng)).rounded()
            )
            let center = CGPoint(
                x: CGFloat.random(in: (xBounds.lowerBound + amplitude.width)...(xBounds.upperBound - amplitude.width), using: &rng).rounded(),
                y: CGFloat.random(in: (yBounds.lowerBound + amplitude.height)...(yBounds.upperBound - amplitude.height), using: &rng).rounded()
            )
            return Dove(
                id: "\(wave)-\(index)",
                center: center,
                amplitude: amplitude,
                frequency: CGSize(
                    width: Double.random(in: Flight.horizontalSpeed, using: &rng) * speed * Flight.frameInterval,
                    height: Double.random(in: Flight.verticalSpeed, using: &rng) * speed * Flight.frameInterval
                ),
                // Evenly spaced phases (plus a little jitter) spread the flock out along
                // their loops so a new wave doesn't start bunched together.
                phase: Double(index) / Double(count) * 2 * .pi + Double.random(in: -0.4...0.4, using: &rng),
                wingsUp: index.isMultiple(of: 2)
            )
        }
    }

    /// Finds a dove by ID, even if it belongs to an earlier wave (used to place the poof).
    static func dove(id: String, family: WidgetFamily, difficulty: Difficulty) -> Dove? {
        guard let wave = id.split(separator: "-").first.flatMap({ Int($0) }) else { return nil }
        return doves(wave: wave, family: family, difficulty: difficulty).first { $0.id == id }
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
    /// The shotgun is mid-shot (hit or miss): show the muzzle flash and recoil.
    var firing: Bool = false
    /// Which way the shotgun points: toward the last shot for a moment, then back to front.
    var aim: GunAim = .front
    /// Flight frame to draw the doves at.
    var flightTick: Int = 0
    /// Flight frame at the moment of the hit, so the poof appears where the dove actually was.
    var poofTick: Int? = nil
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
        let tick = FlightClock.load(for: context.family)?.tick(at: .now) ?? 0
        return makeEntry(date: .now, tick: tick, configuration: configuration, family: context.family, shot: nil)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<DoveHuntEntry> {
        let now = Date.now
        let family = context.family
        var entries: [DoveHuntEntry] = []

        // Continue from the frame that is on screen right now (resting or mid-flight).
        let previous = FlightClock.load(for: family) ?? FlightClock(baseTick: 0, baseDate: now, frames: 0)
        let lastShot = GameStore.lastShot.flatMap { now.timeIntervalSince($0.date) < ShotTiming.freshShotWindow ? $0 : nil }
        let flight = lastShot == nil ? Flight.duration : ShotTiming.postShotFlight
        let clock = FlightClock.continuing(previous, at: now, shotTick: lastShot?.tick, frames: Int(flight / Flight.frameInterval))
        clock.save(for: family)

        // Flash the shot (muzzle flash, plus the poof on a hit), then clear it so the next tap
        // lands on a clean frame. The flash window is measured from the moment of the shot,
        // but always lasts at least `minimumOnScreen` past this reload: the tap -> intent ->
        // reload -> render round trip takes a few hundred milliseconds, and an entry that is
        // already stale by render time gets skipped, which made the poof invisible.
        // Each tap reloads the timeline, so rapid shots simply replace the previous flash.
        var shot: (flashEnd: Date, hitDoveID: String?, tick: Int)?
        var aim = GunAim.front
        var aimEnd = now
        if let last = lastShot {
            let flashEnd = max(
                last.date.addingTimeInterval(ShotTiming.flashDuration),
                now.addingTimeInterval(ShotTiming.minimumOnScreen)
            )
            // The frame that was showing when the trigger was pulled, from the previous timeline.
            let shotTick = last.tick ?? previous.tick(at: last.date)
            shot = (flashEnd, last.hitDoveID, shotTick)

            // Point the gun at the dove that was hit (where it was at that frame), or at the tapped spot.
            let target = last.hitDoveID
                .flatMap { WaveFactory.dove(id: $0, family: family, difficulty: configuration.difficulty) }
                .map { $0.position(atTick: shotTick) } ?? last.missTarget
            aim = GunAim.toward(target, spec: ArtSpec.forFamily(family))
            aimEnd = max(now.addingTimeInterval(ShotTiming.aimHold), flashEnd)
        }

        // A run of flight frames; the flock comes to rest on the last one.
        for frame in 0...clock.frames {
            let date = clock.date(forFrame: frame)
            let firing = shot.map { date < $0.flashEnd } ?? false
            entries.append(makeEntry(
                date: date, tick: clock.baseTick + frame, configuration: configuration, family: family,
                shot: firing ? shot : nil, aim: date < aimEnd ? aim : .front
            ))
        }
        // End the flash, and later swing the gun back to front, exactly on time even when
        // those moments fall between two flight frames.
        if let shot {
            for (moment, keepAim) in [(shot.flashEnd, shot.flashEnd < aimEnd), (aimEnd, false)]
            where moment > now && !entries.contains(where: { $0.date == moment }) {
                entries.append(makeEntry(
                    date: moment, tick: clock.tick(at: moment), configuration: configuration, family: family,
                    shot: nil, aim: keepAim ? aim : .front
                ))
            }
            entries.sort { $0.date < $1.date }
        }

        // After a shot's short run, reload right away for the full flight; otherwise idle refresh.
        let policy: TimelineReloadPolicy = lastShot == nil ? .after(now.addingTimeInterval(15 * 60)) : .atEnd
        return Timeline(entries: entries, policy: policy)
    }

    private func makeEntry(
        date: Date,
        tick: Int,
        configuration: ConfigurationAppIntent,
        family: WidgetFamily,
        shot: (flashEnd: Date, hitDoveID: String?, tick: Int)?,
        aim: GunAim = .front
    ) -> DoveHuntEntry {
        let downed = GameStore.shotDoveIDs
        let doves = WaveFactory.doves(wave: GameStore.wave, family: family, difficulty: configuration.difficulty)
            .filter { !downed.contains($0.id) }
        return DoveHuntEntry(
            date: date,
            configuration: configuration,
            score: GameStore.score,
            doves: doves,
            poofDoveID: shot?.hitDoveID,
            firing: shot != nil,
            aim: aim,
            flightTick: tick,
            poofTick: shot?.tick
        )
    }
}

// MARK: - Views

/// Timing for the shot feedback. Everything is kept short so taps can come in rapid succession.
enum ShotTiming {
    /// How long the muzzle flash and feather poof last, measured from the moment of the shot.
    static let flashDuration: TimeInterval = 0.5
    /// The flash always lasts at least this long past the start of the reload that shows it.
    /// WidgetKit renders every entry before delivering a timeline, so an entry that is already
    /// stale on delivery gets skipped; this headroom covers that render time.
    static let minimumOnScreen: TimeInterval = 0.7
    /// How long the poof takes to pop in, and later burst outward and fade.
    static let poofBurst: TimeInterval = 0.15
    /// Fade-in for a fresh wave of doves.
    static let waveFadeIn: TimeInterval = 0.15
    /// A shot counts as "just happened" if the timeline reloads within this window.
    static let freshShotWindow: TimeInterval = 1.5
    /// How long the shotgun stays pointed toward a shot before swinging back to front,
    /// measured from the start of the reload that shows it. Spans about two Home Screen
    /// redraws: aimed + firing, then aimed without the flash, then back to front.
    static let aimHold: TimeInterval = 2.5
    /// After a shot, the timeline only carries this much flight so it renders (and arrives)
    /// quickly; the next refresh restores the full `Flight.duration` run.
    static let postShotFlight: TimeInterval = 8
}

struct DoveHuntWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var contentMargins

    var body: some View {
        ZStack {
            // Covers the entire widget, console shell included, so any tap that misses a dove
            // fires the shotgun instead of falling through and opening the app. The label is
            // clear so the system's pressed highlight is invisible.
            Button(intent: MissShotIntent(target: nil, tick: entry.flightTick)) {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fire shotgun")

            if entry.configuration.consoleColor == .nes {
                NESDecorations()
            }

            screen
                .padding(contentMargins)
        }
    }

    /// The console screen: landscape, doves, poof, shotgun, and score.
    @ViewBuilder
    private var screen: some View {
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
                    .allowsHitTesting(false)

                missGrid(spec: spec, scale: scale, point: point)

                // Doves are drawn and hit-tested in two separate layers. The visual layer is
                // plain sprites, so WidgetKit can glide them between flight frames (interactive
                // buttons don't animate their position). The tap layer underneath is a set of
                // invisible buttons, each covering the whole stretch its dove travels during
                // the current frame, so a shot lands wherever the dove is mid-glide.
                doveTapTargets(spec: spec, scale: scale, point: point)

                ZStack {
                    ForEach(entry.doves) { dove in
                        let position = dove.position(atTick: entry.flightTick)
                        let facesRight = dove.facesRight(atTick: entry.flightTick)
                        PixelSprite(sprite: Flight.wingsUp(dove, tick: entry.flightTick) ? .doveWingsUp : .doveWingsDown, scale: scale)
                            // Wing beats and turns snap instantly, like sprite animation.
                            .contentTransition(.identity)
                            .scaleEffect(x: facesRight ? 1 : -1)
                            .animation(nil, value: facesRight)
                            .position(point(position.x, position.y))
                            // Glide smoothly from one flight frame to the next.
                            .animation(.linear(duration: Flight.frameInterval), value: entry.flightTick)
                            // A shot dove vanishes instantly (the poof takes its place);
                            // a new wave fades in quickly.
                            .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    }
                }
                .animation(.easeOut(duration: ShotTiming.waveFadeIn), value: entry.doves.map(\.id))
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                ZStack {
                    if let poofID = entry.poofDoveID,
                       let dove = WaveFactory.dove(id: poofID, family: family, difficulty: entry.configuration.difficulty) {
                        let position = dove.position(atTick: entry.poofTick ?? entry.flightTick)
                        PixelSprite(sprite: .featherPoof, scale: scale)
                            .position(point(position.x, position.y))
                            // Pops in on the hit frame, then bursts outward and fades.
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.5),
                                removal: .scale(scale: 1.6).combined(with: .opacity)
                            ))
                            .id(poofID)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: ShotTiming.poofBurst), value: entry.poofDoveID)

                shotgun(spec: spec, scale: scale, point: point)
                scorePlate(spec: spec, scale: scale, point: point)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.black, lineWidth: 3)
                .allowsHitTesting(false)
        )
    }

    /// The shotgun sits bottom-center, swings left or right toward the shot, and kicks down
    /// one (sprite) pixel when firing. It pivots on its stock, which never moves.
    private func shotgun(spec: ArtSpec, scale: CGFloat, point: (CGFloat, CGFloat) -> CGPoint) -> some View {
        let firing = entry.firing
        let multiplier = spec.gunMultiplier
        let sprite = Sprite.shotgun(aim: entry.aim, firing: firing)
        let uprightWidth = Sprite.shotgun(aim: .front, firing: false).size.width * multiplier
        let stockLeft = ((spec.width - uprightWidth) / 2).rounded(.down)
        let spriteLeft = stockLeft - sprite.stockOffset * multiplier
        let size = CGSize(width: sprite.size.width * multiplier, height: sprite.size.height * multiplier)
        let centerY = spec.height - size.height / 2 + (firing ? multiplier : 0)
        // No crossfade: the swing, flash, and recoil snap instantly, like sprite animation.
        return PixelSprite(sprite: sprite, scale: scale * multiplier)
            .contentTransition(.identity)
            .position(point(spriteLeft + size.width / 2, centerY))
            .animation(nil, value: sprite.imageName)
            .allowsHitTesting(false)
    }

    /// Invisible shoot buttons for the doves. Each one spans the dove's sprite at both the
    /// previous and the current flight frame (plus a little slack), covering the whole glide
    /// in between, and never moves itself.
    private func doveTapTargets(spec: ArtSpec, scale: CGFloat, point: @escaping (CGFloat, CGFloat) -> CGPoint) -> some View {
        let sprite = Sprite.doveWingsUp.size
        let slack: CGFloat = 3
        return ForEach(entry.doves) { dove in
            let from = dove.position(atTick: entry.flightTick - 1)
            let to = dove.position(atTick: entry.flightTick)
            let minX = min(from.x, to.x) - sprite.width / 2 - slack
            let maxX = max(from.x, to.x) + sprite.width / 2 + slack
            let minY = min(from.y, to.y) - sprite.height / 2 - slack
            let maxY = max(from.y, to.y) + sprite.height / 2 + slack
            Button(intent: ShootDoveIntent(doveID: dove.id, waveSize: family.waveSize, tick: entry.flightTick)) {
                Color.clear
                    .frame(width: (maxX - minX) * scale, height: (maxY - minY) * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(point((minX + maxX) / 2, (minY + maxY) / 2))
            .accessibilityLabel("Dove")
        }
    }

    /// Invisible grid of miss buttons over the screen. Each cell knows its own center, so a
    /// miss still tells the shotgun which way to aim. Doves sit on top and win their taps.
    /// Kept coarse (3 x 2) on purpose: the aim only has three directions, and every button
    /// is rendered into every timeline entry, so a fine grid slows down each reload.
    private func missGrid(spec: ArtSpec, scale: CGFloat, point: @escaping (CGFloat, CGFloat) -> CGPoint) -> some View {
        let columns = 3
        let rows = 2
        let cell = CGSize(width: spec.width / CGFloat(columns), height: spec.height / CGFloat(rows))
        return ForEach(0..<(columns * rows), id: \.self) { index in
            let center = CGPoint(
                x: (CGFloat(index % columns) + 0.5) * cell.width,
                y: (CGFloat(index / columns) + 0.5) * cell.height
            )
            Button(intent: MissShotIntent(target: center, tick: entry.flightTick)) {
                Color.clear
                    .frame(width: cell.width * scale, height: cell.height * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(point(center.x, center.y))
            .accessibilityHidden(true)
        }
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
                    .contentTransition(.identity)
            }
        }
        // Digits tick over instantly, arcade style.
        .animation(nil, value: entry.score)
        .frame(width: plateWidth * scale, height: plateHeight * scale)
        .background(Color.black.opacity(0.35))
        .position(point(spec.width - 1 - plateWidth / 2, 1 + plateHeight / 2))
        .allowsHitTesting(false)
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
                .containerBackground(for: .widget) {
                    entry.configuration.consoleColor.shell
                }
        }
        // The view applies the margins itself, so the miss button can cover the whole widget.
        .contentMarginsDisabled()
        .configurationDisplayName("Dove Hunt")
        .description("Tap the doves to bag them!")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension ConfigurationAppIntent {
    fileprivate static func with(_ landscape: Landscape, color: ConsoleColor = .nes) -> ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.landscape = landscape
        intent.consoleColor = color
        return intent
    }
}

#Preview("Small", as: .systemSmall) {
    DoveHuntWidget()
} timeline: {
    // Step through these to see the wing beats and gliding hops.
    for tick in 0..<6 {
        DoveHuntEntry(date: .now, configuration: .with(.meadow), score: 300, doves: WaveFactory.doves(wave: 0, family: .systemSmall), poofDoveID: nil, flightTick: tick)
    }
}

#Preview("Medium", as: .systemMedium) {
    DoveHuntWidget()
} timeline: {
    DoveHuntEntry(date: .now, configuration: .with(.nightWoods), score: 1200, doves: WaveFactory.doves(wave: 4, family: .systemMedium), poofDoveID: nil)
    DoveHuntEntry(date: .now, configuration: .with(.nightWoods), score: 1300, doves: Array(WaveFactory.doves(wave: 4, family: .systemMedium).dropFirst()), poofDoveID: "4-0", firing: true)
}

#Preview("Large", as: .systemLarge) {
    DoveHuntWidget()
} timeline: {
    DoveHuntEntry(date: .now, configuration: .with(.sunsetMarsh), score: 4500, doves: WaveFactory.doves(wave: 7, family: .systemLarge).filter { $0.id != "7-2" }, poofDoveID: "7-2", firing: true)
}

#Preview("Aim", as: .systemMedium) {
    DoveHuntWidget()
} timeline: {
    // Step through: aimed left (firing), straight ahead (firing), aimed right (firing), resting front.
    let doves = WaveFactory.doves(wave: 4, family: .systemMedium)
    DoveHuntEntry(date: .now, configuration: .with(.meadow), score: 800, doves: doves, poofDoveID: nil, firing: true, aim: .left)
    DoveHuntEntry(date: .now, configuration: .with(.meadow), score: 800, doves: doves, poofDoveID: nil, firing: true, aim: .front)
    DoveHuntEntry(date: .now, configuration: .with(.meadow), score: 800, doves: doves, poofDoveID: nil, firing: true, aim: .right)
    DoveHuntEntry(date: .now, configuration: .with(.meadow), score: 800, doves: doves, poofDoveID: nil, aim: .right)
}

#Preview("Aim Large", as: .systemLarge) {
    DoveHuntWidget()
} timeline: {
    DoveHuntEntry(date: .now, configuration: .with(.nightWoods), score: 2100, doves: WaveFactory.doves(wave: 9, family: .systemLarge), poofDoveID: nil, firing: true, aim: .left)
}

#Preview("Console Color", as: .systemMedium) {
    DoveHuntWidget()
} timeline: {
    let doves = WaveFactory.doves(wave: 2, family: .systemMedium)
    for color in [ConsoleColor.nes, .cherryRed, .limeGreen, .charcoal, .arcticWhite] {
        DoveHuntEntry(date: .now, configuration: .with(.meadow, color: color), score: 500, doves: doves, poofDoveID: nil)
    }
}
