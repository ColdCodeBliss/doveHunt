//
//  ConsoleView.swift
//  doveHunt
//
//  Aboard the UFO: the alien console mini game (Simon says on a 4x4 grid) and the saucer's
//  interior. Both are full-screen scenes drawn in chunky, pixel-snapped shapes.
//

import SwiftUI

// MARK: - Alien console

/// A full-screen alien computer: a monitor in the middle with a 4x4 grid that flashes a
/// sequence for the player to repeat, flanked by knobs, buttons, and blinking LEDs.
struct ConsoleView: View {
    let game: AdventureGame
    let screen: CGSize
    let now: Date
    var requiresLandscape = false

    private typealias Timing = AdventureGame.ConsoleTiming

    /// The colors a grid cell can flash.
    static let palette: [Color] = [
        Color(red: 0.36, green: 1.0, blue: 0.42),
        Color(red: 0.30, green: 0.90, blue: 1.0),
        Color(red: 1.0, green: 0.36, blue: 0.86),
        Color(red: 1.0, green: 0.90, blue: 0.30),
        Color(red: 1.0, green: 0.56, blue: 0.20),
    ]

    private static let screenGreen = Color(red: 0.36, green: 1.0, blue: 0.42)
    private static let alarmRed = Color(red: 1.0, green: 0.22, blue: 0.2)

    var body: some View {
        let console = game.console
        let elapsed = now.timeIntervalSince(console.stageStart)
        let t = now.timeIntervalSinceReferenceDate
        // One chunky "pixel" for the whole console, so everything snaps to the same grid.
        let px = max(2, (screen.height / 140).rounded())
        let monitorHeight = (screen.height * 0.74 / px).rounded() * px
        let headerHeight = px * 16
        let gap = px * 2
        // The monitor takes at most a little over half the width, leaving the side panels room
        // (on squarer screens, like the Duo's inner display, the height alone would make it too wide).
        let maxMonitorWidth = (screen.width * 0.56 / px).rounded(.down) * px
        let heightCell = ((monitorHeight - headerHeight - px * 12 - gap * 3) / 4 / px).rounded(.down) * px
        let widthCell = ((maxMonitorWidth - px * 12 - gap * 3) / 4 / px).rounded(.down) * px
        let cell = min(heightCell, widthCell)
        let gridSide = cell * 4 + gap * 3
        // Wide enough for the status line and its progress slots, with the grid centered.
        let monitorWidth = min(max(gridSide + px * 12, (gridSide * 1.45 / px).rounded() * px), maxMonitorWidth)
        let sideWidth = max(0, (screen.width - monitorWidth) / 2 - px * 10)
        // A jolt when the console locks down.
        let shake: CGFloat = console.stage == .lockdown && elapsed < 0.8 ? (sin(t * 70) * px * 1.5).rounded() : 0

        ZStack {
            metal(px: px)

            HStack(spacing: px * 6) {
                sidePanel(seed: 0, width: sideWidth, px: px, t: t, stage: console.stage)
                monitor(console: console, elapsed: elapsed, px: px, cell: cell, gap: gap,
                        width: monitorWidth, height: monitorHeight, headerHeight: headerHeight, t: t)
                sidePanel(seed: 1, width: sideWidth, px: px, t: t, stage: console.stage)
            }
            .offset(x: shake)

            Color.black
                .opacity(fade(stage: console.stage, elapsed: elapsed))
                .allowsHitTesting(false)
        }
        .frame(width: screen.width, height: screen.height)
    }

    /// Black over the console: fading in on boot, and out at the end of a lockdown or grant.
    private func fade(stage: ConsoleState.Stage, elapsed: TimeInterval) -> Double {
        switch stage {
        case .booting:
            return max(0, 1 - elapsed / Timing.fadeIn)
        case .lockdown:
            return min(max((elapsed - Timing.lockdown) / Timing.fade, 0), 1)
        case .granted:
            return min(max((elapsed - Timing.granted) / Timing.fade, 0), 1)
        default:
            return 0
        }
    }

    // MARK: Hull

