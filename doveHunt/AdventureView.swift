//
//  AdventureView.swift
//  doveHunt
//
//  Renders the side-scrolling adventure. The world is a continuous strip of screen-wide
//  scenes laid end to end over a seamlessly tiling background; a camera pans along it.
//  Everything is positioned in art pixels and snapped to the pixel grid.
//

import SwiftUI

struct AdventureView: View {
    let game: AdventureGame
    /// A phone held in portrait: the quest only plays in landscape. The home screen still
    /// shows, but nothing can be shot until the device is rotated.
    var requiresLandscape = false
    /// A short (landscape phone) screen, which uses the compact title header.
    var compactHeader = false

    @AppStorage(AppSettings.animatedDovesKey) private var animatedDoves = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Approximate height of the header overlay (title + score + hint, or the small HUD), in points.
    private var headerHeight: CGFloat {
        game.showsTitle ? (compactHeader ? 150 : 270) : (compactHeader ? 50 : 80)
    }

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let art = AppArt.background(for: screen)
            // One art pixel in points. The art fills the screen, anchored to the bottom so the
            // grass and hunter are always visible; one scene is exactly one screen wide.
            let scale = max(screen.width / art.size.width, screen.height / art.size.height)
            let world = AdventureWorld(
                scale: scale,
                originY: screen.height - art.size.height * scale,
                sceneWidth: (screen.width / scale).rounded(.down),
                screen: screen
            )
            let bobbing = animatedDoves && !reduceMotion

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(bobbing || game.isMoving || !game.poofs.isEmpty))) { context in
                let now = context.date
                let time = bobbing ? now.timeIntervalSinceReferenceDate : 0
                let frame = AdventureFrame(game: game, now: now, sceneWidth: world.sceneWidth, scale: world.scale)

                if case .interior(let step, let start) = game.phase {
                    InteriorView(game: game, step: step, stepStart: start, screen: screen, now: now)
                } else if game.phase == .console {
                    ConsoleView(game: game, screen: screen, now: now, requiresLandscape: requiresLandscape)
                } else if case .aboard(let start) = game.phase {
                    AboardView(screen: screen, now: now, start: start)
                } else if case .aliens(let start) = game.phase {
                    AlienLabView(screen: screen, now: now, start: start)
                } else if case .vats(let step, let start) = game.phase {
                    VatLabView(game: game, step: step, start: start, screen: screen, now: now, requiresLandscape: requiresLandscape)
                } else if case .wreckedLab(let start) = game.phase {
                    WreckedLabView(screen: screen, now: now, start: start)
                } else if case .pristineLab(let start) = game.phase {
                    PristineLabView(screen: screen, now: now, start: start)
                } else {
                ZStack(alignment: .topLeading) {
                    background(art: art, world: world, camera: frame.camera)

                    // Tapping anywhere that isn't a dove: fire at the sky, enter the cabin, or start over.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { handleBackgroundTap() }
                        .accessibilityLabel(backgroundTapLabel)
                        .accessibilityAddTraits(.isButton)

                    ForEach(visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth), id: \.self) { sceneIndex in
                        props(sceneIndex: sceneIndex, world: world, frame: frame)
                    }

                    // Dusk falls after the bear: the sky and scenery warm and darken (characters stay bright).
                    // Past the restricted gate, it's night.
                    if game.isNight {
                        night(screen: screen, world: world, now: now)
                    } else if let duskStart = game.duskStart {
                        dusk(amount: min(max(now.timeIntervalSince(duskStart) / AdventureGame.duskFadeDuration, 0), 1))
                    }

                    ForEach(visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth), id: \.self) { sceneIndex in
                        let spec = game.spec(sceneIndex)
                        if spec.hasBearEvent {
                            bearCast(sceneIndex: sceneIndex, world: world, frame: frame, now: now)
                        } else if spec.hasStreamEvent {
                            streamCast(sceneIndex: sceneIndex, world: world, frame: frame, now: now)
                        } else if spec.hasForkEvent {
                            forkCast(sceneIndex: sceneIndex, world: world, frame: frame, time: time, now: now)
                        } else if spec.hasCampsiteEvent {
                            campsiteCast(sceneIndex: sceneIndex, world: world, frame: frame, time: time, now: now)
                        }
                    }

                    ForEach(visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth), id: \.self) { sceneIndex in
                        doves(sceneIndex: sceneIndex, world: world, frame: frame, time: time, now: now)
                    }

                    ForEach(visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth), id: \.self) { sceneIndex in
                        if game.spec(sceneIndex).hasPondEvent {
                            pondCast(sceneIndex: sceneIndex, world: world, frame: frame, now: now)
                        }
                    }

                    ForEach(visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth), id: \.self) { sceneIndex in
                        if game.spec(sceneIndex).hasTackleBoxEvent {
                            tackleCast(sceneIndex: sceneIndex, world: world, frame: frame, time: time, now: now)
                        }
                    }

                    ForEach(visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth), id: \.self) { sceneIndex in
                        if game.spec(sceneIndex).hasReunionEvent {
                            reunionCast(sceneIndex: sceneIndex, world: world, frame: frame, now: now)
                        }
                    }

                    if game.showsChimneyDove {
                        chimneyDove(world: world, frame: frame, time: time)
                    }

                    poofs(world: world, frame: frame, now: now)

                    if case .abduction(let start) = game.phase {
                        abductionCast(world: world, frame: frame, now: now, start: start, rings: false)
                    }

                    hunter(world: world, frame: frame)

                    if case .abduction(let start) = game.phase {
                        abductionCast(world: world, frame: frame, now: now, start: start, rings: true)
                    }

                    // A gusting wind whenever the restricted route is on screen.
                    if !reduceMotion, visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth).contains(where: { game.spec($0).isEerie }) {
                        wind(screen: screen, world: world, now: now)
                    }

                    // Drawn over the hunter so the droppings land on his clothes.
                    if case .poop(let start) = game.phase {
                        poopCast(world: world, frame: frame, time: time, now: now, start: start)
                    }

                    if case .reunion(.returned, _) = game.phase {
                        noticeCard("Tackle box removed from inventory", sprite: InventoryItem.tackleBox, screen: screen)
                    }

                    if game.phase == .cabinPrompt {
                        cabinPrompt(world: world, frame: frame, time: time)
                    }

                    Color.black
                        .opacity(frame.blackout)
                        .allowsHitTesting(false)

                    if case .finished(let start) = game.phase, now.timeIntervalSince(start) >= 1 {
                        toBeContinued(time: now.timeIntervalSinceReferenceDate, screenWidth: screen.width)
                    }
                }
                .frame(width: screen.width, height: screen.height)
                }
            }
        }
        .overlay {
            // Mid-quest in portrait on a phone: pause behind a "rotate" card.
            if requiresLandscape && !game.showsTitle {
                RotateDeviceCard()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: game.shotCount)
        .sensoryFeedback(.success, trigger: game.inventory.count)
    }

    // MARK: Layers

    /// The sky-and-meadow background, tiled seamlessly across the world.
    private func background(art: (name: String, size: CGSize), world: AdventureWorld, camera: CGFloat) -> some View {
        let tileWidth = art.size.width
        let first = Int((camera / tileWidth).rounded(.down))
        let last = Int(((camera + world.sceneWidth) / tileWidth).rounded(.down))
        return ForEach(first...max(first, last), id: \.self) { tile in
            AppSprite(name: art.name, size: art.size, scale: world.scale)
                .position(world.point(CGFloat(tile) * tileWidth + tileWidth / 2, art.size.height / 2, camera: camera))
        }
        .allowsHitTesting(false)
    }

    private func props(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame) -> some View {
        let scene = game.spec(sceneIndex)
        return ForEach(scene.props.indices, id: \.self) { index in
            let prop = scene.props[index]
            let centerX = world.sceneOrigin(sceneIndex) + (prop.fractionX * world.sceneWidth).rounded()
            switch prop.kind {
            case .tree:
                propSprite("prop_tree", size: AppArt.tree, centerX: centerX, sink: 2, world: world, frame: frame)
            case .pine:
                propSprite("prop_pine", size: AppArt.pine, centerX: centerX, sink: 2, world: world, frame: frame)
            case .mountains:
                // Distant range sitting on the horizon, behind the rest of the scenery.
                propSprite("prop_mountains", size: AppArt.mountains, centerX: centerX, sink: -2, world: world, frame: frame)
            case .bush:
                propSprite("prop_bush", size: AppArt.bush, centerX: centerX, sink: 2, world: world, frame: frame)
            case .pond:
                let layout = PondLayout(sceneWidth: world.sceneWidth)
                AppSprite(name: layout.pondSprite, size: layout.pondSize, scale: world.scale)
                    .position(world.point(world.sceneOrigin(sceneIndex) + layout.pondLeft + layout.pondSize.width / 2,
                                          AppArt.groundTop + 1 + layout.pondSize.height / 2, camera: frame.camera))
            case .stream:
                let layout = StreamLayout(sceneWidth: world.sceneWidth)
                AppSprite(name: "prop_stream", size: AppArt.stream, scale: world.scale)
                    .position(world.point(world.sceneOrigin(sceneIndex) + layout.streamLeft + AppArt.stream.width / 2,
                                          AppArt.groundTop + 1 + AppArt.stream.height / 2, camera: frame.camera))
            case .dirtPath:
                // Tiled across the whole scene, under the hunter's boots.
                let tiles = Int((world.sceneWidth / AppArt.dirtPath.width).rounded(.up))
                ForEach(0..<tiles, id: \.self) { tile in
                    AppSprite(name: "prop_dirt_path", size: AppArt.dirtPath, scale: world.scale)
                        .position(world.point(world.sceneOrigin(sceneIndex) + CGFloat(tile) * AppArt.dirtPath.width + AppArt.dirtPath.width / 2,
                                              AppArt.groundTop + 1 + AppArt.dirtPath.height / 2, camera: frame.camera))
                }
            case .farMountain:
                // Far behind the restricted gate; its trail starts right behind the gate.
                let layout = ForkLayout(sceneWidth: world.sceneWidth, scale: world.scale)
                let left = layout.fenceLeft + AppArt.fenceGateWidth / 2 - AppArt.farMountainTrailX
                propSprite("prop_far_mountain", size: AppArt.farMountain, centerX: world.sceneOrigin(sceneIndex) + left + AppArt.farMountain.width / 2,
                           sink: -1, world: world, frame: frame)
            case .cabin:
                propSprite(frame.doorOpen ? "cabin_open" : "cabin_closed", size: AppArt.cabin,
                           centerX: world.sceneOrigin(sceneIndex) + world.cabinCenter(fraction: prop.fractionX),
                           sink: 3, world: world, frame: frame)
            }
        }
        .allowsHitTesting(false)
    }

    /// A sprite standing on the grass: its bottom row sits `sink` pixels below the grass line.
    private func propSprite(_ name: String, size: CGSize, centerX: CGFloat, sink: CGFloat, world: AdventureWorld, frame: AdventureFrame) -> some View {
        AppSprite(name: name, size: size, scale: world.scale)
            .position(world.point(centerX, AppArt.groundTop + sink - size.height / 2, camera: frame.camera))
    }

    private func doves(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, time: Double, now: Date) -> some View {
        let scene = game.spec(sceneIndex)
        let canShoot = sceneIndex == game.scene && game.phase == .hunting && !requiresLandscape
        // Pond and tackle box scene doves only appear once they're released, then fly in from the right edge.
        let release: Date? = scene.dovesFlyIn ? (sceneIndex == game.scene ? game.dovesReleased : nil) : nil
        let hidden = scene.dovesFlyIn && release == nil && !scene.birdsStartOnWater
        // Stream mallards float on the water until they take off.
        let floating = scene.birdsStartOnWater && release == nil
        let pond = PondLayout(sceneWidth: world.sceneWidth)
        // Keep doves below the header overlay on short screens.
        let belowHeader = world.visibleMinY + headerHeight / world.scale + AppArt.dove.height

        return ForEach(scene.doves.indices, id: \.self) { index in
            if !hidden, !game.isDown(scene: sceneIndex, dove: index) {
                let dove = scene.doves[index]
                let edge = AppArt.dove.width / 2 + 4
                let wantedX = scene.hasPondEvent ? pond.doveX(index) : (dove.fractionX * world.sceneWidth).rounded()
                let localX = min(max(wantedX, edge), world.sceneWidth - edge)
                let restX = world.sceneOrigin(sceneIndex) + localX
                let lift = scene.hasPondEvent ? pond.doveLift : 0
                let restY = min(max(AppArt.groundTop - dove.aboveGround - lift, belowHeader), AppArt.groundTop - AppArt.dove.height).rounded()
                // Gentle hover, snapped to whole art pixels for retro motion.
                let dx = (sin(time * 0.7 + dove.phase) * 3).rounded()
                let dy = (sin(time * 1.6 + dove.phase) * 2).rounded()
                let wingsUp = Int(time * 4 + dove.phase).isMultiple(of: 2)
                let hover = CGPoint(x: restX + dx, y: restY + dy)
                // Released doves fly in one after another from past the right edge, gliding down into place.
                let flightStart = release?.addingTimeInterval(Double(index) * AdventureGame.PondTiming.doveFlyInStagger)
                let flight: CGFloat = flightStart.map { CGFloat(min(max(now.timeIntervalSince($0) / AdventureGame.PondTiming.doveFlyIn, 0), 1)) } ?? 1
                let eased = 1 - (1 - flight) * (1 - flight)
                // Stream birds take off from where they float; the others fly in from past the right edge.
                let stream = StreamLayout(sceneWidth: world.sceneWidth)
                let waterX = min(max(restX, world.sceneOrigin(sceneIndex) + stream.streamLeft + 14),
                                 world.sceneOrigin(sceneIndex) + stream.streamLeft + AppArt.stream.width - 14)
                let entry = scene.birdsStartOnWater
                    ? CGPoint(x: waterX, y: StreamLayout.waterY - 1)
                    : CGPoint(x: world.sceneOrigin(sceneIndex) + world.sceneWidth + AppArt.dove.width, y: restY - 24)
                let flyingIn = flight < 1 && !scene.birdsStartOnWater
                // A wounded mallard reels for a moment: knocked down a few pixels with a shake.
                let hitAge: TimeInterval? = game.woundedAt(scene: sceneIndex, dove: index).map { now.timeIntervalSince($0) }
                let reeling = hitAge.map { $0 < AdventureGame.woundDuration } ?? false
                let reel = reeling ? 1 - (hitAge ?? 0) / AdventureGame.woundDuration : 0
                let shake: CGFloat = reeling ? (sin((hitAge ?? 0) * 70) * 1.5).rounded() : 0
                let knock: CGFloat = (4 * reel).rounded()
                let position = CGPoint(
                    x: (entry.x + (hover.x - entry.x) * eased).rounded() + shake,
                    y: (entry.y + (hover.y - entry.y) * eased).rounded() + knock
                )
                let isMallard = dove.kind == .mallard
                let spriteName = floating ? "mallard_float" : (isMallard
                    ? (reeling ? "mallard_hit" : (wingsUp ? "mallard_wings_up" : "mallard_wings_down"))
                    : (wingsUp ? "dove_wings_up" : "dove_wings_down"))
                let spriteSize = floating ? AppArt.mallardFloat : (isMallard ? AppArt.mallard : AppArt.dove)
                // Bobbing gently on the stream.
                let floatBob: CGFloat = sin(time * 2 + dove.phase) > 0 ? 0 : 1
                let drawn = floating ? CGPoint(x: waterX + (sin(time * 0.5 + dove.phase) * 2).rounded(), y: entry.y + floatBob) : position

                AppSprite(name: spriteName, size: spriteSize, scale: world.scale)
                    .scaleEffect(x: dove.facesRight && !flyingIn ? 1 : -1)
                    // A slightly larger target than the sprite, for comfortable tapping.
                    .padding(3 * world.scale)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if canShoot { game.shoot(dove: index, at: position) }
                    }
                    .position(world.point(drawn.x, drawn.y, camera: frame.camera))
                    .accessibilityElement()
                    .accessibilityLabel(isMallard ? (hitAge == nil ? "Mallard" : "Wounded mallard") : "Dove")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { if canShoot { game.shoot(dove: index, at: position) } }
            }
        }
    }

    /// The fisherman, his rod and line, and Max, with their scripted moments and speech.
    @ViewBuilder
    private func pondCast(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, now: Date) -> some View {
        if !game.pondEventDone {
            let layout = PondLayout(sceneWidth: world.sceneWidth)
            let origin = world.sceneOrigin(sceneIndex)
            let cast = PondCast(phase: sceneIndex == game.scene ? game.phase : .hunting, now: now, layout: layout, sceneWidth: world.sceneWidth)
            let fishermanTop = AppArt.groundTop + 3 - AppArt.fisherman.height
            let dogTop = AppArt.groundTop + 3 - AppArt.dog.height
            let point = { (x: CGFloat, y: CGFloat) in world.point(origin + x, y, camera: frame.camera) }

            ZStack(alignment: .topLeading) {
                if cast.showsRod {
                    // The line drops from the rod tip into the pond, with a red-and-white bobber.
                    let rod = layout.rodTip
                    Rectangle()
                        .fill(Color(red: 0.88, green: 0.88, blue: 0.92))
                        .frame(width: world.scale, height: (layout.waterY - rod.y) * world.scale)
                        .position(point(rod.x + 0.5, (rod.y + layout.waterY) / 2))
                    Rectangle()
                        .fill(Color(red: 0.86, green: 0.16, blue: 0.16))
                        .frame(width: world.scale, height: world.scale)
                        .position(point(rod.x + 0.5, layout.waterY - 0.5))
                    AppSprite(name: layout.rodSprite, size: layout.rodSize, scale: world.scale)
                        .scaleEffect(x: -1)
                        .position(point(layout.rodLeft + layout.rodSize.width / 2, layout.rodTop + layout.rodSize.height / 2))
                }

                AppSprite(name: cast.fishermanSprite, size: AppArt.fisherman, scale: world.scale)
                    .scaleEffect(x: cast.fishermanFacesRight ? 1 : -1)
                    .position(point(cast.fishermanLeft + AppArt.fisherman.width / 2, fishermanTop + AppArt.fisherman.height / 2))

                AppSprite(name: cast.dogSprite, size: AppArt.dog, scale: world.scale)
                    .scaleEffect(x: cast.dogFacesRight ? 1 : -1)
                    .position(point(cast.dogLeft + AppArt.dog.width / 2, dogTop + AppArt.dog.height / 2))
            }
            .allowsHitTesting(false)

            if let line = cast.fishermanLine {
                speech(line, anchor: point(cast.fishermanLeft + AppArt.fishermanBodyCenterX, fishermanTop), screen: world.screen)
            }
            if cast.showsBang {
                speech("!", anchor: point(cast.dogLeft + (cast.dogFacesRight ? 22 : 8), dogTop + 2), screen: world.screen, large: true)
            }
        }
        if sceneIndex == game.scene, case .pond(.whoops, let start) = game.phase,
           now.timeIntervalSince(start) >= AdventureGame.PondTiming.whoopsShows {
            speech("Whoops", anchor: world.point(frame.hunterLeft + AppArt.hunterBodyCenterX, AppArt.groundTop + 3 - AppArt.hunter.height, camera: frame.camera), screen: world.screen)
        }
    }

    /// The tackle box scene: the fisherman (carrying his tackle box) and Max bolt off to the
    /// right, the box drops into the grass, and a bobbing arrow asks the player to tap it.
    @ViewBuilder
    private func tackleCast(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, time: Double, now: Date) -> some View {
        let layout = TackleLayout(sceneWidth: world.sceneWidth)
        let origin = world.sceneOrigin(sceneIndex)
        let cast = TackleCast(phase: sceneIndex == game.scene ? game.phase : .hunting, now: now, layout: layout,
                              eventDone: game.tackleEventDone, sceneWidth: world.sceneWidth)
        let fishermanTop = AppArt.groundTop + 3 - AppArt.fisherman.height
        let dogTop = AppArt.groundTop + 3 - AppArt.dog.height
        let point = { (x: CGFloat, y: CGFloat) in world.point(origin + x, y, camera: frame.camera) }

        ZStack(alignment: .topLeading) {
            if cast.showsPeople {
                AppSprite(name: cast.fishermanSprite, size: AppArt.fisherman, scale: world.scale)
                    .scaleEffect(x: cast.fishermanFacesRight ? 1 : -1)
                    .position(point(cast.fishermanLeft + AppArt.fisherman.width / 2, fishermanTop + AppArt.fisherman.height / 2))
                AppSprite(name: cast.dogSprite, size: AppArt.dog, scale: world.scale)
                    .scaleEffect(x: cast.dogFacesRight ? 1 : -1)
                    .position(point(cast.dogLeft + AppArt.dog.width / 2, dogTop + AppArt.dog.height / 2))
            }
            if let box = cast.boxCenter {
                AppSprite(name: "tackle_box", size: AppArt.tackleBox, scale: world.scale)
                    .position(point(box.x, box.y))
            }
        }
        .allowsHitTesting(false)

        if cast.showsBang {
            speech("!", anchor: point(cast.dogLeft + (cast.dogFacesRight ? 22 : 8), dogTop + 2), screen: world.screen, large: true)
        }
        if let line = cast.fishermanLine {
            speech(line, anchor: point(cast.fishermanLeft + AppArt.fishermanBodyCenterX, fishermanTop), screen: world.screen)
        }
        if cast.boxWaiting {
            let rest = layout.boxRest
            let bob: CGFloat = (sin(time * 4) * 1.5).rounded()
            let arrowY = rest.y - AppArt.tackleBox.height / 2 - 3 - AppArt.arrowDown.height / 2 + bob
            AppSprite(name: "arrow_down", size: AppArt.arrowDown, scale: world.scale)
                .position(point(rest.x, arrowY))
                .allowsHitTesting(false)
            // One generous target covering the box and its arrow.
            let targetHeight = AppArt.tackleBox.height + AppArt.arrowDown.height + 10
            Color.clear
                .frame(width: (AppArt.tackleBox.width + 12) * world.scale, height: targetHeight * world.scale)
                .contentShape(Rectangle())
                .onTapGesture { if !requiresLandscape { game.collectTackleBox() } }
                .position(point(rest.x, rest.y + AppArt.tackleBox.height / 2 + 2 - targetHeight / 2))
                .accessibilityElement()
                .accessibilityLabel("Tackle box")
                .accessibilityHint("Adds it to your inventory")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if !requiresLandscape { game.collectTackleBox() } }
        }
        if cast.showsCollected {
            speech("Tackle box added to inventory!", anchor: point(layout.boxRest.x, layout.boxRest.y - AppArt.tackleBox.height / 2), screen: world.screen)
        }
    }

    /// Night on the restricted route: a deep blue multiplied over the sky and scenery, with
    /// pixel stars twinkling in the sky.
    private func night(screen: CGSize, world: AdventureWorld, now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.26, green: 0.28, blue: 0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.multiply)
            Canvas { context, size in
                for i in 0..<40 {
                    // Fixed pseudo-random spots in the upper sky, each twinkling at its own pace.
                    let fx = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let fy = (sin(Double(i) * 78.233) * 12345.6789).truncatingRemainder(dividingBy: 1)
                    let x = (abs(fx) * size.width / world.scale).rounded() * world.scale
                    let y = (abs(fy) * size.height * 0.55 / world.scale).rounded() * world.scale
                    let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * (1.3 + Double(i % 5) * 0.4) + Double(i)))
                    let s = i % 7 == 0 ? world.scale * 2 : world.scale
                    context.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.white.opacity(twinkle * 0.85)))
                }
            }
        }
        .frame(width: screen.width, height: screen.height)
        .allowsHitTesting(false)
    }

    /// An eerie wind: pale streaks and dust rushing across the screen in slow gusts.
    private func wind(screen: CGSize, world: AdventureWorld, now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        return Canvas { context, size in
            let px = world.scale
            for i in 0..<18 {
                let seed = Double(i)
                let r1 = abs((sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1))
                let r2 = abs((sin(seed * 39.3468) * 24634.6345).truncatingRemainder(dividingBy: 1))
                let isDust = i % 3 == 0
                let speed = (isDust ? 420 : 260) + 220 * r2
                let length = isDust ? px * 2 : 40 + 90 * r1
                let span = size.width + length * 2
                let x = size.width + length - (t * speed + r1 * span).truncatingRemainder(dividingBy: span)
                // Dust skims low over the ground; streaks drift across the whole sky.
                let baseY = isDust ? size.height * (0.82 + 0.12 * r2) : size.height * (0.10 + 0.75 * r1)
                let y = ((baseY + sin(t * 2 + seed) * px * 3) / px).rounded() * px
                let gust = 0.5 + 0.5 * sin(t * 0.8 + seed * 0.7)
                let rect = CGRect(x: (x / px).rounded() * px, y: y, width: length, height: isDust ? px * 2 : px)
                context.fill(Path(rect), with: .color(.white.opacity((isDust ? 0.45 : 0.16) * gust)))
            }
        }
        .frame(width: screen.width, height: screen.height)
        .allowsHitTesting(false)
    }

    /// The UFO: it swoops in over the hunter, hovers, and sends green rings down its tractor beam.
    /// Drawn in two passes so the rings pass in front of the hunter while the beam glows behind him.
    @ViewBuilder
    private func abductionCast(world: AdventureWorld, frame: AdventureFrame, now: Date, start: Date, rings: Bool) -> some View {
        let t = max(0, now.timeIntervalSince(start))
        let hover = CGPoint(x: frame.camera + (world.sceneWidth / 2).rounded(), y: AppArt.groundTop - 100)
        let flyIn = min(max((t - AdventureGame.AbductionTiming.ufoArrives) / AdventureGame.AbductionTiming.ufoArriveDuration, 0), 1)
        let eased = 1 - (1 - flyIn) * (1 - flyIn)
        let entry = CGPoint(x: frame.camera + world.sceneWidth + 50, y: AppArt.groundTop - 160)
        let bob: CGFloat = flyIn >= 1 ? (sin(t * 3) * 2).rounded() : 0
        // With the hunter aboard, it speeds off to the left, climbing a little.
        let leave = min(max((t - AdventureGame.AbductionTiming.ufoLeaves) / AdventureGame.AbductionTiming.ufoLeaveDuration, 0), 1)
        let leaveEased = leave * leave
        let exitX = frame.camera - 60
        let arrivedX = entry.x + (hover.x - entry.x) * eased
        let arrivedY = entry.y + (hover.y - entry.y) * eased
        let ufo = CGPoint(x: (arrivedX + (exitX - arrivedX) * leaveEased).rounded(),
                          y: (arrivedY - 30 * leaveEased).rounded() + bob)
        let beamTop = ufo.y + AppArt.ufo.height / 2 - 2
        let ground = AppArt.groundTop + 3
        let beaming = t >= AdventureGame.AbductionTiming.beamStarts && t < AdventureGame.AbductionTiming.beamEnds

        if !rings {
            if beaming {
                // A soft green cone from the saucer down to the ground, pulsing.
                let glow = 0.16 + 0.08 * sin(t * 9)
                let top = world.point(ufo.x, beamTop, camera: frame.camera)
                let bottom = world.point(ufo.x, ground, camera: frame.camera)
                Path { path in
                    path.move(to: CGPoint(x: top.x - 6 * world.scale, y: top.y))
                    path.addLine(to: CGPoint(x: top.x + 6 * world.scale, y: top.y))
                    path.addLine(to: CGPoint(x: bottom.x + 18 * world.scale, y: bottom.y))
                    path.addLine(to: CGPoint(x: bottom.x - 18 * world.scale, y: bottom.y))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.49, green: 1, blue: 0.49).opacity(glow))
                .allowsHitTesting(false)
            }
            if flyIn > 0, leave < 1 {
                AppSprite(name: Int(t * 4).isMultiple(of: 2) ? "ufo_a" : "ufo_b", size: AppArt.ufo, scale: world.scale)
                    .position(world.point(ufo.x, ufo.y, camera: frame.camera))
                    .allowsHitTesting(false)
            }
        } else if beaming {
            // Rings travel down the beam, widening as they go.
            ForEach(0..<6, id: \.self) { index in
                let progress = ((t - AdventureGame.AbductionTiming.beamStarts) * 0.9 + Double(index) / 6).truncatingRemainder(dividingBy: 1)
                let y = beamTop + (ground - beamTop) * progress
                let widen = 0.5 + 1.0 * progress
                AppSprite(name: "beam_ring", size: AppArt.beamRing, scale: world.scale)
                    .scaleEffect(x: widen, y: 1)
                    .opacity(0.9 - 0.4 * progress)
                    .position(world.point(ufo.x, y.rounded(), camera: frame.camera))
            }
            .allowsHitTesting(false)
        }
    }

    /// The dusk tint: a warm, darkening gradient multiplied over the sky and scenery.
    private func dusk(amount: Double) -> some View {
        LinearGradient(
            colors: [Color(red: 0.42, green: 0.32, blue: 0.66), Color(red: 0.98, green: 0.66, blue: 0.46)],
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.multiply)
        .opacity(0.6 * amount)
        .allowsHitTesting(false)
    }

    /// A brief centered pop-up card (like "Tackle box removed from inventory").
    private func noticeCard(_ text: String, sprite item: InventoryItem?, screen: CGSize) -> some View {
        let lines = DialogText.wrap(text, maxCharacters: 20)
        return HStack(spacing: 16) {
            if let item {
                AppSprite(name: item.spriteName, size: item.spriteSize, scale: 3)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines.indices, id: \.self) { index in
                    PixelText(lines[index], pixelSize: 2)
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.92), ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(Color.pixelOrange, lineWidth: 3))
        .frame(width: screen.width, height: screen.height * 0.6)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    /// Three doves fly over the hunter (they can't be shot), each dropping a present on his
    /// clothes. The splats linger, then slowly fade; then he has a remark.
    @ViewBuilder
    private func poopCast(world: AdventureWorld, frame: AdventureFrame, time: Double, now: Date, start: Date) -> some View {
        let t = max(0, now.timeIntervalSince(start))
        let hunterTop = AppArt.groundTop + 3 - AppArt.hunter.height
        let entryX = frame.camera + world.sceneWidth + 12
        let exitX = frame.camera - 12
        // Where each dropping lands (hunter-sprite pixels): shoulder, chest, and sleeve.
        let targets = [CGPoint(x: 10, y: 21), CGPoint(x: 15, y: 27), CGPoint(x: 7, y: 31)]
        let heights: [CGFloat] = [90, 102, 82]

        ZStack(alignment: .topLeading) {
            ForEach(0..<3, id: \.self) { index in
                let doveStart = Double(index) * AdventureGame.PoopTiming.stagger
                let progress = (t - doveStart) / AdventureGame.PoopTiming.crossDuration
                let doveY = AppArt.groundTop - heights[index]
                let target = CGPoint(x: frame.hunterLeft + targets[index].x, y: hunterTop + targets[index].y)
                // The drop leaves the dove right above its target, so it falls straight down.
                let dropAt = doveStart + Double((entryX - target.x) / (entryX - exitX)) * AdventureGame.PoopTiming.crossDuration
                let landsAt = dropAt + AdventureGame.PoopTiming.fall
                if progress >= 0, progress <= 1 {
                    let wingsUp = Int(t * 6 + Double(index)).isMultiple(of: 2)
                    AppSprite(name: wingsUp ? "dove_wings_up" : "dove_wings_down", size: AppArt.dove, scale: world.scale)
                        .scaleEffect(x: -1)
                        .position(world.point((entryX + (exitX - entryX) * progress).rounded(), doveY, camera: frame.camera))
                }
                if t >= dropAt, t < landsAt {
                    let q = (t - dropAt) / AdventureGame.PoopTiming.fall
                    let y = doveY + 4 + (target.y - doveY - 4) * q * q
                    AppSprite(name: "poop_drop", size: AppArt.poopDrop, scale: world.scale)
                        .position(world.point(target.x, y.rounded(), camera: frame.camera))
                }
                if t >= landsAt {
                    let fade = max(0, (t - landsAt - AdventureGame.PoopTiming.splatHold) / AdventureGame.PoopTiming.splatFade)
                    AppSprite(name: "poop_splat", size: AppArt.poopSplat, scale: world.scale)
                        .opacity(max(0, 1 - fade))
                        .position(world.point(target.x, target.y, camera: frame.camera))
                }
            }
        }
        .allowsHitTesting(false)

        if t >= AdventureGame.PoopTiming.remarkShows, t < AdventureGame.PoopTiming.remarkHides {
            speech(AdventureGame.poopRemark, anchor: world.point(frame.hunterLeft + AppArt.hunterBodyCenterX, hunterTop, camera: frame.camera), screen: world.screen)
        }
    }

    /// The bear: reared up, then down on all fours, a bluff charge and a roar. Two warning shots
    /// send it running, the sun starts to set, and the hunter has a remark.
    @ViewBuilder
    private func bearCast(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, now: Date) -> some View {
        let phase = sceneIndex == game.scene ? game.phase : .hunting
        let cast = BearCast(phase: phase, now: now, sceneWidth: world.sceneWidth, done: game.bearDone)
        let origin = world.sceneOrigin(sceneIndex)
        let top = AppArt.groundTop + 3 - cast.size.height
        if cast.visible {
            AppSprite(name: cast.sprite, size: cast.size, scale: world.scale)
                .scaleEffect(x: cast.facesRight ? 1 : -1)
                .position(world.point(origin + cast.centerX, top + cast.size.height / 2, camera: frame.camera))
                .allowsHitTesting(false)
        }
        if cast.showsRoar {
            speech("ROAR!", anchor: world.point(origin + cast.centerX - cast.size.width / 2 + 8, top, camera: frame.camera), screen: world.screen, large: true)
        }
        if case .bear(let start) = phase {
            let t = now.timeIntervalSince(start)
            let overHunter = world.point(frame.hunterLeft + AppArt.hunterBodyCenterX, AppArt.groundTop + 3 - AppArt.hunter.height, camera: frame.camera)
            if t >= AdventureGame.BearTiming.smokeyShows, t < AdventureGame.BearTiming.smokeyHides {
                speech(AdventureGame.smokeyRemark, anchor: overHunter, screen: world.screen)
            }
            if t >= AdventureGame.BearTiming.remarkShows, t < AdventureGame.BearTiming.remarkHides {
                speech(AdventureGame.bearRemark, anchor: overHunter, screen: world.screen)
            }
        }
    }

    /// The doe and fawn drinking at the stream; they spot the hunter and bound away.
    @ViewBuilder
    private func streamCast(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, now: Date) -> some View {
        let layout = StreamLayout(sceneWidth: world.sceneWidth)
        let origin = world.sceneOrigin(sceneIndex)
        let phase = sceneIndex == game.scene ? game.phase : .hunting
        // Once the mallards have taken off (or the hunter has moved on), the deer are long gone.
        let gone = sceneIndex < game.scene || (sceneIndex == game.scene && game.dovesReleased != nil)
        let cast = StreamCast(phase: phase, now: now, layout: layout, sceneWidth: world.sceneWidth)
        let doeTop = AppArt.groundTop + 3 - AppArt.deer.height
        let fawnTop = AppArt.groundTop + 3 - AppArt.fawn.height
        let point = { (x: CGFloat, y: CGFloat) in world.point(origin + x, y, camera: frame.camera) }
        if !gone {
            ZStack(alignment: .topLeading) {
                AppSprite(name: "deer_\(cast.pose)", size: AppArt.deer, scale: world.scale)
                    .position(point(cast.doeLeft + AppArt.deer.width / 2, doeTop + AppArt.deer.height / 2))
                AppSprite(name: "fawn_\(cast.pose)", size: AppArt.fawn, scale: world.scale)
                    .position(point(cast.fawnLeft + AppArt.fawn.width / 2, fawnTop + AppArt.fawn.height / 2))
            }
            .allowsHitTesting(false)
            if cast.showsBang {
                speech("!", anchor: point(cast.doeLeft + 36, doeTop + 1), screen: world.screen, large: true)
                speech("!", anchor: point(cast.fawnLeft + 24, fawnTop + 1), screen: world.screen, large: true)
            }
        }
    }

    /// The fork in the trail: a wooden campground sign on the right, and a chain-link fence with
    /// a locked gate and a "Restricted Access" sign. Tap a sign (or the fence) to choose.
    @ViewBuilder
    private func forkCast(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, time: Double, now: Date) -> some View {
        let layout = ForkLayout(sceneWidth: world.sceneWidth, scale: world.scale)
        let origin = world.sceneOrigin(sceneIndex)
        let point = { (x: CGFloat, y: CGFloat) in world.point(origin + x, y, camera: frame.camera) }
        let phase = sceneIndex == game.scene ? game.phase : .hunting
        let choosing: Bool = { if case .fork(.choosing, _) = phase { return true } else { return false } }()
        let shotAt: Date? = { if case .fork(.gateOpening, let start) = phase { return start } else { return nil } }()
        let locked: Bool = { if case .fork(.locked, _) = phase { return true } else { return false } }()
        let sinceShot = shotAt.map { now.timeIntervalSince($0) }
        // The gate stays open once the lock is shot (and for the rest of the run on this route).
        let gateOpen = (sinceShot.map { $0 >= AdventureGame.ForkTiming.gateOpens } ?? false) || (game.route == .restricted && sceneIndex < game.scene)
        let fenceTop = ForkLayout.fenceTop
        let pixel: CGFloat = 2

        // Fence and gate (behind the hunter).
        AppSprite(name: gateOpen ? "fence_open" : "fence_closed", size: AppArt.fence, scale: world.scale)
            .position(point(layout.fenceLeft + AppArt.fence.width / 2, fenceTop + AppArt.fence.height / 2))
            .allowsHitTesting(false)

        // The padlock: hanging on the gate, flashing slowly while it waits to be shot, then dropping.
        if !gateOpen || (sinceShot ?? 0) < AdventureGame.ForkTiming.lockFall {
            let lock = layout.lock
            let fall = sinceShot.map { min($0 / AdventureGame.ForkTiming.lockFall, 1) } ?? 0
            let glow = locked && (now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: AdventureGame.ForkTiming.lockFlashPeriod)) < AdventureGame.ForkTiming.lockFlashPeriod / 2
            AppSprite(name: glow ? "padlock_glow" : "padlock", size: AppArt.padlock, scale: world.scale)
                .position(point(lock.x, (lock.y + (AppArt.groundTop - lock.y) * fall * fall).rounded()))
                .allowsHitTesting(false)
            if locked {
                Color.clear
                    .frame(width: 26 * world.scale, height: 26 * world.scale)
                    .contentShape(Rectangle())
                    .onTapGesture { if !requiresLandscape { game.shootLock(at: CGPoint(x: origin + lock.x, y: lock.y)) } }
                    .position(point(lock.x, lock.y))
                    .accessibilityElement()
                    .accessibilityLabel("Padlock on the gate")
                    .accessibilityHint("Shoot it off")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { game.shootLock(at: CGPoint(x: origin + lock.x, y: lock.y)) }
            }
        }

        // "Restricted Access" sign on the fence, with the alien logo.
        HStack(spacing: 8) {
            AppSprite(name: "alien_logo", size: AppArt.alienLogo, scale: 3)
            VStack(alignment: .leading, spacing: 4) {
                PixelText("RESTRICTED", pixelSize: pixel, color: Color(red: 0.8, green: 0.1, blue: 0.1), shadow: nil, scalesWithDynamicType: false)
                PixelText("ACCESS", pixelSize: pixel, color: Color(red: 0.8, green: 0.1, blue: 0.1), shadow: nil, scalesWithDynamicType: false)
            }
        }
        .padding(8)
        .background(Color(red: 0.96, green: 0.95, blue: 0.9), ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(Color(red: 0.8, green: 0.1, blue: 0.1), lineWidth: 3))
        .fixedSize()
        .position(point(layout.fenceLeft + AppArt.fenceGateWidth + (AppArt.fence.width - AppArt.fenceGateWidth) / 2, fenceTop + 16))
        .onTapGesture { if choosing, !requiresLandscape { game.choosePath(.restricted) } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Restricted Access path")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if choosing { game.choosePath(.restricted) } }

        // Wooden campground sign on a post. It's placed in the scene (not pinned to the screen),
        // so it only comes into view with the rest of the fork, already on its post.
        let postTop = AppArt.groundTop + 2 - AppArt.signPost.height
        let signX = layout.campSignX
        AppSprite(name: "sign_post", size: AppArt.signPost, scale: world.scale)
            .position(point(signX, postTop + AppArt.signPost.height / 2))
            .allowsHitTesting(false)
        let board = PixelText("CAMPGROUNDS", pixelSize: pixel, scalesWithDynamicType: false)
        .padding(8)
        .background(Color(red: 0.55, green: 0.36, blue: 0.18), ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(Color(red: 0.29, green: 0.18, blue: 0.09), lineWidth: 3))
        .fixedSize()
        board
            .position(point(signX, postTop + 2 - 12 / world.scale))
            .onTapGesture { if choosing, !requiresLandscape { game.choosePath(.campground) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Campgrounds path")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if choosing { game.choosePath(.campground) } }

        if choosing {
            // The fence itself also picks the restricted path.
            Color.clear
                .frame(width: AppArt.fence.width * world.scale, height: AppArt.fence.height * world.scale)
                .contentShape(Rectangle())
                .onTapGesture { if !requiresLandscape { game.choosePath(.restricted) } }
                .position(point(layout.fenceLeft + AppArt.fence.width / 2, fenceTop + AppArt.fence.height / 2))
                .accessibilityHidden(true)
            if case .fork(_, let start) = phase, now.timeIntervalSince(start) >= AdventureGame.ForkTiming.promptShows {
                speech(AdventureGame.forkPrompt, anchor: world.point(frame.hunterLeft + AppArt.hunterBodyCenterX, AppArt.groundTop + 3 - AppArt.hunter.height, camera: frame.camera), screen: world.screen, hint: "> TAP A SIGN")
            }
        }
    }

    /// The campsite: an RV, a crackling campfire, and a dad and kid roasting marshmallows.
    /// A proceed arrow appears on the right after a few seconds.
    @ViewBuilder
    private func campsiteCast(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, time: Double, now: Date) -> some View {
        let layout = CampsiteLayout(sceneWidth: world.sceneWidth)
        let origin = world.sceneOrigin(sceneIndex)
        let point = { (x: CGFloat, y: CGFloat) in world.point(origin + x, y, camera: frame.camera) }
        let flicker = Int(now.timeIntervalSinceReferenceDate * 6).isMultiple(of: 2)
        let rvTop = AppArt.groundTop + 4 - AppArt.rv.height
        let fireTop = AppArt.groundTop + 3 - AppArt.campfire.height
        let dadTop = AppArt.groundTop + 3 - AppArt.camperDad.height
        let kidTop = AppArt.groundTop + 3 - AppArt.camperKid.height

        ZStack(alignment: .topLeading) {
            AppSprite(name: "rv", size: AppArt.rv, scale: world.scale)
                .position(point(layout.rvCenterX, rvTop + AppArt.rv.height / 2))
            AppSprite(name: "camper_dad", size: AppArt.camperDad, scale: world.scale)
                .position(point(layout.dadLeft + AppArt.camperDad.width / 2, dadTop + AppArt.camperDad.height / 2))
            AppSprite(name: "camper_kid", size: AppArt.camperKid, scale: world.scale)
                .scaleEffect(x: -1)
                .position(point(layout.kidLeft + AppArt.camperKid.width / 2, kidTop + AppArt.camperKid.height / 2))
            AppSprite(name: flicker ? "campfire_a" : "campfire_b", size: AppArt.campfire, scale: world.scale)
                .position(point(layout.fireCenterX, fireTop + AppArt.campfire.height / 2))
        }
        .allowsHitTesting(false)

        if sceneIndex == game.scene, case .campsite(let start) = game.phase,
           now.timeIntervalSince(start) >= AdventureGame.CampTiming.arrowShows {
            let nudge: CGFloat = (sin(now.timeIntervalSinceReferenceDate * 4) * 2).rounded()
            let arrow = point(world.sceneWidth - AppArt.arrowRight.width / 2 - 6 + nudge, AppArt.groundTop - 26)
            AppSprite(name: "arrow_right", size: AppArt.arrowRight, scale: world.scale)
                .padding(8 * world.scale)
                .contentShape(Rectangle())
                .onTapGesture { if !requiresLandscape { game.leaveCampsite() } }
                .position(arrow)
                .accessibilityElement()
                .accessibilityLabel("Proceed")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { game.leaveCampsite() }
        }
    }

    /// A timed speech bubble (no tap needed) above `anchor`.
    private func speech(_ text: String, anchor: CGPoint, screen: CGSize, large: Bool = false, hint: String? = nil) -> some View {
        let pixel: CGFloat = large ? 4 : (screen.width >= 700 ? 3 : 2)
        // Long lines get a wider box so they take fewer rows.
        let columns: CGFloat = text.count > 90 ? 40 : 30
        let maxWidth = min(screen.width - 32, columns * 6 * pixel + 32)
        let maxChars = max(6, Int((maxWidth - 32) / (6 * pixel)))
        let lines = DialogText.wrap(text, maxCharacters: maxChars)
        let longest = CGFloat(lines.map(\.count).max() ?? 1)
        let boxWidth = min(maxWidth, longest * 6 * pixel + 32)
        return SpeechBubble(anchor: CGPoint(x: anchor.x, y: anchor.y - 4), boxWidth: boxWidth, screen: screen) {
            VStack(alignment: .leading, spacing: 3 * pixel) {
                ForEach(lines.indices, id: \.self) { index in
                    PixelText(lines[index], pixelSize: pixel, scalesWithDynamicType: !large)
                }
                if let hint {
                    PixelText(hint, pixelSize: pixel, color: .pixelOrange)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The leash scene: the fisherman walks Max over on a leash from beside the tree, then they
    /// talk with the hunter (tap to continue).
    @ViewBuilder
    private func reunionCast(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, now: Date) -> some View {
        let layout = ReunionLayout(sceneWidth: world.sceneWidth)
        let origin = world.sceneOrigin(sceneIndex)
        let cast = ReunionCast(phase: sceneIndex == game.scene ? game.phase : .hunting, now: now, layout: layout, done: game.reunionDone)
        let fishermanTop = AppArt.groundTop + 3 - AppArt.fisherman.height
        let dogTop = AppArt.groundTop + 3 - AppArt.dog.height
        let point = { (x: CGFloat, y: CGFloat) in world.point(origin + x, y, camera: frame.camera) }
        // The leash: a 1-pixel line from his hand to Max's collar, sagging a little in the middle.
        let hand = CGPoint(x: cast.fishermanLeft + AppArt.fisherman.width - 1 - AppArt.fishermanHand.x,
                           y: AppArt.groundTop + 3 - AppArt.fisherman.height + AppArt.fishermanHand.y)
        let collar = CGPoint(x: cast.dogLeft + AppArt.dogCollarFacingLeft.x, y: dogTop + AppArt.dogCollarFacingLeft.y + cast.dogBob)
        let steps = Int(max(abs(hand.x - collar.x), abs(hand.y - collar.y)))
        let leash = Path { path in
            for step in 0...max(steps, 1) {
                let s = CGFloat(step) / CGFloat(max(steps, 1))
                let sag = 3 * 4 * s * (1 - s)
                let x = (hand.x + (collar.x - hand.x) * s).rounded()
                let y = (hand.y + (collar.y - hand.y) * s + sag).rounded()
                let p = point(x, y)
                path.addRect(CGRect(x: p.x, y: p.y, width: world.scale, height: world.scale))
            }
        }

        ZStack(alignment: .topLeading) {
            AppSprite(name: cast.dogSprite, size: AppArt.dog, scale: world.scale)
                .scaleEffect(x: -1)
                .position(point(cast.dogLeft + AppArt.dog.width / 2, dogTop + AppArt.dog.height / 2))
            AppSprite(name: cast.fishermanSprite, size: AppArt.fisherman, scale: world.scale)
                .scaleEffect(x: -1)
                .position(point(cast.fishermanLeft + AppArt.fisherman.width / 2, fishermanTop + AppArt.fisherman.height / 2))
            leash.fill(Color(red: 0.78, green: 0.22, blue: 0.18))
        }
        .allowsHitTesting(false)

        if let line = cast.line {
            let line = AdventureGame.reunionLines[line]
            let anchor = line.speaker == .fisherman
                ? point(cast.fishermanLeft + AppArt.fishermanBodyCenterX, fishermanTop)
                : world.point(frame.hunterLeft + AppArt.hunterBodyCenterX, AppArt.groundTop + 3 - AppArt.hunter.height, camera: frame.camera)
            speech(line.text, anchor: anchor, screen: world.screen, hint: "> TAP")
        }
    }

    /// The dove perched on the cabin chimney after the visit inside.
    private func chimneyDove(world: AdventureWorld, frame: AdventureFrame, time: Double) -> some View {
        let cabinX = world.sceneOrigin(game.scene) + world.cabinCenter(fraction: game.spec(game.scene).cabin?.fractionX ?? 0.6)
        let cabinLeft = cabinX - AppArt.cabin.width / 2
        let cabinTop = AppArt.groundTop + 3 - AppArt.cabin.height
        // Perched: wings folded, sitting on the chimney, with an occasional flap.
        let flap = Int(time * 1.2).isMultiple(of: 5)
        let position = CGPoint(
            x: cabinLeft + AppArt.cabinChimneyTop.x,
            y: cabinTop + AppArt.cabinChimneyTop.y - AppArt.dove.height / 2 + 2
        )
        return AppSprite(name: flap ? "dove_wings_up" : "dove_wings_down", size: AppArt.dove, scale: world.scale)
            .scaleEffect(x: -1)
            .padding(3 * world.scale)
            .contentShape(Rectangle())
            .onTapGesture { game.shootChimneyDove(at: position) }
            .position(world.point(position.x, position.y, camera: frame.camera))
            .accessibilityElement()
            .accessibilityLabel("Dove on the chimney")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { game.shootChimneyDove(at: position) }
    }

    private func poofs(world: AdventureWorld, frame: AdventureFrame, now: Date) -> some View {
        ForEach(game.poofs) { poof in
            let age = min(max(now.timeIntervalSince(poof.date) / AdventureGame.poofDuration, 0), 1)
            AppSprite(name: "feather_poof", size: AppArt.poof, scale: world.scale)
                .scaleEffect(poof.scale * (0.7 + 0.6 * age))
                .opacity(1 - age * 0.8)
                .position(world.point(poof.position.x, poof.position.y, camera: frame.camera))
        }
        .allowsHitTesting(false)
    }

    private func hunter(world: AdventureWorld, frame: AdventureFrame) -> some View {
        let size = AppArt.hunter
        let top = AppArt.groundTop + 3 - size.height - frame.hunterLift
        return ZStack {
            AppSprite(name: frame.hunterSprite, size: size, scale: world.scale)
                .position(world.point(frame.hunterLeft + size.width / 2, top + size.height / 2, camera: frame.camera))

            if game.isFiring {
                AppSprite(name: "muzzle_flash", size: AppArt.muzzleFlash, scale: world.scale)
                    .position(world.point(frame.hunterLeft + AppArt.hunterMuzzle.x, top + AppArt.hunterMuzzle.y, camera: frame.camera))
            }
        }
        .opacity(frame.hunterOpacity)
        .allowsHitTesting(false)
    }

    /// The floating "Enter the cabin?" box above the cabin.
    private func cabinPrompt(world: AdventureWorld, frame: AdventureFrame, time: Double) -> some View {
        let pixel: CGFloat = world.screen.width >= 700 ? 3 : 2
        let boxWidth = min(world.screen.width - 32, 30 * 6 * pixel + 32)
        let maxChars = max(10, Int((boxWidth - 32) / (6 * pixel)))
        let lines = DialogText.wrap(
            "Enter the cabin? I'm sure they won't mind a total stranger barging in.",
            maxCharacters: maxChars
        )
        let cabinX = world.sceneOrigin(game.scene) + world.cabinCenter(fraction: game.spec(game.scene).cabin?.fractionX ?? 0.6)
        let cabinTop = AppArt.groundTop + 3 - AppArt.cabin.height
        let anchor = world.point(cabinX, cabinTop - 4, camera: frame.camera)
        let bob: CGFloat = (sin(time * 2) * 2).rounded()
        let blinkOn: Bool = Int(time * 2).isMultiple(of: 2) || time == 0
        // Hang the box above the cabin, kept on screen.
        let halfSlack: CGFloat = world.screen.width / 2 - boxWidth / 2 - 16
        let offsetX: CGFloat = min(max(anchor.x - world.screen.width / 2, -halfSlack), halfSlack)
        let hangHeight: CGFloat = max(anchor.y + bob, 120)

        return VStack(alignment: .leading, spacing: 3 * pixel) {
            ForEach(lines.indices, id: \.self) { index in
                PixelText(lines[index], pixelSize: pixel)
            }
            PixelText("> TAP TO ENTER", pixelSize: pixel, color: .pixelOrange)
                .opacity(blinkOn ? 1 : 0.25)
        }
        .padding(14)
        .background(Color.black.opacity(0.9), ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
        .fixedSize()
        .frame(width: world.screen.width, height: hangHeight, alignment: .bottom)
        .offset(x: offsetX)
        .onTapGesture { game.enterCabin() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { game.enterCabin() }
    }

    private func toBeContinued(time: Double, screenWidth: CGFloat) -> some View {
        let title = "TO BE CONTINUED..."
        // Largest pixel size that keeps the line inside the screen.
        let pixel = max(1, min(4, ((screenWidth - 48) / CGFloat(title.count * 6)).rounded(.down)))
        return VStack(spacing: 24) {
            PixelText(title, pixelSize: pixel, scalesWithDynamicType: false)
            PixelText("TAP TO RETURN", pixelSize: 2, color: .pixelOrange)
                .opacity(Int(time * 2).isMultiple(of: 2) ? 1 : 0.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { game.restart() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { game.restart() }
    }

    // MARK: Helpers

    private func visibleScenes(camera: CGFloat, sceneWidth: CGFloat) -> [Int] {
        let first = max(0, Int((camera / sceneWidth).rounded(.down)))
        let last = min(game.sceneCount - 1, Int(((camera + sceneWidth - 1) / sceneWidth).rounded(.down)))
        return first <= last ? Array(first...last) : []
    }

    private func handleBackgroundTap() {
        if requiresLandscape { return }
        switch game.phase {
        case .hunting: game.shootMiss()
        case .cabinPrompt: game.enterCabin()
        case .reunion(.talking(_), _): game.advanceReunion()
        case .finished: game.restart()
        default: break
        }
    }

    private var backgroundTapLabel: String {
        switch game.phase {
        case .cabinPrompt: "Enter the cabin"
        case .reunion(.talking(_), _): "Continue"
        case .finished: "Return to the start"
        default: "Fire at the sky"
        }
    }
}

// MARK: - Geometry

/// Screen geometry for the adventure, in art pixels.
struct AdventureWorld {
    let scale: CGFloat
    /// Screen y of the art's top edge (negative when the top of the sky is cropped).
    let originY: CGFloat
    /// Width of one scene: exactly one screen, in art pixels.
    let sceneWidth: CGFloat
    let screen: CGSize

    /// The topmost art row on screen.
    var visibleMinY: CGFloat { -originY / scale }

    func sceneOrigin(_ index: Int) -> CGFloat { CGFloat(index) * sceneWidth }

    /// The cabin's center within its scene, nudged so the whole cabin fits on screen.
    func cabinCenter(fraction: CGFloat) -> CGFloat {
        Self.cabinCenter(fraction: fraction, sceneWidth: sceneWidth)
    }

    static func cabinCenter(fraction: CGFloat, sceneWidth: CGFloat) -> CGFloat {
        let half = AppArt.cabin.width / 2
        return min(max((fraction * sceneWidth).rounded(), half + 2), sceneWidth - half - 2).rounded()
    }

    /// Converts a world position (art pixels) to a screen point for the given camera.
    func point(_ x: CGFloat, _ y: CGFloat, camera: CGFloat) -> CGPoint {
        CGPoint(x: (x - camera) * scale, y: originY + y * scale)
    }
}

/// Where the camera and hunter are at a moment in time, derived from the game phase.
struct AdventureFrame {
    var camera: CGFloat
    /// The hunter sprite's left edge, in world art pixels.
    var hunterLeft: CGFloat
    var hunterSprite = "hunter"
    var hunterOpacity: Double = 1
    /// How far the hunter is lifted off the ground (being beamed up), in art pixels.
    var hunterLift: CGFloat = 0
    var doorOpen = false
    var blackout: Double = 0

    init(game: AdventureGame, now: Date, sceneWidth: CGFloat, scale: CGFloat) {
        let restCamera = CGFloat(game.scene) * sceneWidth
        camera = restCamera
        let restOffset = Self.restOffset(game: game, scene: game.scene, sceneWidth: sceneWidth)
        hunterLeft = restCamera + restOffset
        if let fadeStart = game.fadeInStart {
            blackout = max(0, 1 - now.timeIntervalSince(fadeStart) / AdventureGame.fadeInDuration)
        }

        switch game.phase {
        case .hunting, .cabinPrompt:
            break

        case .walking(let from, let start, _):
            // The hunter walks one full scene at a steady pace. The camera lets him stride
            // toward the middle of the screen, then catches up so he arrives back at the left
            // edge of the next scene, like a classic side-scroller.
            let elapsed = max(0, now.timeIntervalSince(start))
            let progress = min(elapsed / AdventureGame.walkDuration, 1)
            let origin = CGFloat(from) * sceneWidth
            let startOffset = Self.restOffset(game: game, scene: from, sceneWidth: sceneWidth)
            let endOffset = Self.restOffset(game: game, scene: from + 1, sceneWidth: sceneWidth)
            hunterLeft = (origin + startOffset + (sceneWidth + endOffset - startOffset) * progress).rounded()
            camera = (origin + sceneWidth * progress - 0.3 * sceneWidth * sin(.pi * progress)).rounded()
            hunterSprite = Self.walkFrame(elapsed: elapsed)

        case .enteringCabin(let start):
            let elapsed = max(0, now.timeIntervalSince(start))
            let walk = min(elapsed / AdventureGame.enterWalkDuration, 1)
            let cabinX = restCamera + AdventureWorld.cabinCenter(fraction: game.spec(game.scene).cabin?.fractionX ?? 0.6, sceneWidth: sceneWidth)
            let doorX = cabinX - AppArt.cabin.width / 2 + AppArt.cabinDoorCenterX
            let target = doorX - AppArt.hunterBodyCenterX
            hunterLeft = (restCamera + 4 + (target - restCamera - 4) * walk).rounded()
            hunterSprite = walk < 1 ? Self.walkFrame(elapsed: elapsed) : "hunter"
            doorOpen = walk > 0.6
            let inside = elapsed - AdventureGame.enterWalkDuration
            hunterOpacity = inside <= 0 ? 1 : max(0, 1 - inside / 0.35)
            blackout = min(max(inside / AdventureGame.enterFadeDuration, 0), 1)

        case .pond, .tackleBox, .reunion, .poop, .stream, .campsite:
            break

        case .abduction(let start):
            // He walks to the middle, gapes at the UFO, and is lifted up into it, fading away.
            let t = max(0, now.timeIntervalSince(start))
            let walk = min(t / AdventureGame.AbductionTiming.walkToCenter, 1)
            let center = restCamera + (sceneWidth / 2).rounded() - AppArt.hunterBodyCenterX
            hunterLeft = (restCamera + restOffset + (center - restCamera - restOffset) * walk).rounded()
            if walk < 1 {
                hunterSprite = Self.walkFrame(elapsed: t)
            } else if t >= AdventureGame.AbductionTiming.shocked {
                hunterSprite = "hunter_shocked"
            }
            let lift = min(max((t - AdventureGame.AbductionTiming.liftStarts) / AdventureGame.AbductionTiming.liftDuration, 0), 1)
            hunterLift = (46 * lift * lift).rounded()
            hunterOpacity = 1 - min(max((lift - 0.55) / 0.45, 0), 1)
            blackout = min(max((t - AdventureGame.AbductionTiming.fadeStarts) / AdventureGame.AbductionTiming.fadeDuration, 0), 1)

        case .console, .aboard, .aliens, .vats, .wreckedLab, .pristineLab:
            blackout = 1

        case .bear(let start):
            // A wide-eyed double take at the bear, and later a look up at the sky as the sun sets.
            let t = now.timeIntervalSince(start)
            if t >= AdventureGame.BearTiming.shockedStarts, t < AdventureGame.BearTiming.shockedEnds {
                hunterSprite = "hunter_shocked"
            } else if t >= AdventureGame.BearTiming.duskStarts, t < AdventureGame.BearTiming.remarkShows {
                hunterSprite = "hunter_look_up"
            }

        case .fork(let step, let start):
            typealias Timing = AdventureGame.ForkTiming
            let layout = ForkLayout(sceneWidth: sceneWidth, scale: scale)
            let t = max(0, now.timeIntervalSince(start))
            let atGate = restCamera + layout.hunterAtGate
            switch step {
            case .choosing:
                break
            case .toGate:
                let walk = min(t / Timing.toGateDuration, 1)
                hunterLeft = (restCamera + restOffset + (atGate - restCamera - restOffset) * walk).rounded()
                hunterSprite = walk < 1 ? Self.walkFrame(elapsed: t) : "hunter"
            case .locked:
                hunterLeft = atGate
            case .gateOpening:
                // Through the open gate, fading out, then to black.
                let walk = min(max((t - Timing.walkInStarts) / Timing.walkInDuration, 0), 1)
                let through = restCamera + layout.hunterThroughGate
                hunterLeft = (atGate + (through - atGate) * walk).rounded()
                if walk > 0, walk < 1 { hunterSprite = Self.walkFrame(elapsed: t) }
                hunterOpacity = 1 - min(max((t - Timing.fadeStarts) / 0.5, 0), 1)
                blackout = min(max((t - Timing.fadeStarts) / Timing.fadeDuration, 0), 1)
            }

        case .interior:
            doorOpen = true
            hunterOpacity = 0
            blackout = 1

        case .finished(let start):
            blackout = game.finishesFromBlack ? 1 : min(now.timeIntervalSince(start) / AdventureGame.enterFadeDuration, 1)
        }
    }

    /// Where the hunter stands in a scene (sprite left edge, within the scene): at the cabin
    /// door after his visit, framed slightly further left at the pond on narrow screens, and
    /// otherwise at the left edge.
    static func restOffset(game: AdventureGame, scene: Int, sceneWidth: CGFloat) -> CGFloat {
        guard scene >= 0, scene < game.sceneCount else { return 4 }
        let spec = game.spec(scene)
        if game.cabinVisited, spec.cabin != nil {
            return cabinDoorOffset(scene: scene, sceneWidth: sceneWidth)
        }
        if spec.hasPondEvent {
            return PondLayout.hunterOffset(sceneWidth: sceneWidth)
        }
        return 4
    }

    /// Where the hunter stands (sprite left edge, within the scene) when he's at the cabin door.
    static func cabinDoorOffset(scene: Int, sceneWidth: CGFloat) -> CGFloat {
        let cabinX = AdventureWorld.cabinCenter(fraction: AdventureScenes.all[scene].cabin?.fractionX ?? 0.6, sceneWidth: sceneWidth)
        return cabinX - AppArt.cabin.width / 2 + AppArt.cabinDoorCenterX - AppArt.hunterBodyCenterX
    }

    private static func walkFrame(elapsed: TimeInterval) -> String {
        let cycle = AppArt.hunterWalkCycle
        return cycle[Int(elapsed * AdventureGame.walkFrameRate) % cycle.count]
    }
}

// MARK: - Dialog text

enum DialogText {
    /// Breaks text into upper-case lines of at most `maxCharacters` for the pixel font.
    static func wrap(_ text: String, maxCharacters: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.uppercased().split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= maxCharacters {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

#if DEBUG
#Preview("Scene 2") {
    AdventureView(game: .preview(scene: 1))
        .ignoresSafeArea()
}

#Preview("Cabin") {
    AdventureView(game: .preview(scene: 2, phase: .cabinPrompt))
        .ignoresSafeArea()
}

#Preview("Inside") {
    AdventureView(game: .preview(scene: 3, phase: .finished(start: .now.addingTimeInterval(-2))))
        .ignoresSafeArea()
}

#Preview("Walking") {
    AdventureView(game: .preview(scene: 0, phase: .walking(from: 0, start: .now.addingTimeInterval(-1.6), fromCabinDoor: false)))
        .ignoresSafeArea()
}
#endif

#if DEBUG
#Preview("Interior: Anna speaks") {
    AdventureView(game: .preview(scene: 2, phase: .interior(.speaking(line: 0), start: .now)))
        .ignoresSafeArea()
}

#Preview("Interior: puzzled") {
    AdventureView(game: .preview(scene: 2, phase: .interior(.puzzled, start: .now.addingTimeInterval(-1.5))))
        .ignoresSafeArea()
}

#Preview("Chimney dove") {
    AdventureView(game: .preview(scene: 2, cabinVisited: true))
        .ignoresSafeArea()
}
#endif

// MARK: - Pond scene

/// Where the pond, fisherman, rod, and Max sit within the pond scene (scene-local art pixels).
/// The fisherman stands on the far bank facing left, casting into the pond, with Max beside him.
/// Wide screens (landscape phones) get the large pond, reaching left from the fisherman's bank.
/// Narrow screens (about 90 art pixels wide in portrait) get a compact arrangement: a smaller
/// pond and shorter rod, Max sitting in front of the fisherman, and the hunter framed slightly
/// past the left edge, so the line always lands in the water in front of the fisherman.
struct PondLayout {
    let isCompact: Bool
    let isLarge: Bool
    let pondLeft: CGFloat
    let fishermanLeft: CGFloat
    let dogLeft: CGFloat

    /// Where the hunter stands in the pond scene (sprite left edge).
    static func hunterOffset(sceneWidth width: CGFloat) -> CGFloat {
        width < compactWidth ? -12 : 4
    }

    static let compactWidth: CGFloat = 120

    init(sceneWidth width: CGFloat) {
        isCompact = width < Self.compactWidth
        if isCompact {
            fishermanLeft = width - 26
            dogLeft = width - AppArt.dog.width
        } else {
            let fishermanCenter = min((width * 0.72).rounded(), width - 34)
            fishermanLeft = fishermanCenter - AppArt.fishermanBodyCenterX
            dogLeft = min(fishermanCenter + 12, width - AppArt.dog.width - 1)
        }
        // Center the pond under the rod tip.
        let rodSize = isCompact ? AppArt.fishingRodShort : AppArt.fishingRod
        let grip = isCompact ? AppArt.rodShortGrip : AppArt.rodGrip
        let tip = isCompact ? AppArt.rodShortTip : AppArt.rodTip
        let handX = fishermanLeft + AppArt.fisherman.width - 1 - AppArt.fishermanHand.x
        let tipX = handX - (rodSize.width - 1 - grip.x) + rodSize.width - 1 - tip.x
        // The large pond's right bank meets the fisherman's feet, so it grows toward the hunter.
        // It's used only when it stays clear of the hunter (sprite at x 4, 38 px wide).
        let largeLeft = fishermanLeft + 1 - AppArt.pondLarge.width
        isLarge = !isCompact && largeLeft >= 4 + AppArt.hunter.width + 4
        if isLarge {
            pondLeft = largeLeft
        } else {
            let pondWidth = (isCompact ? AppArt.pondSmall : AppArt.pond).width
            pondLeft = max(2, (tipX - pondWidth / 2).rounded())
        }
    }

    var pondSprite: String { isCompact ? "prop_pond_small" : (isLarge ? "prop_pond_large" : "prop_pond") }
    var pondSize: CGSize { isCompact ? AppArt.pondSmall : (isLarge ? AppArt.pondLarge : AppArt.pond) }
    var rodSprite: String { isCompact ? "fishing_rod_short" : "fishing_rod" }
    var rodSize: CGSize { isCompact ? AppArt.fishingRodShort : AppArt.fishingRod }

    var pondCenterX: CGFloat { pondLeft + pondSize.width / 2 }
    /// The water's surface, where the fishing line meets the pond.
    var waterY: CGFloat { AppArt.groundTop + (isCompact ? 6 : (isLarge ? 12 : 7)) }

    /// The three pond doves hover spread across the water.
    func doveX(_ index: Int) -> CGFloat {
        let spread: CGFloat = isCompact ? 12 : (isLarge ? 26 : 16)
        return (pondCenterX + [-spread, 0, spread][min(index, 2)]).rounded()
    }

    /// Extra height for the pond doves on narrow screens, keeping them clear of everyone.
    var doveLift: CGFloat { isCompact ? 14 : 0 }

    // The rod, mirrored to point left from the fisherman's hand.
    private var handX: CGFloat { fishermanLeft + AppArt.fisherman.width - 1 - AppArt.fishermanHand.x }
    private var handY: CGFloat { AppArt.groundTop + 3 - AppArt.fisherman.height + AppArt.fishermanHand.y }
    private var grip: CGPoint { isCompact ? AppArt.rodShortGrip : AppArt.rodGrip }
    private var tip: CGPoint { isCompact ? AppArt.rodShortTip : AppArt.rodTip }
    var rodLeft: CGFloat { handX - (rodSize.width - 1 - grip.x) }
    var rodTop: CGFloat { handY - grip.y }
    var rodTip: CGPoint {
        CGPoint(x: rodLeft + rodSize.width - 1 - tip.x, y: rodTop + tip.y)
    }
}

/// How the fisherman and Max look at a moment, from the pond step and its elapsed time.
struct PondCast {
    var fishermanLeft: CGFloat
    var fishermanFacesRight = false
    var fishermanSprite = "fisherman"
    var showsRod = true
    var fishermanLine: String?
    var dogLeft: CGFloat
    var dogFacesRight = false
    var dogSprite = "dog_sit"
    var showsBang = false

    typealias Timing = AdventureGame.PondTiming

    init(phase: AdventureGame.Phase, now: Date, layout: PondLayout, sceneWidth: CGFloat) {
        fishermanLeft = layout.fishermanLeft
        dogLeft = layout.dogLeft
        guard case .pond(let step, let start) = phase else { return }
        let t = max(0, now.timeIntervalSince(start))

        switch step {
        case .greeting:
            if t >= Timing.greetingShows, t < Timing.greetingHides {
                fishermanLine = AdventureGame.fishermanGreeting
            }

        case .dogStartled:
            dogSprite = "dog_stand"
            showsBang = t >= Timing.bangShows && t < Timing.dogRuns
            if t >= Timing.dogRuns {
                // Max bolts off to the right.
                let run = min((t - Timing.dogRuns) / Timing.dogRunDuration, 1)
                dogFacesRight = true
                dogLeft = layout.dogLeft + (sceneWidth + 40 - layout.dogLeft) * run
                dogSprite = Self.frame(AppArt.dogRunCycle, t, rate: 12)
            }

        case .fishermanYells:
            dogLeft = sceneWidth + 60
            if t < Timing.yellHides {
                fishermanLine = AdventureGame.fishermanYell
            } else {
                // Pole put away; he turns and runs after Max.
                showsRod = false
                fishermanFacesRight = true
                let run = min((t - Timing.yellHides) / Timing.fishermanRunDuration, 1)
                fishermanLeft = layout.fishermanLeft + (sceneWidth + 40 - layout.fishermanLeft) * run
                fishermanSprite = Self.frame(AppArt.fishermanRunCycle, t, rate: 10)
            }

        case .whoops:
            showsRod = false
            fishermanLeft = sceneWidth + 60
            dogLeft = sceneWidth + 60
        }
        fishermanLeft = fishermanLeft.rounded()
        dogLeft = dogLeft.rounded()
    }

    private static func frame(_ cycle: [String], _ t: TimeInterval, rate: Double) -> String {
        cycle[Int(t * rate) % cycle.count]
    }
}

#if DEBUG
#Preview("Pond: greeting") {
    AdventureView(game: .preview(scene: 4, phase: .pond(.greeting, start: .now.addingTimeInterval(-1))))
        .ignoresSafeArea()
}

#Preview("Pond: doves out") {
    AdventureView(game: .preview(scene: 4, pondDovesOut: true))
        .ignoresSafeArea()
}

#Preview("Pond: Max startled") {
    AdventureView(game: .preview(scene: 4, phase: .pond(.dogStartled, start: .now.addingTimeInterval(-0.5))))
        .ignoresSafeArea()
}

#Preview("Pond: fisherman yells") {
    AdventureView(game: .preview(scene: 4, phase: .pond(.fishermanYells, start: .now.addingTimeInterval(-1))))
        .ignoresSafeArea()
}
#endif

// MARK: - Tackle box scene

/// Where the fisherman, Max, and the tackle box sit in the tackle box scene (scene-local art pixels).
/// The fisherman stands mid-scene facing the hunter, carrying the box, with Max sitting beside him.
struct TackleLayout {
    let fishermanLeft: CGFloat
    let dogLeft: CGFloat

    init(sceneWidth width: CGFloat) {
        let center = (width * 0.5).rounded()
        fishermanLeft = center - AppArt.fishermanBodyCenterX
        dogLeft = min(center + 12, width - AppArt.dog.width - 1)
    }

    /// His hand (facing left), where the box hangs by its handle.
    var hand: CGPoint {
        CGPoint(x: fishermanLeft + AppArt.fisherman.width - 1 - AppArt.fishermanHand.x,
                y: AppArt.groundTop + 3 - AppArt.fisherman.height + AppArt.fishermanHand.y)
    }

    /// The box's center while he carries it.
    var boxCarried: CGPoint { CGPoint(x: hand.x, y: hand.y - 1 + AppArt.tackleBox.height / 2) }
    /// The box's center once it's lying in the grass.
    var boxRest: CGPoint { CGPoint(x: hand.x, y: AppArt.groundTop + 2 - AppArt.tackleBox.height / 2) }
}

/// How the tackle box scene looks at a moment, from its step and elapsed time.
struct TackleCast {
    var showsPeople = true
    var fishermanLeft: CGFloat
    var fishermanFacesRight = false
    var fishermanSprite = "fisherman"
    var dogLeft: CGFloat
    var dogFacesRight = false
    var dogSprite = "dog_sit"
    var showsBang = false
    var fishermanLine: String?
    /// Where the tackle box is drawn (nil once it's picked up).
    var boxCenter: CGPoint?
    var boxWaiting = false
    var showsCollected = false

    typealias Timing = AdventureGame.TackleTiming

    init(phase: AdventureGame.Phase, now: Date, layout: TackleLayout, eventDone: Bool, sceneWidth: CGFloat) {
        fishermanLeft = layout.fishermanLeft
        dogLeft = layout.dogLeft
        boxCenter = layout.boxCarried
        if eventDone {
            showsPeople = false
            boxCenter = nil
            return
        }
        // Before the scene starts (the hunter walking in), they wait with the box in hand.
        guard case .tackleBox(let step, let start) = phase else { return }
        let t = max(0, now.timeIntervalSince(start))

        switch step {
        case .fleeing:
            dogSprite = "dog_stand"
            showsBang = t >= Timing.bangShows && t < Timing.dogRuns
            if t >= Timing.waitShows, t < Timing.waitHides {
                fishermanLine = "Max, wait!"
            }
            if t >= Timing.dogRuns {
                // Max bolts off to the right.
                let run = min((t - Timing.dogRuns) / Timing.dogRunDuration, 1)
                dogFacesRight = true
                dogLeft = layout.dogLeft + (sceneWidth + 40 - layout.dogLeft) * run
                dogSprite = Self.frame(AppArt.dogRunCycle, t, rate: 12)
            }
            if t >= Timing.fishermanRuns {
                // He turns to chase Max, and the box slips out of his hand.
                let run = min((t - Timing.fishermanRuns) / Timing.fishermanRunDuration, 1)
                fishermanFacesRight = true
                fishermanLeft = layout.fishermanLeft + (sceneWidth + 40 - layout.fishermanLeft) * run
                fishermanSprite = Self.frame(AppArt.fishermanRunCycle, t, rate: 10)
                let fall = min((t - Timing.fishermanRuns) / Timing.boxFall, 1)
                let carried = layout.boxCarried
                let rest = layout.boxRest
                boxCenter = CGPoint(x: carried.x, y: (carried.y + (rest.y - carried.y) * fall * fall).rounded())
            }

        case .waiting:
            showsPeople = false
            boxCenter = layout.boxRest
            boxWaiting = true

        case .collected:
            showsPeople = false
            boxCenter = nil
            showsCollected = true
        }
        fishermanLeft = fishermanLeft.rounded()
        dogLeft = dogLeft.rounded()
    }

    private static func frame(_ cycle: [String], _ t: TimeInterval, rate: Double) -> String {
        cycle[Int(t * rate) % cycle.count]
    }
}

#if DEBUG
#Preview("Tackle box: fleeing") {
    AdventureView(game: .preview(scene: 7, phase: .tackleBox(.fleeing, start: .now.addingTimeInterval(-1.6))))
        .ignoresSafeArea()
}

#Preview("Tackle box: waiting") {
    AdventureView(game: .preview(scene: 7, phase: .tackleBox(.waiting, start: .now)))
        .ignoresSafeArea()
}
#endif

// MARK: - Leash scene

/// Where the fisherman and Max stand in the leash scene (scene-local art pixels): they start by
/// the tree and stop a little way in front of the hunter, Max on the leash ahead of him.
struct ReunionLayout {
    let startFishermanLeft: CGFloat
    let endFishermanLeft: CGFloat

    init(sceneWidth width: CGFloat) {
        let treeX = (0.86 * width).rounded()
        startFishermanLeft = treeX - 26 - AppArt.fishermanBodyCenterX
        endFishermanLeft = min(max((width * 0.3).rounded(), 92), startFishermanLeft)
    }

    /// Max walks just ahead of the fisherman, at the end of the leash.
    static func dogLeft(fishermanLeft: CGFloat) -> CGFloat {
        fishermanLeft - AppArt.dog.width
    }
}

/// How the leash scene looks at a moment.
struct ReunionCast {
    var fishermanLeft: CGFloat
    var fishermanSprite = "fisherman"
    var dogLeft: CGFloat
    var dogSprite = "dog_stand"
    /// Max's head (and collar) sits a pixel lower in his running frames.
    var dogBob: CGFloat = 0
    /// Which conversation line is showing.
    var line: Int?

    init(phase: AdventureGame.Phase, now: Date, layout: ReunionLayout, done: Bool) {
        fishermanLeft = done ? layout.endFishermanLeft : layout.startFishermanLeft
        if case .reunion(let step, let start) = phase {
            switch step {
            case .approaching:
                let t = max(0, now.timeIntervalSince(start))
                let walk = min(t / AdventureGame.ReunionTiming.approachDuration, 1)
                fishermanLeft = (layout.startFishermanLeft + (layout.endFishermanLeft - layout.startFishermanLeft) * walk).rounded()
                if walk < 1 {
                    // No walk cycle for these two, so their run strides at a slower pace read as walking.
                    fishermanSprite = AppArt.fishermanRunCycle[Int(t * 6) % AppArt.fishermanRunCycle.count]
                    dogSprite = AppArt.dogRunCycle[Int(t * 7) % AppArt.dogRunCycle.count]
                }
            case .talking(let index):
                fishermanLeft = layout.endFishermanLeft
                line = index
            case .returned:
                fishermanLeft = layout.endFishermanLeft
            }
        }
        dogLeft = ReunionLayout.dogLeft(fishermanLeft: fishermanLeft)
        // Keep the leash clipped to the collar as his head bobs.
        dogBob = dogSprite == "dog_stand" ? 0 : 1
    }
}

#if DEBUG
#Preview("Leash: approaching") {
    AdventureView(game: .preview(scene: 8, phase: .reunion(.approaching, start: .now.addingTimeInterval(-1.4))))
        .ignoresSafeArea()
}

