//
//  VatLabView.swift
//  doveHunt
//
//  Aboard the UFO: the specimen-vat lab. A dove and a mallard float in vats of green goo;
//  the hunter shoots them on instinct, they rise as skeletons and chase off an alien scientist,
//  and the hunter picks up the clipboard he dropped.
//

import SwiftUI

struct VatLabView: View {
    let game: AdventureGame
    let step: VatStep
    let start: Date
    let screen: CGSize
    let now: Date
    var requiresLandscape = false

    private typealias Timing = AdventureGame.VatTiming

    private static let goo = Color(red: 0.25, green: 0.75, blue: 0.35)

    var body: some View {
        let layout = UFOInteriorLayout(screen: screen)
        let s = layout.scale
        let w = screen.width
        let elapsed = max(0, now.timeIntervalSince(start))
        // The scripted part's clock; once it's over everything holds its final pose.
        let t = step == .scripted ? elapsed : 1000
        let collectedTime: TimeInterval? = step == .collected ? elapsed : nil
        let leavingTime: TimeInterval? = step == .leaving ? elapsed : nil

        // The hunter: walks in, stands, and (after the pickup) walks off to the right.
        let hunterWidth = AppArt.hunter.width * s
        let standX = (w * 0.16).rounded()
        let walkIn = min(t / Timing.walkInDuration, 1)
        let leave = leavingTime.map { min($0 / Timing.leaveDuration, 1) } ?? 0
        let hunterX = -hunterWidth / 2 + (standX + hunterWidth / 2) * walkIn + (w + hunterWidth - standX) * leave
        let hunterWalking = walkIn < 1 || (leave > 0 && leave < 1)
        // Stopped dead and wide-eyed at the sight of the vats, then the shotgun comes level at them.
        let aiming = t >= Timing.aimStarts && t < Timing.aimEnds
        let hunterSprite: String = {
            if hunterWalking { return AppArt.hunterWalkCycle[Int(elapsed * AdventureGame.walkFrameRate) % AppArt.hunterWalkCycle.count] }
            if t >= Timing.walkInDuration, t < Timing.stunnedEnds { return "hunter_shocked" }
            if aiming { return "hunter_aim" }
            if t >= Timing.shockedStarts, t < Timing.shockedEnds { return "hunter_shocked" }
            return "hunter"
        }()
        // A little kick back with each shot.
        let recoil: CGFloat = aiming && game.isFiring ? -2 * s : 0
        let hunterCenter = layout.standing(AppArt.hunter, x: hunterX + recoil)
        let hunterTop = hunterCenter.y - AppArt.hunter.height * s / 2

        // The vats, and when each one is shot.
        let vatX = [(w * 0.42).rounded(), (w * 0.57).rounded()]
        let shotAt = [Timing.firstShot, Timing.secondShot]
        let vatCenterY = layout.standing(AppArt.vat, x: 0).y
        let vatTop = vatCenterY - AppArt.vat.height * s / 2
        let floorY = layout.floorTop + 3 * s

        // The scientist: runs in from the right, drops his clipboard, screams, and flees.
        let arrive = min(max((t - Timing.scientistArrives) / Timing.scientistArriveDuration, 0), 1)
        let flee = min(max((t - Timing.scientistFlees) / Timing.scientistFleeDuration, 0), 1)
        let scientistStop = (w * 0.76).rounded()
        let scientistX = (w + 40) + (scientistStop - (w + 40)) * arrive + (w + 80 - scientistStop) * flee
        let scared = t >= Timing.drop
        let scientistMoving = (arrive > 0 && arrive < 1) || (flee > 0 && flee < 1)
        let stride = Int(elapsed * 10).isMultiple(of: 2) ? "_walk_a" : "_walk_b"
        let scientistSprite = (scared ? "scientist_scared" : "scientist") + (scientistMoving ? stride : "")
        let scientistFacesRight = flee > 0

        // The clipboard: dropped at his feet, waiting to be picked up.
        let clipboardRestX = scientistStop - 10 * s
        let clipboardRestY = floorY - AppArt.clipboard.height * s / 2 + s
        let fall = min(max((t - Timing.drop) / Timing.clipboardFall, 0), 1)
        let clipboardHeldY = layout.standing(AppArt.alien, x: 0).y - 2 * s
        let clipboardY = clipboardHeldY + (clipboardRestY - clipboardHeldY) * fall * fall
        let showsLooseClipboard = t >= Timing.drop && step == .scripted || step == .waiting

        ZStack(alignment: .topLeading) {
            UFOInteriorBackground(layout: layout, now: now)

            // Spilled goo spreading across the deck.
            ForEach(0..<2, id: \.self) { i in
                let since = t - shotAt[i]
                if since >= 0 {
                    let spread = min(since / 0.6, 1)
                    Ellipse()
                        .fill(Self.goo.opacity(0.85))
                        .frame(width: (44 * spread * s).rounded(), height: 4 * s)
                        .position(x: vatX[i], y: floorY - s)
                }
            }

            ForEach(0..<2, id: \.self) { i in
                vat(index: i, x: vatX[i], centerY: vatCenterY, top: vatTop, floorY: floorY, shotAt: shotAt[i], t: t, s: s)
            }

            if showsLooseClipboard {
                AppSprite(name: "clipboard", size: AppArt.clipboard, scale: s)
                    .position(x: clipboardRestX, y: clipboardY.rounded())
            }

            AppSprite(name: scientistSprite, size: AppArt.alien, scale: s)
                .scaleEffect(x: scientistFacesRight ? 1 : -1)
                .position(layout.standing(AppArt.alien, x: scientistX))

            ForEach(0..<2, id: \.self) { i in
                skeleton(index: i, homeX: vatX[i], floorY: floorY, t: t, elapsed: elapsed, s: s, screenWidth: w)
            }

            AppSprite(name: hunterSprite, size: AppArt.hunter, scale: s)
                .position(hunterCenter)
            if game.isFiring {
                let muzzle = aiming ? AppArt.hunterAimMuzzle : AppArt.hunterMuzzle
                AppSprite(name: "muzzle_flash", size: AppArt.muzzleFlash, scale: s)
                    .position(x: hunterX + recoil - hunterWidth / 2 + muzzle.x * s, y: hunterTop + muzzle.y * s)
            }

            if t >= Timing.screamShows, t < Timing.screamHides {
                ufoBubble(AdventureGame.scientistScream, anchor: layout.above(AppArt.alien, x: scientistX), screen: screen)
            }

            // The clipboard, waiting under a bobbing arrow.
            if step == .waiting {
                let bob: CGFloat = (sin(now.timeIntervalSinceReferenceDate * 4) * 1.5).rounded() * s
                AppSprite(name: "arrow_down", size: AppArt.arrowDown, scale: s)
                    .position(x: clipboardRestX, y: clipboardRestY - (AppArt.clipboard.height / 2 + 3 + AppArt.arrowDown.height / 2) * s + bob)
                    .allowsHitTesting(false)
                Color.clear
                    .frame(width: (AppArt.clipboard.width + 14) * s, height: (AppArt.clipboard.height + AppArt.arrowDown.height + 10) * s)
                    .contentShape(Rectangle())
                    .onTapGesture { if !requiresLandscape { game.collectClipboard() } }
                    .position(x: clipboardRestX, y: clipboardRestY - (AppArt.arrowDown.height + 4) * s / 2)
                    .accessibilityElement()
                    .accessibilityLabel("Clipboard")
                    .accessibilityHint("Adds it to your inventory")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { if !requiresLandscape { game.collectClipboard() } }
            }
            if let collectedTime, collectedTime < Timing.collectedShows {
                ufoBubble("Clipboard added to inventory!", anchor: CGPoint(x: clipboardRestX, y: clipboardRestY - AppArt.clipboard.height * s / 2 - 4), screen: screen)
            }

            Color.black
                .opacity(fade(elapsed: elapsed, leavingTime: leavingTime))
                .allowsHitTesting(false)
        }
        .frame(width: screen.width, height: screen.height)
    }

