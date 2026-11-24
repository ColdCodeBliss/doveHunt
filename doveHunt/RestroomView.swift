//
//  RestroomView.swift
//  doveHunt
//
//  Aboard the UFO: the restroom corridor. The pickle sandwich strikes again; the hunter ducks
//  into the men's room (we only hear it), and two angry aliens carry him out afterward.
//

import SwiftUI

struct RestroomView: View {
    let screen: CGSize
    let now: Date
    let start: Date

    private typealias Timing = AdventureGame.RestroomTiming

    var body: some View {
        let t = max(0, now.timeIntervalSince(start))
        let layout = UFOInteriorLayout(screen: screen)
        let s = layout.scale
        let w = screen.width
        let hunterWidth = AppArt.hunter.width * s
        let mensDoorX = (w * 0.56).rounded()
        let womensDoorX = (w * 0.80).rounded()
        let back = t >= Timing.backStarts

        // Before the visit: in from the left, a stomach grab, then into the men's room.
        let walkIn = min(t / Timing.walkInDuration, 1)
        let toDoor = min(max((t - Timing.toDoorStarts) / Timing.toDoorDuration, 0), 1)
        let standX = (w * 0.30).rounded()
        let approachX = -hunterWidth / 2 + (standX + hunterWidth / 2) * walkIn + (mensDoorX - standX) * toDoor
        let doorOpen = !back && t >= Timing.doorOpens
            ? min((t - Timing.doorOpens) / 0.3, 1) : 0
        let entering = min(max((t - Timing.enters) / 0.3, 0), 1)

        // After: the angry aliens close in, pick him up (lying sideways, head to the right),
        // and carry him off to the right.
        let closeIn = min(max((t - (Timing.pickup - 0.4)) / 0.4, 0), 1)
        let pickup = min(max((t - Timing.pickup) / Timing.pickupDuration, 0), 1)
        let carry = min(max((t - Timing.carryStarts) / Timing.carryDuration, 0), 1)
        let carryOffset = (w + 140 - mensDoorX) * carry
        let alienHome = [mensDoorX - w * 0.13, mensDoorX + w * 0.13]
        let alienCarry = [mensDoorX - 22 * s, mensDoorX + 22 * s]
        let alienX = (0..<2).map { i in alienHome[i] + (alienCarry[i] - alienHome[i]) * closeIn + carryOffset }
        let aliensMoving = (closeIn > 0 && closeIn < 1) || (carry > 0 && carry < 1)
        let alienSprite: String = {
            if aliensMoving { return Int(t * 8).isMultiple(of: 2) ? "alien_carry_a" : "alien_carry_b" }
            return pickup > 0 ? "alien_carry" : "alien_angry"
        }()
        let alienTop = layout.floorTop + 3 * s - AppArt.alien.height * s
        let standingCenter = layout.standing(AppArt.hunter, x: mensDoorX)
        // Lying down, the sprite's width is its height. His body is in the upper part of that
        // (the shotgun side hangs below), so set him low enough to rest on their raised hands.
        let carriedY = alienTop + 22 * s - AppArt.hunter.width * s / 2

        let hunterSprite: String = {
            if !back {
                if walkIn < 1 || (toDoor > 0 && toDoor < 1) {
                    return AppArt.hunterWalkCycle[Int(t * AdventureGame.walkFrameRate) % AppArt.hunterWalkCycle.count]
                }
                if t >= Timing.stomachStarts, t < Timing.stomachEnds { return "hunter_stomach" }
            }
            return "hunter"
        }()

        ZStack(alignment: .topLeading) {
            UFOInteriorBackground(layout: layout, now: now)

            door(x: mensDoorX, sign: .men, open: doorOpen, layout: layout)
            door(x: womensDoorX, sign: .women, open: 0, layout: layout)

            if back {
                ForEach(0..<2, id: \.self) { i in
                    AppSprite(name: alienSprite, size: AppArt.alien, scale: s)
                        // Facing him until they pick him up, then both face the way out.
                        .scaleEffect(x: i == 0 || carry > 0 ? 1 : -1)
                        .position(layout.standing(AppArt.alien, x: alienX[i]))
                }
                AppSprite(name: hunterSprite, size: AppArt.hunter, scale: s)
                    .rotationEffect(.degrees(90 * pickup))
                    .position(x: mensDoorX + carryOffset,
                              y: standingCenter.y + (carriedY - standingCenter.y) * pickup)
                if t >= Timing.cursingShows, t < Timing.cursingHides {
                    ForEach(0..<2, id: \.self) { i in
                        ufoBubble(AdventureGame.alienCursing[i], anchor: layout.above(AppArt.alien, x: alienX[i]), screen: screen,
                                  color: Color(red: 1, green: 0.45, blue: 0.4))
                    }
                }
            } else if entering < 1 {
                AppSprite(name: hunterSprite, size: AppArt.hunter, scale: s)
                    .opacity(1 - entering)
                    .position(layout.standing(AppArt.hunter, x: approachX))
            }

            Color.black
                .opacity(blackout(t))
                .allowsHitTesting(false)
        }
        .frame(width: screen.width, height: screen.height)
    }