    /// Brushed grey metal with panel seams and rivets.
    private func metal(px: CGFloat) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.62, green: 0.65, blue: 0.70), Color(red: 0.36, green: 0.39, blue: 0.44)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let rows = 4
            for row in 1..<rows {
                let y = (size.height * CGFloat(row) / CGFloat(rows) / px).rounded() * px
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: px)), with: .color(.black.opacity(0.35)))
                context.fill(Path(CGRect(x: 0, y: y + px, width: size.width, height: px)), with: .color(.white.opacity(0.18)))
                var x = px * 6
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y - px * 3, width: px * 2, height: px * 2)), with: .color(.black.opacity(0.3)))
                    context.fill(Path(CGRect(x: x, y: y + px * 3, width: px * 2, height: px * 2)), with: .color(.black.opacity(0.3)))
                    x += px * 40
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Monitor

    private func monitor(console: ConsoleState, elapsed: TimeInterval, px: CGFloat, cell: CGFloat, gap: CGFloat,
                         width: CGFloat, height: CGFloat, headerHeight: CGFloat, t: Double) -> some View {
        let wrongFlash = console.stage == .wrong && Int(elapsed * 8).isMultiple(of: 2)
        let correctFlash = console.stage == .correct && Int(elapsed * 8).isMultiple(of: 2)
        let borderColor: Color = wrongFlash ? Self.alarmRed : (correctFlash ? Self.screenGreen : Color(red: 0.12, green: 0.35, blue: 0.22))

        return ZStack {
            VStack(spacing: px * 3) {
                header(console: console, elapsed: elapsed, px: px, innerWidth: width - px * 12)
                    .frame(height: headerHeight - px * 3)
                grid(console: console, elapsed: elapsed, px: px, cell: cell, gap: gap)
            }
            .padding(px * 3)
            .frame(width: width - px * 6, height: height - px * 6)
            .background(Color(red: 0.02, green: 0.08, blue: 0.05), ignoresSafeAreaEdges: [])
            .overlay(scanlines(px: px))
            .overlay(Rectangle().strokeBorder(borderColor, lineWidth: px))

            // Big status text, sized so its longest word fits the screen.
            let bigPixel = max(2, min(px * 2, ((width - px * 14) / (8 * 6)).rounded(.down)))
            if console.stage == .lockdown {
                lockdownOverlay(elapsed: elapsed, px: px, textPixel: bigPixel)
                    .frame(width: width - px * 6, height: height - px * 6)
                    .clipped()
            } else if console.stage == .granted {
                grantedOverlay(elapsed: elapsed, px: px, textPixel: bigPixel)
                    .frame(width: width - px * 6, height: height - px * 6)
                    .clipped()
            }
        }
        .frame(width: width, height: height)
        .background(Color(red: 0.16, green: 0.18, blue: 0.22), ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(Color(red: 0.08, green: 0.09, blue: 0.11), lineWidth: px))
    }

    private func scanlines(px: CGFloat) -> some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: max(1, px / 2))), with: .color(.black.opacity(0.25)))
                y += px * 2
            }
        }
        .allowsHitTesting(false)
    }

    /// The status line, plus three slots for matched sequences and two for errors.
    private func header(console: ConsoleState, elapsed: TimeInterval, px: CGFloat, innerWidth: CGFloat) -> some View {
        let message: String
        var color = Self.screenGreen
        switch console.stage {
        case .booting: message = elapsed < 1 ? "INITIALIZING..." : "MATCH THE SEQUENCE"
        case .showing: message = "WATCH..."
        case .input: message = "YOUR TURN"
        case .correct: message = "CORRECT!"
        case .wrong:
            message = "ERROR"
            color = Self.alarmRed
        case .lockdown, .granted: message = ""
        }
        let blink = console.stage == .input && !Int(elapsed * 2).isMultiple(of: 2)
        // One text size for every message, small enough that the longest ("MATCH THE SEQUENCE")
        // fits across the screen. The progress slots sit on their own row underneath.
        let longest = CGFloat("MATCH THE SEQUENCE".count * 6)
        let textPixel = max(1, min(px - 1, (innerWidth / longest).rounded(.down)))
        return VStack(alignment: .leading, spacing: px) {
            PixelText(message, pixelSize: textPixel, color: color.opacity(blink ? 0.45 : 1), shadow: nil, scalesWithDynamicType: false)
            HStack(spacing: px * 2) {
            Spacer(minLength: 0)
            ForEach(0..<ConsoleState.toWin, id: \.self) { index in
                Rectangle()
                    .fill(index < console.correctCount ? Self.screenGreen : Color.clear)
                    .frame(width: px * 4, height: px * 4)
                    .overlay(Rectangle().strokeBorder(Self.screenGreen.opacity(0.7), lineWidth: max(1, px / 2)))
            }
            Rectangle().fill(Color.clear).frame(width: px * 2)
            ForEach(0..<ConsoleState.toLose, id: \.self) { index in
                Rectangle()
                    .fill(index < console.wrongCount ? Self.alarmRed : Color.clear)
                    .frame(width: px * 4, height: px * 4)
                    .overlay(Rectangle().strokeBorder(Self.alarmRed.opacity(0.7), lineWidth: max(1, px / 2)))
            }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message.capitalized). Matched \(console.correctCount) of \(ConsoleState.toWin). Errors \(console.wrongCount) of \(ConsoleState.toLose).")
    }

    private func grid(console: ConsoleState, elapsed: TimeInterval, px: CGFloat, cell: CGFloat, gap: CGFloat) -> some View {
        VStack(spacing: gap) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        let lit = litColor(cell: index, console: console, elapsed: elapsed)
                        Rectangle()
                            .fill(lit ?? Color(red: 0.05, green: 0.17, blue: 0.11))
                            .frame(width: cell, height: cell)
                            .overlay(Rectangle().strokeBorder(lit == nil ? Color(red: 0.12, green: 0.35, blue: 0.22) : Color.white.opacity(0.8), lineWidth: px))
                            .shadow(color: lit ?? .clear, radius: lit == nil ? 0 : px * 3)
                            .contentShape(Rectangle())
                            .onTapGesture { if !requiresLandscape { game.tapConsoleCell(index) } }
                            .accessibilityElement()
                            .accessibilityLabel("Row \(row + 1), column \(column + 1)")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { game.tapConsoleCell(index) }
                    }
                }
            }
        }
    }

    /// The color a cell is lit right now: a step of the playback, or the player's last tap.
    private func litColor(cell: Int, console: ConsoleState, elapsed: TimeInterval) -> Color? {
        switch console.stage {
        case .showing:
            let s = elapsed - 0.4
            guard s >= 0 else { return nil }
            let stepLength = Timing.stepOn + Timing.stepGap
            let step = Int(s / stepLength)
            guard step < console.sequence.count, s - Double(step) * stepLength < Timing.stepOn,
                  console.sequence[step] == cell else { return nil }
            return Self.palette[console.colors[step]]
        case .input, .correct, .wrong:
            guard let tap = console.lastTap, tap.cell == cell, now.timeIntervalSince(tap.date) < Timing.tapFlash else { return nil }
            return Self.palette[tap.color]
        default:
            return nil
        }
    }

    // MARK: Lockdown and access

    private func lockdownOverlay(elapsed: TimeInterval, px: CGFloat, textPixel: CGFloat) -> some View {
        let on = Int(elapsed * 4).isMultiple(of: 2)
        return VStack(spacing: px * 4) {
            hazardStripes(px: px)
            Spacer(minLength: 0)
            PixelText("SYSTEM", pixelSize: textPixel, color: .white, shadow: .black, scalesWithDynamicType: false)
            PixelText("LOCKDOWN", pixelSize: textPixel, color: .white, shadow: .black, scalesWithDynamicType: false)
            Spacer(minLength: 0)
            hazardStripes(px: px)
        }
        .background(Self.alarmRed.opacity(on ? 0.85 : 0.55), ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("System lockdown")
    }

    private func hazardStripes(px: CGFloat) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let stripe = px * 4
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + stripe, y: 0))
                path.addLine(to: CGPoint(x: x + stripe, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(Color(red: 1, green: 0.84, blue: 0.2)))
                x += stripe * 2
            }
        }
        .frame(height: px * 5)
    }

    private func grantedOverlay(elapsed: TimeInterval, px: CGFloat, textPixel: CGFloat) -> some View {
        let pulse = 0.55 + 0.3 * sin(elapsed * 8)
        return VStack(spacing: px * 4) {
            PixelText("ACCESS", pixelSize: textPixel, color: .white, shadow: .black, scalesWithDynamicType: false)
            PixelText("GRANTED", pixelSize: textPixel, color: .white, shadow: .black, scalesWithDynamicType: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.screenGreen.opacity(pulse), ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Access granted")
    }

    // MARK: Side panels

    /// Alien knobs, buttons, glyph labels, and blinking LEDs.
    private func sidePanel(seed: Int, width: CGFloat, px: CGFloat, t: Double, stage: ConsoleState.Stage) -> some View {
        let glyphs = seed == 0 ? ["ZX-7", "QV9", "K#2"] : ["TRX", "0101", "VQ-4"]
        let tick = Int(t * 3)
        // Glyph labels sized so the widest row (two labels side by side) stays inside the panel
        // with a margin, clear of the monitor's border.
        // Both panels use the widest pair ("0101" + "VQ-4") so their labels match in size.
        let pairChars = CGFloat(8 * 6)
        let labelPixel = max(1, min(max(1, px / 2) * 2, ((width - px * 10) / pairChars).rounded(.down)))
        return VStack(alignment: .center, spacing: px * 5) {
            // Two rows of LEDs, blinking at random (all red in a lockdown, all green when granted).
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: px * 2) {
                    ForEach(0..<6, id: \.self) { index in
                        let n = Self.noise(seed * 100 + row * 10 + index, tick)
                        let color = ledColor(n: n, stage: stage, t: t)
                        Rectangle()
                            .fill(color)
                            .frame(width: px * 3, height: px * 3)
                            .shadow(color: color, radius: n > 0.4 ? px * 1.5 : 0)
                    }
                }
            }
            HStack(spacing: px * 6) {
                ForEach(0..<2, id: \.self) { index in
                    knob(angle: Self.noise(seed * 7 + index, 0) * 360 + t * (index.isMultiple(of: 2) ? 25 : -18), px: px)
                }
            }
            PixelText(glyphs[0], pixelSize: labelPixel, color: Color(red: 0.55, green: 0.95, blue: 1).opacity(0.8), shadow: nil, scalesWithDynamicType: false)
            // A block of chunky push buttons; one pulses.
            Grid(horizontalSpacing: px * 2, verticalSpacing: px * 2) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple]
                            let pulse = index == (tick / 2 + seed) % 6
                            Rectangle()
                                .fill(colors[(index + seed * 2) % colors.count].opacity(pulse ? 1 : 0.6))
                                .frame(width: px * 6, height: px * 5)
                                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.5), lineWidth: max(1, px / 2)))
                        }
                    }
                }
            }
            HStack(spacing: px * 4) {
                ForEach(1..<3, id: \.self) { index in
                    PixelText(glyphs[index], pixelSize: labelPixel, color: Color(red: 0.55, green: 0.95, blue: 1).opacity(0.6), shadow: nil, scalesWithDynamicType: false)
                }
            }
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }

    private func ledColor(n: Double, stage: ConsoleState.Stage, t: Double) -> Color {
        switch stage {
        case .lockdown:
            return Int(t * 4).isMultiple(of: 2) ? Self.alarmRed : Self.alarmRed.opacity(0.25)
        case .granted:
            return Self.screenGreen
        default:
            let colors: [Color] = [Self.alarmRed, Self.screenGreen, Color(red: 1, green: 0.75, blue: 0.2), Color(red: 0.3, green: 0.9, blue: 1)]
            return n > 0.4 ? colors[Int(n * 97) % colors.count] : Color.black.opacity(0.45)
        }
    }

    private func knob(angle: Double, px: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.24, green: 0.26, blue: 0.30))
                .overlay(Circle().strokeBorder(Color(red: 0.75, green: 0.78, blue: 0.82), lineWidth: px))
            Rectangle()
                .fill(Color(red: 0.55, green: 0.95, blue: 1))
                .frame(width: px, height: px * 4)
                .offset(y: -px * 2.5)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: px * 12, height: px * 12)
    }

    /// A stable pseudo-random value in 0..<1.
    private static func noise(_ a: Int, _ b: Int) -> Double {
        let x = sin(Double(a) * 12.9898 + Double(b) * 78.233) * 43758.5453
        return x - x.rounded(.down)
    }
}

