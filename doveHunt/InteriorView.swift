//
//  InteriorView.swift
//  doveHunt
//
//  The cut-scene inside the cabin: the hunter barges in, Anna has words with him, then
//  slips out the kitchen's back door, and the hunter, puzzled, walks back outside.
//

import SwiftUI

struct InteriorView: View {
    let game: AdventureGame
    let step: InteriorStep
    let stepStart: Date
    let screen: CGSize
    let now: Date

    var body: some View {
        let room = InteriorRoom(screen: screen)
        let frame = InteriorFrame(step: step, elapsed: max(0, now.timeIntervalSince(stepStart)))
        let time = now.timeIntervalSinceReferenceDate

        ZStack(alignment: .topLeading) {
            // The room sits on a black stage; on tall screens the space above holds the dialog.
            Color.black

            AppSprite(name: frame.backDoorOpen ? "interior_door_open" : "interior_door_closed", size: AppArt.interior, scale: room.scale)
                .position(room.point(AppArt.interior.width / 2, AppArt.interior.height / 2))

            TVStatic(time: time, pixel: room.scale)
                .frame(width: AppArt.interiorTVScreen.width * room.scale, height: AppArt.interiorTVScreen.height * room.scale)
                .position(room.point(AppArt.interiorTVScreen.midX, AppArt.interiorTVScreen.midY))

            character(sprite: frame.annaSprite, size: AppArt.anna, left: frame.annaLeft, facesRight: frame.annaFacesRight, room: room)
                .opacity(frame.annaOpacity)

            character(sprite: frame.hunterSprite, size: AppArt.hunter, left: frame.hunterLeft, facesRight: frame.hunterFacesRight, room: room)
                .opacity(frame.hunterOpacity)

            if case .speaking(let line) = step {
                annaSpeech(line: line, frame: frame, room: room, time: time)
            }

            if frame.showsQuestion {
                questionBubble(frame: frame, room: room)
            }

            Color.black
                .opacity(frame.blackout)
                .allowsHitTesting(false)
        }
        .frame(width: screen.width, height: screen.height)
        .contentShape(Rectangle())
        .onTapGesture { game.advanceDialog() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Continue") { game.advanceDialog() }
    }

    // MARK: Pieces

    /// A character standing on the floor, mirrored when facing left.
    private func character(sprite: String, size: CGSize, left: CGFloat, facesRight: Bool, room: InteriorRoom) -> some View {
        AppSprite(name: sprite, size: size, scale: room.scale)
            .scaleEffect(x: facesRight ? 1 : -1)
            .position(room.point(left.rounded() + size.width / 2, AppArt.interiorFeet + 3 - size.height / 2))
            .allowsHitTesting(false)
    }

    /// Anna's speech box with a tail pointing down at her.
    private func annaSpeech(line: Int, frame: InteriorFrame, room: InteriorRoom, time: Double) -> some View {
        let pixel: CGFloat = screen.width >= 700 ? 3 : 2
        let boxWidth = min(screen.width - 32, 34 * 6 * pixel + 32)
        let maxChars = max(10, Int((boxWidth - 32) / (6 * pixel)))
        let lines = DialogText.wrap(AdventureGame.annaLines[line], maxCharacters: maxChars)
        let isLast = line == AdventureGame.annaLines.count - 1
        let blinkOn = Int(time * 2).isMultiple(of: 2)

        let content = VStack(alignment: .leading, spacing: 3 * pixel) {
            PixelText("ANNA:", pixelSize: pixel, color: .pixelOrange)
            ForEach(lines.indices, id: \.self) { index in
                PixelText(lines[index], pixelSize: pixel)
            }
            PixelText(isLast ? "> TAP" : "> TAP TO CONTINUE", pixelSize: pixel, color: .pixelOrange)
                .opacity(blinkOn ? 1 : 0.25)
        }

        let head = room.point(frame.annaLeft + AppArt.annaBodyCenterX, AppArt.interiorFeet + 3 - AppArt.anna.height - 2)
        // On tall screens, keep the speech in the black space above the room.
        let aboveRoom: CGFloat? = room.origin.y >= 220 ? room.origin.y - 8 : nil
        return SpeechBubble(anchor: head, boxWidth: boxWidth, screen: screen, maxBottom: aboveRoom) { content }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private func questionBubble(frame: InteriorFrame, room: InteriorRoom) -> some View {
        let head = room.point(frame.hunterLeft + AppArt.hunterBodyCenterX, AppArt.interiorFeet + 3 - AppArt.hunter.height - 2)
        return SpeechBubble(anchor: head, boxWidth: 60, screen: screen) {
            PixelText("?", pixelSize: 4, scalesWithDynamicType: false)
        }
        .accessibilityLabel("The hunter is puzzled")
    }
}

// MARK: - Speech bubble

/// A black, cream-bordered pixel box hanging above `anchor`, kept on screen, with a small
/// tail pointing down at the speaker.
struct SpeechBubble<Content: View>: View {
    let anchor: CGPoint
    let boxWidth: CGFloat
    let screen: CGSize
    /// If set, the bubble's bottom edge sits no lower than this (used to keep dialog in the
    /// empty space above the room on tall screens instead of covering the scene).
    var maxBottom: CGFloat? = nil
    @ViewBuilder let content: Content

    var body: some View {
        let halfSlack: CGFloat = max(0, screen.width / 2 - boxWidth / 2 - 16)
        let offsetX: CGFloat = min(max(anchor.x - screen.width / 2, -halfSlack), halfSlack)
        let boxCenterX: CGFloat = screen.width / 2 + offsetX
        let tailOffset: CGFloat = min(max(anchor.x - boxCenterX, -boxWidth / 2 + 14), boxWidth / 2 - 14)

        VStack(spacing: -3) {
            content
                .padding(14)
                .background(Color.black.opacity(0.92), ignoresSafeAreaEdges: [])
                .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
            BubbleTail()
                .fill(Color.pixelCream)
                .frame(width: 14, height: 10)
                .offset(x: tailOffset)
        }
        .fixedSize()
        .frame(width: screen.width, height: max(min(anchor.y, maxBottom ?? .infinity), 80), alignment: .bottom)
        .offset(x: offsetX)
        .allowsHitTesting(false)
    }
}

/// A stepped, pixel-style downward pointer.
nonisolated struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.height / 3
        for row in 0..<3 {
            let inset = CGFloat(row) * rect.width / 6
            path.addRect(CGRect(x: rect.minX + inset, y: rect.minY + CGFloat(row) * step, width: rect.width - inset * 2, height: step))
        }
        return path
    }
}