#Preview("Leash: talking") {
    AdventureView(game: .preview(scene: 8, phase: .reunion(.talking(line: 0), start: .now)))
        .ignoresSafeArea()
}

#Preview("Leash: hunter replies") {
    AdventureView(game: .preview(scene: 8, phase: .reunion(.talking(line: 1), start: .now)))
        .ignoresSafeArea()
}
#endif

// MARK: - Bear scene

/// Where the bear is and how it looks at a moment (scene-local art pixels; `centerX` is the sprite's center).
struct BearCast {
    var visible = true
    var centerX: CGFloat
    var sprite = "bear_standing"
    var size = AppArt.bearStanding
    var facesRight = false
    var showsRoar = false

    typealias Timing = AdventureGame.BearTiming

    init(phase: AdventureGame.Phase, now: Date, sceneWidth: CGFloat, done: Bool) {
        let homeX = (sceneWidth * 0.7).rounded()
        let chargedX = homeX - min(46, homeX - 70)
        centerX = homeX
        if done {
            visible = false
            return
        }
        guard case .bear(let start) = phase else { return }
        let t = max(0, now.timeIntervalSince(start))
        if t < Timing.dropsToFours { return }

        size = AppArt.bearFour
        sprite = "bear_four"
        if t >= Timing.chargeStarts {
            // The bluff charge toward the hunter.
            let charge = min((t - Timing.chargeStarts) / Timing.chargeDuration, 1)
            centerX = homeX + (chargedX - homeX) * charge
            if charge < 1 { sprite = AppArt.bearRunCycle[Int(t * 12) % AppArt.bearRunCycle.count] }
        }
        if t >= Timing.roarStarts, t < Timing.roarEnds {
            sprite = "bear_roar"
            showsRoar = true
            centerX += (sin(t * 60)).rounded()
        }
        if t >= Timing.fleeStarts {
            // Scampering off to the right.
            let flee = min((t - Timing.fleeStarts) / Timing.fleeDuration, 1)
            facesRight = true
            centerX = chargedX + (sceneWidth + 60 - chargedX) * flee
            sprite = AppArt.bearRunCycle[Int(t * 14) % AppArt.bearRunCycle.count]
            visible = flee < 1
        }
        centerX = centerX.rounded()
    }
}