// MARK: - Aboard the UFO

/// Shared layout for the UFO's interior scenes: the pixel unit, the deck line, and helpers
/// for placing art-pixel sprites standing on the deck.
struct UFOInteriorLayout {
    let screen: CGSize
    /// Points per art pixel.
    let scale: CGFloat
    /// Screen y of the deck's top edge.
    let floorTop: CGFloat

    init(screen: CGSize) {
        self.screen = screen
        scale = max(2, (screen.height / 120).rounded())
        floorTop = (screen.height * 0.78).rounded()
    }

    /// The center of a sprite of `size` (art pixels) standing on the deck with its center at `x`.
    func standing(_ size: CGSize, x: CGFloat) -> CGPoint {
        CGPoint(x: x.rounded(), y: floorTop + 3 * scale - size.height * scale / 2)
    }

    /// The point just above the top of a standing sprite (for speech bubbles).
    func above(_ size: CGSize, x: CGFloat) -> CGPoint {
        CGPoint(x: x, y: floorTop + 3 * scale - size.height * scale - 4)
    }
}

/// Inside the saucer: purple-black bulkheads, round portholes onto twinkling stars, glowing
/// wall panels, and a deck with a glowing edge strip.
struct UFOInteriorBackground: View {
    let layout: UFOInteriorLayout
    let now: Date