    /// Fading in at the start, and out as he walks off after the pickup.
    private func fade(elapsed: TimeInterval, leavingTime: TimeInterval?) -> Double {
        if step == .scripted { return max(0, 1 - elapsed / Timing.fadeIn) }
        guard let leavingTime else { return 0 }
        return min(max((leavingTime - (Timing.leaveDuration - Timing.fadeDuration + 0.2)) / Timing.fadeDuration, 0), 1)
    }

    /// One vat: the goo and its floating bird, the glass, the base's blinking LEDs, and the
    /// alarm light on top. Shot, it shatters: the goo gushes out and the bird drops to the deck.
    @ViewBuilder
    private func vat(index: Int, x: CGFloat, centerY: CGFloat, top: CGFloat, floorY: CGFloat, shotAt: TimeInterval, t: TimeInterval, s: CGFloat) -> some View {
        let broken = t >= shotAt
        let since = t - shotAt
        let clock = now.timeIntervalSinceReferenceDate
        let isDove = index == 0
        let birdSize = isDove ? AppArt.dove : AppArt.mallard
        let birdName = isDove ? "dove_wings_down" : "mallard_wings_down"
        let bob: CGFloat = (sin(clock * 1.4 + Double(index) * 2) * 2).rounded() * s
        let floating = CGPoint(x: x, y: top + 22 * s + bob)
        let onFloor = CGPoint(x: x, y: floorY - birdSize.height * s / 2 + s)
        let birdFall = min(max(since / AdventureGame.VatTiming.birdFall, 0), 1)

        if !broken {
            AppSprite(name: "vat_back", size: AppArt.vat, scale: s)
                .position(x: x, y: centerY)
            // Presumed dead: belly-up, bobbing in the goo.
            AppSprite(name: birdName, size: birdSize, scale: s)
                .scaleEffect(x: isDove ? 1 : -1, y: -1)
                .position(floating)
            AppSprite(name: "vat_front", size: AppArt.vat, scale: s)
                .position(x: x, y: centerY)
        } else {
            AppSprite(name: "vat_broken", size: AppArt.vat, scale: s)
                .position(x: x, y: centerY)
            // Goo gushing out of the broken vat.
            if since < AdventureGame.VatTiming.liquidFall {
                let p = since / AdventureGame.VatTiming.liquidFall
                ForEach(0..<6, id: \.self) { drop in
                    let dx = CGFloat(drop - 3) * 4 * s * (0.5 + p)
                    let y = top + 30 * s + (floorY - top - 30 * s) * min(1, p * (0.8 + Double(drop) * 0.08))
                    Rectangle()
                        .fill(Self.goo)
                        .frame(width: 2 * s, height: 3 * s)
                        .position(x: x + dx, y: y)
                }
            }
            // The bird drops to the deck, until it rises again as a skeleton.
            if t < AdventureGame.VatTiming.transform {
                AppSprite(name: birdName, size: birdSize, scale: s)
                    .scaleEffect(x: isDove ? 1 : -1, y: -1)
                    .position(x: x, y: floating.y + (onFloor.y - floating.y) * birdFall * birdFall)
            }
        }

        // Blinking LEDs on the base, and the alarm light on top (dark until the glass breaks).
        HStack(spacing: s) {
            ForEach(0..<3, id: \.self) { led in
                let on = Int(clock * 3 + Double(led + index * 2)).isMultiple(of: 2)
                Rectangle()
                    .fill([Color.green, Color.cyan, Color.yellow][led].opacity(on ? 1 : 0.3))
                    .frame(width: 2 * s, height: 2 * s)
            }
        }
        .position(x: x, y: top + 43 * s)
        let alarmOn = broken && Int(clock * 4).isMultiple(of: 2)
        Rectangle()
            .fill(alarmOn ? Color(red: 1, green: 0.2, blue: 0.2) : Color(red: 0.35, green: 0.08, blue: 0.08))
            .frame(width: 6 * s, height: 3 * s)
            .overlay(Rectangle().strokeBorder(Color.black.opacity(0.6), lineWidth: max(1, s / 2)))
            .shadow(color: alarmOn ? .red : .clear, radius: alarmOn ? 4 * s : 0)
            .position(x: x, y: top - 1.5 * s)
    }