// MARK: - Stream scene

/// Where the stream and the deer sit in the stream scene (scene-local art pixels).
struct StreamLayout {
    let streamLeft: CGFloat
    let doeLeft: CGFloat
    let fawnLeft: CGFloat

    /// The water line where the mallards float.
    static let waterY = AppArt.groundTop + 9

    init(sceneWidth width: CGFloat) {
        let center = min((width * 0.6).rounded(), width - AppArt.stream.width / 2 - 4)
        streamLeft = center - AppArt.stream.width / 2
        // The deer drink at the far right end of the stream, the fawn beside its mother.
        doeLeft = streamLeft + AppArt.stream.width - AppArt.deer.width - 6
        fawnLeft = doeLeft - AppArt.fawn.width + 4
    }
}

/// How the deer look at a moment.
struct StreamCast {
    var doeLeft: CGFloat
    var fawnLeft: CGFloat
    /// The sprite pose shared by both: "drink", "stand", "a", or "b".
    var pose = "drink"
    var showsBang = false

    typealias Timing = AdventureGame.StreamTiming

    init(phase: AdventureGame.Phase, now: Date, layout: StreamLayout, sceneWidth: CGFloat) {
        doeLeft = layout.doeLeft
        fawnLeft = layout.fawnLeft
        guard case .stream(let start) = phase else { return }
        let t = max(0, now.timeIntervalSince(start))
        if t >= Timing.alert {
            pose = "stand"
            showsBang = t < Timing.runs
        }
        if t >= Timing.runs {
            // Bounding off to the right, away from the hunter.
            let run = min((t - Timing.runs) / Timing.runDuration, 1)
            doeLeft = (layout.doeLeft + (sceneWidth + 50 - layout.doeLeft) * run).rounded()
            fawnLeft = (layout.fawnLeft + (sceneWidth + 50 - layout.fawnLeft) * run).rounded()
            pose = Int(t * 8).isMultiple(of: 2) ? "a" : "b"
        }
    }
}