    var body: some View {
        let clock = now.timeIntervalSinceReferenceDate
        let scale = layout.scale
        let floorTop = layout.floorTop
        let glow = 0.55 + 0.35 * sin(clock * 2)

        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.13, blue: 0.25), Color(red: 0.08, green: 0.07, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)

            Canvas { context, size in
                let ribs = 6
                for i in 0...ribs {
                    let x = (size.width * CGFloat(i) / CGFloat(ribs) / scale).rounded() * scale
                    context.fill(Path(CGRect(x: x - scale * 2, y: 0, width: scale * 4, height: floorTop)), with: .color(.black.opacity(0.35)))
                    context.fill(Path(CGRect(x: x - scale * 2, y: 0, width: scale, height: floorTop)), with: .color(.white.opacity(0.08)))
                }
                for i in 0..<3 {
                    let cx = size.width * (0.2 + 0.3 * CGFloat(i))
                    let cy = floorTop * 0.38
                    let r = scale * 14
                    let window = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                    context.fill(window, with: .color(Color(red: 0.02, green: 0.03, blue: 0.08)))
                    for s in 0..<9 {
                        let a = Double(i * 9 + s)
                        let sx = cx + CGFloat(sin(a * 12.9898) * 0.6) * r
                        let sy = cy + CGFloat(cos(a * 78.233) * 0.6) * r
                        let twinkle = 0.5 + 0.5 * sin(clock * 2 + a)
                        context.fill(Path(CGRect(x: (sx / scale).rounded() * scale, y: (sy / scale).rounded() * scale, width: scale, height: scale)),
                                     with: .color(.white.opacity(twinkle)))
                    }
                    context.stroke(window, with: .color(Color(red: 0.55, green: 0.58, blue: 0.64)), lineWidth: scale * 2)
                }
                for i in 0..<2 {
                    let x = size.width * (0.05 + 0.82 * CGFloat(i))
                    context.fill(Path(CGRect(x: x, y: floorTop * 0.62, width: scale * 16, height: scale * 10)),
                                 with: .color(Color(red: 0.36, green: 1, blue: 0.42).opacity(glow * 0.6)))
                }
            }

