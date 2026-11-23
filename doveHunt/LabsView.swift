//
//  LabsView.swift
//  doveHunt
//
//  Aboard the UFO, after the skeletons' chase: a lab they wrecked on the way through, and a
//  pristine lab where the scientist has ended up in a vat (with the skeletons, now in lab coats,
//  taking notes). The hunter returns the clipboard.
//

import SwiftUI

// MARK: - The wrecked lab

/// Smashed and strewn: a toppled table, a knocked-over vat, spilled goo, scattered papers,
/// scorch marks with smoke, wall cracks, a flickering panel, and a dangling, sparking cable.
/// The hunter walks to the middle, looks around, scratches his head, and moves on.
struct WreckedLabView: View {
    let screen: CGSize
    let now: Date
    let start: Date

    private typealias Timing = AdventureGame.WreckedTiming

    var body: some View {
        let t = max(0, now.timeIntervalSince(start))
        let clock = now.timeIntervalSinceReferenceDate
        let layout = UFOInteriorLayout(screen: screen)
        let s = layout.scale
        let w = screen.width
        let floorY = layout.floorTop + 3 * s
        let hunterWidth = AppArt.hunter.width * s

        // The hunter: in to the middle, a look left and right, a head scratch, then off to the right.
        let walkIn = min(t / Timing.walkToCenter, 1)
        let walkOff = min(max((t - Timing.walkOffStarts) / Timing.walkOffDuration, 0), 1)
        let centerX = (w / 2).rounded()
        let hunterX = -hunterWidth / 2 + (centerX + hunterWidth / 2) * walkIn + (w + hunterWidth - centerX) * walkOff
        let walking = walkIn < 1 || (walkOff > 0 && walkOff < 1)
        let scratching = t >= Timing.scratchStarts && t < Timing.scratchEnds
        let facesLeft = t >= Timing.lookLeftStarts && t < Timing.lookRightStarts
        let hunterSprite: String = walking
            ? AppArt.hunterWalkCycle[Int(t * AdventureGame.walkFrameRate) % AppArt.hunterWalkCycle.count]
            : (scratching ? "hunter_scratch" : "hunter")

        ZStack(alignment: .topLeading) {
            UFOInteriorBackground(layout: layout, now: now)

            // The lights are flickering after the chase.
            Color.black
                .opacity(0.25 + (Int(clock * 7).isMultiple(of: 5) ? 0.25 : 0))
                .allowsHitTesting(false)

            wallDamage(layout: layout, clock: clock)

            // Spilled goo and scorch marks on the deck.
            Ellipse().fill(Color(red: 0.25, green: 0.75, blue: 0.35).opacity(0.85))
                .frame(width: 50 * s, height: 4 * s)
                .position(x: w * 0.74, y: floorY - s)
            Ellipse().fill(Color.black.opacity(0.45))
                .frame(width: 34 * s, height: 5 * s)
                .position(x: w * 0.36, y: floorY - s)

            // A toppled table and a knocked-over vat.
            AppSprite(name: "metal_table", size: AppArt.metalTable, scale: s)
                .rotationEffect(.degrees(-78))
                .position(x: w * 0.28, y: floorY - AppArt.metalTable.width * s * 0.42)
            AppSprite(name: "vat_broken", size: AppArt.vat, scale: s)
                .rotationEffect(.degrees(90))
                .position(x: w * 0.76, y: floorY - AppArt.vat.width * s / 2 + s)

            // Papers everywhere.
            ForEach(0..<9, id: \.self) { i in
                let fx = 0.12 + 0.09 * Double(i) + 0.03 * sin(Double(i) * 3.1)
                Rectangle()
                    .fill(Color(red: 0.95, green: 0.95, blue: 0.92))
                    .frame(width: 4 * s, height: 3 * s)
                    .overlay(Rectangle().fill(Color(red: 0.43, green: 0.75, blue: 0.43)).frame(width: 2 * s, height: max(1, s / 2)))
                    .rotationEffect(.degrees(Double(i * 37 % 60) - 30))
                    .position(x: w * fx, y: floorY + CGFloat(i % 3) * 3 * s + s)
            }

            // Smoke curling up from the scorch mark.
            ForEach(0..<3, id: \.self) { i in
                let p = (clock * 0.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                AppSprite(name: "gas_puff", size: AppArt.gasPuff, scale: s)
                    .grayscale(1)
                    .scaleEffect(0.6 + p)
                    .opacity((1 - p) * 0.6)
                    .position(x: w * 0.36 + CGFloat(sin(p * 6 + Double(i))) * 4 * s, y: floorY - (6 + 40 * p) * s)
            }
            .allowsHitTesting(false)

            AppSprite(name: hunterSprite, size: AppArt.hunter, scale: s)
                .scaleEffect(x: facesLeft ? -1 : 1)
                .position(layout.standing(AppArt.hunter, x: hunterX))

            if t >= Timing.scratchStarts + 0.1, t < Timing.scratchEnds - 0.2 {
                ufoBubble("?", anchor: layout.above(AppArt.hunter, x: hunterX), screen: screen, large: true)
            }
        }
        .frame(width: screen.width, height: screen.height)
    }

    /// Cracks in the bulkheads, a broken wall panel flickering, and a cable dangling from the
    /// ceiling, spitting sparks.
    private func wallDamage(layout: UFOInteriorLayout, clock: Double) -> some View {
        let s = layout.scale
        let w = screen.width
        return Canvas { context, size in
            // Zigzag cracks.
            for (startX, startY) in [(w * 0.18, layout.floorTop * 0.55), (w * 0.63, layout.floorTop * 0.2), (w * 0.9, layout.floorTop * 0.7)] {
                var path = Path()
                path.move(to: CGPoint(x: startX, y: startY))
                for k in 1...5 {
                    let dx = (k.isMultiple(of: 2) ? 1 : -1) * 4 * s
                    path.addLine(to: CGPoint(x: startX + dx + CGFloat(k) * s, y: startY + CGFloat(k) * 5 * s))
                }
                context.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: s)
            }
            // A broken panel, flickering.
            let flicker = Int(clock * 11).isMultiple(of: 3)
            context.fill(Path(CGRect(x: w * 0.87, y: layout.floorTop * 0.62, width: 16 * s, height: 10 * s)),
                         with: .color(flicker ? Color(red: 0.36, green: 1, blue: 0.42).opacity(0.6) : Color.black.opacity(0.5)))
            // A cable hanging from the ceiling, sparking at its torn end.
            let cableX = w * 0.55
            let end = CGPoint(x: cableX + sin(clock * 2) * 2 * s, y: layout.floorTop * 0.42)
            var cable = Path()
            cable.move(to: CGPoint(x: cableX, y: 0))
            cable.addQuadCurve(to: end, control: CGPoint(x: cableX - 6 * s, y: layout.floorTop * 0.2))
            context.stroke(cable, with: .color(Color(red: 0.1, green: 0.1, blue: 0.12)), lineWidth: 2 * s)
            let tick = Int(clock * 10)
            if tick % 4 != 0 {
                for spark in 0..<5 {
                    let a = Double(spark * 72 + tick * 37)
                    let r = CGFloat((tick * 7 + spark * 3) % 5 + 2) * s
                    let x = end.x + CGFloat(cos(a)) * r
                    let y = end.y + CGFloat(sin(a)) * r
                    context.fill(Path(CGRect(x: (x / s).rounded() * s, y: (y / s).rounded() * s, width: s, height: s)),
                                 with: .color(spark.isMultiple(of: 2) ? .yellow : .white))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - The pristine lab

/// Spotless: the scientist floats in a vat while the two skeletons, in lab coats with
/// clipboards, observe. The hunter goes wide-eyed, the skeletons look over, the scientist says
/// something alien, and the hunter whistles his way to a table to leave the clipboard.
struct PristineLabView: View {
    let screen: CGSize
    let now: Date
    let start: Date

    private typealias Timing = AdventureGame.PristineTiming

    var body: some View {
        let t = max(0, now.timeIntervalSince(start))
        let clock = now.timeIntervalSinceReferenceDate
        let layout = UFOInteriorLayout(screen: screen)
        let s = layout.scale
        let w = screen.width
        let floorY = layout.floorTop + 3 * s
        let hunterWidth = AppArt.hunter.width * s

        // The table for the clipboard, and the big vat with the scientist in it.
        let tableX = (w * 0.34).rounded()
        let tableCenter = layout.standing(AppArt.metalTable, x: tableX)
        let tableTop = tableCenter.y - AppArt.metalTable.height * s / 2
        let vatScale = (s * 1.5).rounded()
        let vatX = (w * 0.71).rounded()
        let vatCenterY = floorY - AppArt.vat.height * vatScale / 2
        let vatTop = vatCenterY - AppArt.vat.height * vatScale / 2
        let scientistBob: CGFloat = (sin(clock * 1.3) * 2).rounded() * s

        // The skeletons flank the vat, facing it; the left one turns to look at the hunter.
        let lookedOver = t >= Timing.skeletonsLook
        let hop: CGFloat = lookedOver && t < Timing.skeletonsLook + 0.2 ? -2 * s : 0

        // The hunter: walks in, gapes, then carries the clipboard to the table and walks off.
        let walkIn = min(t / Timing.walkInDuration, 1)
        let toTable = min(max((t - Timing.toTableStarts) / Timing.toTableDuration, 0), 1)
        let walkOff = min(max((t - Timing.walkOffStarts) / Timing.walkOffDuration, 0), 1)
        let standX = (w * 0.14).rounded()
        let tableStandX = tableX - AppArt.metalTable.width * s / 2 - hunterWidth * 0.2
        let hunterX = -hunterWidth / 2 + (standX + hunterWidth / 2) * walkIn
            + (tableStandX - standX) * toTable + (w + hunterWidth - tableStandX) * walkOff
        let carrying = t >= Timing.clipboardOut && t < Timing.place
        let unarmed = t >= Timing.clipboardOut && t < Timing.armedAgain
        let walking = walkIn < 1 || (toTable > 0 && toTable < 1) || (walkOff > 0 && walkOff < 1)
        let hunterSprite: String = {
            if walking {
                return unarmed ? unarmedWalkFrame(t) : AppArt.hunterWalkCycle[Int(t * AdventureGame.walkFrameRate) % AppArt.hunterWalkCycle.count]
            }
            if unarmed { return "hunter_unarmed" }
            if t >= Timing.shockedStarts, t < Timing.shockedEnds { return "hunter_shocked" }
            return "hunter"
        }()
        let hunterCenter = layout.standing(AppArt.hunter, x: hunterX)
        let hunterLeft = hunterX - hunterWidth / 2
        let hunterTop = hunterCenter.y - AppArt.hunter.height * s / 2

        ZStack(alignment: .topLeading) {
            UFOInteriorBackground(layout: layout, now: now)

            AppSprite(name: "metal_table", size: AppArt.metalTable, scale: s)
                .position(tableCenter)
            if t >= Timing.place {
                AppSprite(name: "clipboard", size: AppArt.clipboard, scale: s)
                    .rotationEffect(.degrees(90))
                    .position(x: tableX + 6 * s, y: tableTop - AppArt.clipboard.width * s / 2 + s)
            }

            // The scientist, floating in his own vat.
            AppSprite(name: "vat_back", size: AppArt.vat, scale: vatScale)
                .position(x: vatX, y: vatCenterY)
            AppSprite(name: "scientist_bare", size: AppArt.alien, scale: s)
                .scaleEffect(x: -1)
                .position(x: vatX, y: vatTop + 26 * vatScale + scientistBob - AppArt.alien.height * s / 2 + 6 * s)
            AppSprite(name: "vat_front", size: AppArt.vat, scale: vatScale)
                .position(x: vatX, y: vatCenterY)
            Rectangle()
                .fill(Color(red: 0.3, green: 0.9, blue: 0.4).opacity(0.5 + 0.4 * sin(clock * 3)))
                .frame(width: 6 * s, height: 3 * s)
                .position(x: vatX, y: vatTop - 1.5 * s)

            // The skeletons in their lab coats.
            AppSprite(name: "skeleton_dove_coat", size: AppArt.skeletonDove, scale: s)
                .scaleEffect(x: lookedOver ? -1 : 1)
                .position(x: (w * 0.55).rounded(), y: floorY - AppArt.skeletonDove.height * s / 2 + hop)
            AppSprite(name: "skeleton_mallard_coat", size: AppArt.skeletonMallard, scale: s)
                .scaleEffect(x: -1)
                .position(x: (w * 0.87).rounded(), y: floorY - AppArt.skeletonMallard.height * s / 2 + hop)

            AppSprite(name: hunterSprite, size: AppArt.hunter, scale: s)
                .position(hunterCenter)
            if carrying {
                AppSprite(name: "clipboard", size: AppArt.clipboard, scale: s)
                    .position(x: hunterLeft + 21 * s, y: hunterTop + 25 * s)
            }

            if t >= Timing.chatterShows, t < Timing.chatterHides {
                ufoBubble(AdventureGame.vatAlienChatter, anchor: CGPoint(x: vatX, y: vatTop - 4 * s), screen: screen,
                          color: Color(red: 0.49, green: 1, blue: 0.49))
            }
            // Musical notes while he whistles.
            if t >= Timing.toTableStarts, t < Timing.place + 0.4 {
                ForEach(0..<2, id: \.self) { i in
                    let p = ((t - Timing.toTableStarts) * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    MusicNote(pixel: s)
                        .fill(Color.pixelCream)
                        .frame(width: 5 * s, height: 7 * s)
                        .opacity(1 - p)
                        .position(x: hunterLeft + 22 * s + CGFloat(p) * 8 * s, y: hunterTop - CGFloat(p) * 12 * s)
                }
            }

            Color.black
                .opacity(min(max((t - Timing.fadeStarts) / Timing.fadeDuration, 0), 1))
                .allowsHitTesting(false)
        }
        .frame(width: screen.width, height: screen.height)
    }
}

/// A tiny pixel eighth note: a round head, a stem, and a flag.
private nonisolated struct MusicNote: Shape {
    let pixel: CGFloat

    func path(in rect: CGRect) -> Path {
        let p = pixel
        var path = Path()
        // Head (bottom left), stem up its right side, and a flag off the top.
        path.addRect(CGRect(x: rect.minX, y: rect.minY + 5 * p, width: 3 * p, height: 2 * p))
        path.addRect(CGRect(x: rect.minX + 2 * p, y: rect.minY, width: p, height: 6 * p))
        path.addRect(CGRect(x: rect.minX + 3 * p, y: rect.minY + p, width: p, height: p))
        path.addRect(CGRect(x: rect.minX + 4 * p, y: rect.minY + 2 * p, width: p, height: 2 * p))
        return path
    }
}

#if DEBUG
#Preview("Wrecked lab") {
    AdventureView(game: .preview(scene: 14, phase: .wreckedLab(start: .now.addingTimeInterval(-4.6)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Pristine lab") {
    AdventureView(game: .preview(scene: 14, phase: .pristineLab(start: .now.addingTimeInterval(-4.0)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Pristine lab: clipboard") {
    AdventureView(game: .preview(scene: 14, phase: .pristineLab(start: .now.addingTimeInterval(-6.8)), route: .restricted))
        .ignoresSafeArea()
}
#endif