#if DEBUG
#Preview("Poop") {
    AdventureView(game: .preview(scene: 9, phase: .poop(start: .now.addingTimeInterval(-3.2))))
        .ignoresSafeArea()
}

#Preview("Bear: shocked") {
    AdventureView(game: .preview(scene: 10, phase: .bear(start: .now.addingTimeInterval(-0.6))))
        .ignoresSafeArea()
}

#Preview("Fork: walking in") {
    AdventureView(game: .preview(scene: 11, phase: .walking(from: 11, start: .now.addingTimeInterval(-2.4), fromCabinDoor: false)))
        .ignoresSafeArea()
}

#Preview("Bear: rearing") {
    AdventureView(game: .preview(scene: 10, phase: .bear(start: .now.addingTimeInterval(-0.5))))
        .ignoresSafeArea()
}

#Preview("Bear: roar") {
    AdventureView(game: .preview(scene: 10, phase: .bear(start: .now.addingTimeInterval(-3.0))))
        .ignoresSafeArea()
}

#Preview("Bear: looking up at dusk") {
    AdventureView(game: .preview(scene: 10, phase: .bear(start: .now.addingTimeInterval(-11.0))))
        .ignoresSafeArea()
}

#Preview("Stream: drinking") {
    AdventureView(game: .preview(scene: 11, phase: .stream(start: .now)))
        .ignoresSafeArea()
}