            Rectangle()
                .fill(Color(red: 0.23, green: 0.21, blue: 0.31))
                .frame(width: layout.screen.width, height: layout.screen.height - floorTop)
                .offset(y: floorTop)
            Rectangle()
                .fill(Color(red: 0.49, green: 1, blue: 0.49).opacity(glow))
                .frame(width: layout.screen.width, height: scale)
                .offset(y: floorTop)
        }
        .frame(width: layout.screen.width, height: layout.screen.height)
        .allowsHitTesting(false)
    }
}

/// A timed pixel-font speech bubble over a point, for the full-screen UFO scenes.
func ufoBubble(_ text: String, anchor: CGPoint, screen: CGSize, large: Bool = false, color: Color = .pixelCream) -> some View {
    let pixel: CGFloat = large ? 4 : (screen.width >= 700 ? 3 : 2)
    let lines = DialogText.wrap(text, maxCharacters: 26)
    let longest = CGFloat(lines.map(\.count).max() ?? 1)
    return SpeechBubble(anchor: anchor, boxWidth: min(screen.width - 32, longest * 6 * pixel + 32), screen: screen) {
        VStack(alignment: .leading, spacing: 3 * pixel) {
            ForEach(lines.indices, id: \.self) { index in
                PixelText(lines[index], pixelSize: pixel, color: color, scalesWithDynamicType: !large)
            }
        }
    }
    .accessibilityElement(children: .combine)
}