// MARK: - TV

/// The old TV flipping between random color "scenes", drawn as chunky 2x2 art-pixel blocks.
struct TVStatic: View {
    let time: Double
    /// Points per art pixel.
    let pixel: CGFloat

    private static let palette: [Color] = [
        Color(red: 0.95, green: 0.95, blue: 0.95), Color(red: 0.95, green: 0.85, blue: 0.2),
        Color(red: 0.2, green: 0.85, blue: 0.9), Color(red: 0.3, green: 0.8, blue: 0.3),
        Color(red: 0.85, green: 0.3, blue: 0.85), Color(red: 0.9, green: 0.25, blue: 0.2),
        Color(red: 0.2, green: 0.3, blue: 0.85), Color(red: 0.1, green: 0.1, blue: 0.12),
    ]

    var body: some View {
        Canvas { context, size in
            let cells = 8
            let cell = size.width / CGFloat(cells)
            let channel = Int((time / 0.8).rounded(.down))
            var rng = SplitMix(seed: UInt64(bitPattern: Int64(channel)))
            let kind = Int(rng.next() % 4)
            let a = Self.palette[Int(rng.next() % 8)]
            let b = Self.palette[Int(rng.next() % 8)]
            for y in 0..<cells {
                for x in 0..<cells {
                    let color: Color
                    switch kind {
                    case 0: color = Self.palette[x % 7]                                // color bars
                    case 1: color = Self.palette[Int(rng.next() % 8)]                  // snowy blocks
                    case 2: color = (x / 2 + y / 2).isMultiple(of: 2) ? a : b          // checkerboard
                    default: color = y < cells / 2 ? a : (y < cells * 3 / 4 ? b : .black) // banded scene
                    }
                    context.fill(Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell)), with: .color(color))
                }
            }
            // A faint scanline every other art pixel for that CRT look.
            for row in stride(from: 0, to: size.height, by: pixel * 2) {
                context.fill(Path(CGRect(x: 0, y: row, width: size.width, height: max(1, pixel * 0.4))), with: .color(.black.opacity(0.25)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Tiny deterministic RNG for the TV's random scenes.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Geometry

/// The room fitted to the screen like a stage: as large as possible without cropping,
/// centered horizontally and set a little low so tall screens have room for dialog above.
struct InteriorRoom {
    let scale: CGFloat
    let origin: CGPoint

    init(screen: CGSize) {
        let room = AppArt.interior
        scale = min(screen.width / room.width, screen.height / room.height)
        let height = room.height * scale
        let lowCenterY = screen.height * 0.6
        let y = min(max(lowCenterY - height / 2, 0), screen.height - height)
        origin = CGPoint(x: (screen.width - room.width * scale) / 2, y: y)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }
}

/// Where everyone is at a moment in the cut-scene.
struct InteriorFrame {
    /// Just inside the front door (clear of the TV).
    var hunterLeft: CGFloat = InteriorFrame.hunterInside
    var hunterFacesRight = true
    var hunterSprite = "hunter"
    var hunterOpacity: Double = 1
    var annaLeft: CGFloat = 186
    /// Anna starts facing away from the hunter (to the right).
    var annaFacesRight = true
    var annaSprite = "anna"
    var annaOpacity: Double = 1
    var backDoorOpen = false
    var showsQuestion = false
    var blackout: Double = 0

    typealias Timing = AdventureGame.InteriorTiming
    static let hunterInside: CGFloat = 12

    init(step: InteriorStep, elapsed t: TimeInterval) {
        switch step {
        case .arriving:
            blackout = max(0, 1 - t / AdventureGame.fadeInDuration)
            let walk = min(max((t - Timing.stepInStart) / Timing.stepInDuration, 0), 1)
            hunterLeft = -6 + (Self.hunterInside + 6) * walk
            if walk > 0, walk < 1 { hunterSprite = Self.walkFrame(AppArt.hunterWalkCycle, t) }
            annaFacesRight = t < Timing.annaTurns

        case .speaking:
            annaFacesRight = false

        case .annaLeaving:
            let walk = min(t / Timing.annaWalkDuration, 1)
            let doorLeft = AppArt.interiorBackDoorCenterX - AppArt.annaBodyCenterX
            annaLeft = 186 + (doorLeft - 186) * walk
            if walk < 1 { annaSprite = Self.walkFrame(AppArt.annaWalkCycle, t) }
            backDoorOpen = t >= Timing.backDoorOpens && t < Timing.backDoorCloses
            annaOpacity = t < Timing.annaWalkDuration ? 1 : max(0, 1 - (t - Timing.annaWalkDuration) / (Timing.annaGone - Timing.annaWalkDuration))

        case .puzzled:
            annaOpacity = 0
            hunterFacesRight = t >= Timing.looksRight
            showsQuestion = t >= Timing.questionAppears

        case .leaving:
            annaOpacity = 0
            hunterFacesRight = false
            let walk = min(t / Timing.leaveWalkDuration, 1)
            hunterLeft = Self.hunterInside - 34 * walk
            if walk < 1 { hunterSprite = Self.walkFrame(AppArt.hunterWalkCycle, t) }
            hunterOpacity = t < Timing.leaveWalkDuration - 0.3 ? 1 : max(0, 1 - (t - (Timing.leaveWalkDuration - 0.3)) / 0.3)
            blackout = min(max((t - Timing.leaveFadeStart) / (Timing.leaveDone - Timing.leaveFadeStart - 0.1), 0), 1)
        }
    }

    private static func walkFrame(_ cycle: [String], _ t: TimeInterval) -> String {
        cycle[Int(t * AdventureGame.walkFrameRate) % cycle.count]
    }
}