#Preview("Stream: deer alert") {
    AdventureView(game: .preview(scene: 11, phase: .stream(start: .now.addingTimeInterval(-1.5))))
        .ignoresSafeArea()
}

#Preview("Leash: tackle box returned") {
    AdventureView(game: .preview(scene: 8, phase: .reunion(.returned, start: .now)))
        .ignoresSafeArea()
}
#endif

// MARK: - Fork and campsite

/// Where the fence, gate, and campground sign sit at the fork (scene-local art pixels).
struct ForkLayout {
    let fenceLeft: CGFloat
    /// The campground sign post's center (the board is centered on it).
    let campSignX: CGFloat

    static let fenceTop = AppArt.groundTop + 2 - AppArt.fence.height
    /// The "CAMPGROUNDS" board is drawn in points (about 160 pt wide); half of it, in points.
    static let boardHalfWidth: CGFloat = 80

    /// `scale` is points per art pixel: the board is a fixed size in points, so its footprint in
    /// art pixels depends on the screen.
    init(sceneWidth width: CGFloat, scale: CGFloat) {
        let boardHalf = Self.boardHalfWidth / scale
        // The sign sits near the right edge, clear of the camera cutout (about 70 pt).
        campSignX = (width - 70 / scale - boardHalf).rounded()
        // The fence ends at least 20 px before the board, and leaves the hunter room to walk up.
        let latestLeft = campSignX - boardHalf - 20 - AppArt.fence.width
        let earliestLeft = 4 + AppArt.hunter.width + 20
        fenceLeft = max(min((width * 0.27).rounded(), latestLeft), earliestLeft).rounded()
    }