/// The hunter's unarmed walk cycle.
func unarmedWalkFrame(_ t: TimeInterval) -> String {
    ["hunter_unarmed_walk_a", "hunter_unarmed", "hunter_unarmed_walk_b", "hunter_unarmed"][Int(t * AdventureGame.walkFrameRate) % 4]
}

/// The first room aboard: the hunter (no shotgun now) wakes up wide-eyed, has two remarks,
/// clutches his gurgling stomach, then walks off to the right.
struct AboardView: View {
    let screen: CGSize
    let now: Date
    let start: Date

    private typealias Timing = AdventureGame.AboardTiming

    var body: some View {
        let t = now.timeIntervalSince(start)
        let layout = UFOInteriorLayout(screen: screen)
        let walk = min(max((t - Timing.walkOffStarts) / Timing.walkOffDuration, 0), 1)
        let hunterX = screen.width / 2 + (screen.width / 2 + AppArt.hunter.width * layout.scale) * walk
        let sprite: String = {
            if walk > 0 { return unarmedWalkFrame(t) }
            if t < 1.6 || (t >= Timing.gurgle && t < Timing.gurgleEnds) {
                return t >= Timing.gurgle ? "hunter_stomach" : "hunter_unarmed_shocked"
            }
            return "hunter_unarmed"
        }()
        let overHunter = layout.above(AppArt.hunter, x: hunterX)

        ZStack(alignment: .topLeading) {
            UFOInteriorBackground(layout: layout, now: now)

            AppSprite(name: sprite, size: AppArt.hunter, scale: layout.scale)
                .position(layout.standing(AppArt.hunter, x: hunterX))

            if t >= Timing.remarkShows, t < Timing.remarkHides {
                ufoBubble(AdventureGame.aboardRemark, anchor: overHunter, screen: screen)
            }
            if t >= Timing.bathroomShows, t < Timing.bathroomHides {
                ufoBubble(AdventureGame.bathroomRemark, anchor: overHunter, screen: screen)
            }

            Color.black
                .opacity(max(0, 1 - t / Timing.fadeIn))
                .allowsHitTesting(false)
        }
        .frame(width: screen.width, height: screen.height)
    }
}

/// The aliens' lab: two aliens at a metal table (backs to the hunter) with his shotgun on it.
/// They notice him, come over and chatter, he lets one slip, they comment and leave, and he
/// takes his shotgun back.
struct AlienLabView: View {
    let screen: CGSize
    let now: Date
    let start: Date

    private typealias Timing = AdventureGame.AlienTiming