    /// In from black, black while he's in there, back again, and out at the end.
    private func blackout(_ t: TimeInterval) -> Double {
        if t < Timing.fadeIn { return 1 - t / Timing.fadeIn }
        if t < Timing.blackStarts { return 0 }
        if t < Timing.backStarts { return min((t - Timing.blackStarts) / Timing.blackFade, 1) }
        if t < Timing.backStarts + Timing.backFade { return 1 - (t - Timing.backStarts) / Timing.backFade }
        return min(max((t - Timing.fadeOutStarts) / Timing.fadeOutDuration, 0), 1)
    }

    private enum Sign { case men, women }

    /// A metal sliding door with a pictogram sign above it. `open` (0...1) slides the panel up.
    private func door(x: CGFloat, sign: Sign, open: Double, layout: UFOInteriorLayout) -> some View {
        let s = layout.scale
        let width = 30 * s
        let height = 52 * s
        let bottom = layout.floorTop + 3 * s
        let panelHeight = (height - 4 * s) * (1 - open)
        return ZStack(alignment: .topLeading) {
            // Frame and the dark doorway behind the panel.
            Rectangle()
                .fill(Color(red: 0.55, green: 0.58, blue: 0.64))
                .frame(width: width, height: height)
            Rectangle()
                .fill(Color.black)
                .frame(width: width - 4 * s, height: height - 4 * s)
                .offset(x: 2 * s, y: 2 * s)
            // The panel, sliding up into the frame.
            Rectangle()
                .fill(Color(red: 0.25, green: 0.27, blue: 0.33))
                .frame(width: width - 4 * s, height: panelHeight)
                .overlay(alignment: .center) {
                    Rectangle().fill(Color.black.opacity(0.35)).frame(width: s, height: panelHeight)
                }
                .offset(x: 2 * s, y: 2 * s + (height - 4 * s) - panelHeight)
            // The sign plate above the door.
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.1, green: 0.11, blue: 0.14)))
                let ink = sign == .men ? Color(red: 0.4, green: 0.85, blue: 1) : Color(red: 1, green: 0.55, blue: 0.85)
                let px = s
                // An alien pictogram: a big head and a body (trousers or a dress).
                context.fill(Path(CGRect(x: 5 * px, y: 2 * px, width: 4 * px, height: 3 * px)), with: .color(ink))
                if sign == .men {
                    context.fill(Path(CGRect(x: 6 * px, y: 5 * px, width: 2 * px, height: 4 * px)), with: .color(ink))
                    context.fill(Path(CGRect(x: 5 * px, y: 9 * px, width: px, height: 2 * px)), with: .color(ink))
                    context.fill(Path(CGRect(x: 8 * px, y: 9 * px, width: px, height: 2 * px)), with: .color(ink))
                } else {
                    for row in 0..<4 {
                        context.fill(Path(CGRect(x: (6 - CGFloat(row) / 2) * px, y: (5 + CGFloat(row)) * px,
                                                 width: (2 + CGFloat(row)) * px, height: px)), with: .color(ink))
                    }
                    context.fill(Path(CGRect(x: 5.5 * px, y: 9 * px, width: px, height: 2 * px)), with: .color(ink))
                    context.fill(Path(CGRect(x: 7.5 * px, y: 9 * px, width: px, height: 2 * px)), with: .color(ink))
                }
            }
            .frame(width: 14 * s, height: 12 * s)
            .overlay(Rectangle().strokeBorder(Color(red: 0.55, green: 0.58, blue: 0.64), lineWidth: s))
            .offset(x: (width - 14 * s) / 2, y: -15 * s)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .position(x: x, y: bottom - height / 2)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(sign == .men ? "Men's restroom" : "Women's restroom")
    }
}

#if DEBUG
#Preview("Restroom: stomach") {
    AdventureView(game: .preview(scene: 14, phase: .restroom(start: .now.addingTimeInterval(-3.0)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Restroom: angry aliens") {
    AdventureView(game: .preview(scene: 14, phase: .restroom(start: .now.addingTimeInterval(-12.8)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Restroom: carried out") {
    AdventureView(game: .preview(scene: 14, phase: .restroom(start: .now.addingTimeInterval(-15.4)), route: .restricted))
        .ignoresSafeArea()
}
#endif