    /// Where the padlock hangs.
    var lock: CGPoint {
        CGPoint(x: fenceLeft + AppArt.fenceLock.x, y: Self.fenceTop + AppArt.fenceLock.y)
    }

    /// The hunter's sprite left edge when he's standing at the gate, and once he's walked through it.
    var hunterAtGate: CGFloat { fenceLeft - 14 - AppArt.hunterBodyCenterX }
    var hunterThroughGate: CGFloat { fenceLeft + AppArt.fenceGateWidth / 2 - AppArt.hunterBodyCenterX }
}

/// Where the RV, the campfire, and the campers sit at the campsite (scene-local art pixels).
struct CampsiteLayout {
    let rvCenterX: CGFloat
    let fireCenterX: CGFloat
    let dadLeft: CGFloat
    let kidLeft: CGFloat

    init(sceneWidth width: CGFloat) {
        rvCenterX = max((width * 0.32).rounded(), 4 + AppArt.hunter.width + 8 + AppArt.rv.width / 2)
        fireCenterX = max((width * 0.68).rounded(), rvCenterX + AppArt.rv.width / 2 + 40)
        // Dad's marshmallow (at the right end of his sprite) hangs over the fire; the kid faces him
        // from the other side (mirrored, so the kid's marshmallow is at the sprite's left end).
        dadLeft = fireCenterX - AppArt.camperDad.width + 3
        kidLeft = fireCenterX - 1
    }
}