    var body: some View {
        let t = max(0, now.timeIntervalSince(start))
        let layout = UFOInteriorLayout(screen: screen)
        let scale = layout.scale
        let w = screen.width
        let hunterWidth = AppArt.hunter.width * scale

        // The table at the far right, the shotgun on top.
        let tableX = (w * 0.86).rounded()
        let tableCenter = layout.standing(AppArt.metalTable, x: tableX)
        let tableTop = tableCenter.y - AppArt.metalTable.height * scale / 2
        let gunCenter = CGPoint(x: tableX, y: tableTop - AppArt.shotgunItem.height * scale / 2 + scale)

        // The aliens: at the table, then over to the middle, then away to the right.
        let homes = [w * 0.66, w * 0.75]
        let meets = [w * 0.47, w * 0.58]
        let approach = min(max((t - Timing.approachStarts) / Timing.approachDuration, 0), 1)
        let leave = min(max((t - Timing.leaveStarts) / Timing.leaveDuration, 0), 1)
        let aliensFaceRight = t < Timing.turn || leave > 0
        let aliensWalking = (approach > 0 && approach < 1) || (leave > 0 && leave < 1)
        let alienX: [CGFloat] = (0..<2).map { i in
            homes[i] + (meets[i] - homes[i]) * approach + (w + 80 - meets[i]) * leave
        }
        let alienSprite = aliensWalking ? (Int(t * 8).isMultiple(of: 2) ? "alien_walk_a" : "alien_walk_b") : "alien"

        // The hunter: walks in, later walks up to the table, then off to the right.
        let walkIn = min(t / Timing.walkInDuration, 1)
        let toTable = min(max((t - Timing.toTableStarts) / Timing.toTableDuration, 0), 1)
        let exit = min(max((t - Timing.exitStarts) / Timing.exitDuration, 0), 1)
        let standX = w * 0.22
        let tableStandX = tableX - AppArt.metalTable.width * scale / 2 - hunterWidth * 0.2
        let hunterX = -hunterWidth / 2 + (standX + hunterWidth / 2) * walkIn
            + (tableStandX - standX) * toTable + (w + hunterWidth - tableStandX) * exit
        let armed = t >= Timing.pickup
        let walking = (walkIn < 1) || (toTable > 0 && toTable < 1) || (exit > 0 && exit < 1)
        let hunterSprite: String = {
            if walking { return armed ? ["hunter_walk_a", "hunter", "hunter_walk_b", "hunter"][Int(t * AdventureGame.walkFrameRate) % 4] : unarmedWalkFrame(t) }
            if armed { return "hunter" }
            if t >= Timing.shockedStarts, t < Timing.shockedEnds { return "hunter_unarmed_shocked" }
            return "hunter_unarmed"
        }()
        let looksBack = t >= Timing.lookBackStarts && t < Timing.lookBackEnds
        let overHunter = layout.above(AppArt.hunter, x: hunterX)
        let overAlien = alienX.map { layout.above(AppArt.alien, x: $0) }

        ZStack(alignment: .topLeading) {
            UFOInteriorBackground(layout: layout, now: now)

            AppSprite(name: "metal_table", size: AppArt.metalTable, scale: scale)
                .position(tableCenter)
            if !armed {
                AppSprite(name: "shotgun_item", size: AppArt.shotgunItem, scale: scale)
                    .position(gunCenter)
            }

            // The fart: a few puffs of gas from behind him, drifting back and up as they swell and
            // fade. They hang where he was standing, so his glance back lands right on them.
            if t >= Timing.fart, t < Timing.fart + Timing.gasDuration + 0.6 {
                let hunterLeft = hunterX - AppArt.hunter.width * scale / 2
                let hunterTop = layout.standing(AppArt.hunter, x: hunterX).y - AppArt.hunter.height * scale / 2
                let rear = CGPoint(x: hunterLeft + AppArt.hunterRear.x * scale, y: hunterTop + AppArt.hunterRear.y * scale)
                ForEach(0..<4, id: \.self) { i in
                    let puffStart = Timing.fart + Double(i) * 0.15
                    let p = min(max((t - puffStart) / (Timing.gasDuration - 0.3), 0), 1)
                    if t >= puffStart, p < 1 {
                        AppSprite(name: "gas_puff", size: AppArt.gasPuff, scale: scale)
                            .scaleEffect(0.5 + 0.9 * p)
                            .opacity((1 - p) * 0.9)
                            .position(x: rear.x - ((4 + 12 * p + CGFloat(i) * 3) * scale).rounded(),
                                      y: rear.y - ((2 + 7 * p - CGFloat(i)) * scale).rounded())
                    }
                }
            }

            ForEach(0..<2, id: \.self) { i in
                AppSprite(name: alienSprite, size: AppArt.alien, scale: scale)
                    .scaleEffect(x: aliensFaceRight ? 1 : -1)
                    .position(layout.standing(AppArt.alien, x: alienX[i]))
            }

            AppSprite(name: hunterSprite, size: AppArt.hunter, scale: scale)
                .scaleEffect(x: looksBack ? -1 : 1)
                .position(layout.standing(AppArt.hunter, x: hunterX))

            if t >= Timing.bangShows, t < Timing.bangHides {
                ufoBubble("!", anchor: overAlien[0], screen: screen, large: true)
                ufoBubble("!", anchor: overAlien[1], screen: screen, large: true)
            }
            if t >= Timing.firstChatterShows, t < Timing.secondChatterShows {
                ufoBubble(AdventureGame.alienChatter[0], anchor: overAlien[0], screen: screen, color: Color(red: 0.49, green: 1, blue: 0.49))
            }
            if t >= Timing.secondChatterShows, t < Timing.chatterHides {
                ufoBubble(AdventureGame.alienChatter[1], anchor: overAlien[1], screen: screen, color: Color(red: 0.49, green: 1, blue: 0.49))
            }
            if t >= Timing.questionShows, t < Timing.questionHides {
                ufoBubble("?", anchor: overHunter, screen: screen, large: true)
            }
            if t >= Timing.mannersShows, t < Timing.mannersHides {
                ufoBubble(AdventureGame.alienManners, anchor: overAlien[0], screen: screen)
            }
            if t >= Timing.niceShows, t < Timing.niceHides {
                ufoBubble(AdventureGame.alienNice, anchor: overAlien[1], screen: screen)
            }

            Color.black
                .opacity(min(max((t - Timing.fadeStarts) / Timing.fadeDuration, 0), 1))
                .allowsHitTesting(false)
        }
        .frame(width: screen.width, height: screen.height)
        .sensoryFeedback(.success, trigger: armed)
    }
}