    /// A risen bird skeleton: it pops up where the bird fell, turns on the scientist with its
    /// wing bones out, and shuffles after him.
    @ViewBuilder
    private func skeleton(index: Int, homeX: CGFloat, floorY: CGFloat, t: TimeInterval, elapsed: TimeInterval, s: CGFloat, screenWidth: CGFloat) -> some View {
        let kind = index == 0 ? "dove" : "mallard"
        let size = index == 0 ? AppArt.skeletonDove : AppArt.skeletonMallard
        let since = t - AdventureGame.VatTiming.transform
        let chase = min(max((t - AdventureGame.VatTiming.chaseStarts - Double(index) * 0.2) / AdventureGame.VatTiming.chaseDuration, 0), 1)
        if since >= 0, chase < 1 {
            let rise = min(since / 0.35, 1)
            let reaching = t >= AdventureGame.VatTiming.reachStarts
            let frame = Int(elapsed * (chase > 0 ? 6 : 2) + Double(index)).isMultiple(of: 2) ? "_reach_a" : "_reach_b"
            let x = homeX + (screenWidth + 60 - homeX) * chase
            let y = floorY - size.height * s / 2 + (1 - rise) * size.height * s * 0.5
            AppSprite(name: "skeleton_\(kind)" + (reaching ? frame : ""), size: size, scale: s)
                .position(x: x.rounded(), y: y.rounded())
            // A puff as the bird transforms.
            if since < 0.45 {
                AppSprite(name: "feather_poof", size: AppArt.poof, scale: s)
                    .scaleEffect(0.8 + since)
                    .opacity(1 - since / 0.45)
                    .position(x: homeX, y: floorY - size.height * s / 2)
            }
        }
    }
}

#if DEBUG
#Preview("Vats: floating") {
    AdventureView(game: .preview(scene: 14, phase: .vats(.scripted, start: .now.addingTimeInterval(-2.2)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Vats: aim") {
    AdventureView(game: .preview(scene: 14, phase: .vats(.scripted, start: .now.addingTimeInterval(-3.3)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Vats: shattered") {
    AdventureView(game: .preview(scene: 14, phase: .vats(.scripted, start: .now.addingTimeInterval(-4.2)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Vats: scream") {
    AdventureView(game: .preview(scene: 14, phase: .vats(.scripted, start: .now.addingTimeInterval(-7.3)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Vats: chase") {
    AdventureView(game: .preview(scene: 14, phase: .vats(.scripted, start: .now.addingTimeInterval(-9.0)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Vats: clipboard") {
    AdventureView(game: .preview(scene: 14, phase: .vats(.waiting, start: .now), route: .restricted))
        .ignoresSafeArea()
}
#endif