#if DEBUG
#Preview("Bear: Smokey") {
    AdventureView(game: .preview(scene: 10, phase: .bear(start: .now.addingTimeInterval(-7.5))))
        .ignoresSafeArea()
}

#Preview("Fork: choosing") {
    AdventureView(game: .preview(scene: 12, phase: .fork(.choosing, start: .now.addingTimeInterval(-1))))
        .ignoresSafeArea()
}

#Preview("Fork: locked gate") {
    AdventureView(game: .preview(scene: 12, phase: .fork(.locked, start: .now), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Fork: gate open") {
    AdventureView(game: .preview(scene: 12, phase: .fork(.gateOpening, start: .now.addingTimeInterval(-1.2)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Eerie trail") {
    AdventureView(game: .preview(scene: 13, route: .restricted))
        .ignoresSafeArea()
}

#Preview("UFO arrives") {
    AdventureView(game: .preview(scene: 14, phase: .abduction(start: .now.addingTimeInterval(-4.0)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("UFO beam") {
    AdventureView(game: .preview(scene: 14, phase: .abduction(start: .now.addingTimeInterval(-6.2)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("UFO leaving") {
    AdventureView(game: .preview(scene: 14, phase: .abduction(start: .now.addingTimeInterval(-8.6)), route: .restricted))
        .ignoresSafeArea()
}

#Preview("Campsite") {
    AdventureView(game: .preview(scene: 13, phase: .campsite(start: .now.addingTimeInterval(-4)), route: .campground))
        .ignoresSafeArea()
}
#endif

// MARK: - Rotate prompt

/// Covers the quest on a phone held in portrait: The Hunter's Quest plays in landscape.
struct RotateDeviceCard: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rotate.right")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(Color.pixelOrange)
                .accessibilityHidden(true)
            PixelText("ROTATE YOUR DEVICE", pixelSize: 3)
            PixelText("TO KEEP HUNTING", pixelSize: 2, color: .pixelOrange)
        }
        .padding(28)
        .background(Color.black.opacity(0.92), ignoresSafeAreaEdges: [])
        .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rotate your device to landscape to keep hunting")
    }
}

#if DEBUG
#Preview("Mallard scene") {
    AdventureView(game: .preview(scene: 6))
        .ignoresSafeArea()
}
#endif