#if DEBUG
#Preview("Alien console") {
    // Partway through playing back a sequence, one matched and one error so far.
    AdventureView(game: .preview(scene: 14, phase: .console, route: .restricted, console: ConsoleState(
        stage: .showing, stageStart: .now.addingTimeInterval(-0.6),
        sequence: [5, 10, 3, 12], colors: [0, 2, 1, 3], results: [true, false])))
        .ignoresSafeArea()
}

#Preview("Console: booting") {
    AdventureView(game: .preview(scene: 14, phase: .console, route: .restricted, console: ConsoleState(
        stage: .booting, stageStart: .now.addingTimeInterval(-1.5))))
        .ignoresSafeArea()
}

#Preview("Console: lockdown") {
    AdventureView(game: .preview(scene: 14, phase: .console, route: .restricted, console: ConsoleState(
        stage: .lockdown, stageStart: .now.addingTimeInterval(-1.2), results: [false, false])))
        .ignoresSafeArea()
}

#Preview("Console: access granted") {
    AdventureView(game: .preview(scene: 14, phase: .console, route: .restricted, console: ConsoleState(
        stage: .granted, stageStart: .now.addingTimeInterval(-1.0), results: [true, true, true])))
        .ignoresSafeArea()
}

#Preview("Aboard: bathroom") {
    AdventureView(game: .preview(scene: 14, phase: .aboard(start: .now.addingTimeInterval(-6.0)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Aboard: stomach") {
    AdventureView(game: .preview(scene: 14, phase: .aboard(start: .now.addingTimeInterval(-9.2)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Lab: aliens notice") {
    AdventureView(game: .preview(scene: 14, phase: .aliens(start: .now.addingTimeInterval(-2.5)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Lab: chatter") {
    AdventureView(game: .preview(scene: 14, phase: .aliens(start: .now.addingTimeInterval(-6.0)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Lab: fart") {
    AdventureView(game: .preview(scene: 14, phase: .aliens(start: .now.addingTimeInterval(-10.6)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Lab: manners") {
    AdventureView(game: .preview(scene: 14, phase: .aliens(start: .now.addingTimeInterval(-12.5)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Lab: shotgun") {
    AdventureView(game: .preview(scene: 14, phase: .aliens(start: .now.addingTimeInterval(-20.4)), route: .restricted))
        .ignoresSafeArea()
}
#endif
