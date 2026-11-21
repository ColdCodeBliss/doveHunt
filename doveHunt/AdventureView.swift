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

    @AppStorage(AppSettings.animatedDovesKey) private var animatedDoves = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Approximate height of the header overlay (title + score + hint, or the small HUD), in points.
    private var headerHeight: CGFloat { game.showsTitle ? 270 : 80 }

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
                let frame = AdventureFrame(game: game, now: now, sceneWidth: world.sceneWidth)

                if case .interior(let step, let start) = game.phase {
                    InteriorView(game: game, step: step, stepStart: start, screen: screen, now: now)
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

                    ForEach(visibleScenes(camera: frame.camera, sceneWidth: world.sceneWidth), id: \.self) { sceneIndex in
                        doves(sceneIndex: sceneIndex, world: world, frame: frame, time: time)
                    }

                    if game.showsChimneyDove {
                        chimneyDove(world: world, frame: frame, time: time)
                    }

                    poofs(world: world, frame: frame, now: now)

                    hunter(world: world, frame: frame)

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
        .sensoryFeedback(.impact(weight: .medium), trigger: game.shotCount)
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
        let scene = AdventureScenes.all[sceneIndex]
        return ForEach(scene.props.indices, id: \.self) { index in
            let prop = scene.props[index]
            let centerX = world.sceneOrigin(sceneIndex) + (prop.fractionX * world.sceneWidth).rounded()
            switch prop.kind {
            case .tree:
                propSprite("prop_tree", size: AppArt.tree, centerX: centerX, sink: 2, world: world, frame: frame)
            case .bush:
                propSprite("prop_bush", size: AppArt.bush, centerX: centerX, sink: 2, world: world, frame: frame)
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

    private func doves(sceneIndex: Int, world: AdventureWorld, frame: AdventureFrame, time: Double) -> some View {
        let scene = AdventureScenes.all[sceneIndex]
        let canShoot = sceneIndex == game.scene && game.phase == .hunting
        // Keep doves below the header overlay on short screens.
        let belowHeader = world.visibleMinY + headerHeight / world.scale + AppArt.dove.height

        return ForEach(scene.doves.indices, id: \.self) { index in
            if !game.isDown(scene: sceneIndex, dove: index) {
                let dove = scene.doves[index]
                let edge = AppArt.dove.width / 2 + 4
                let localX = min(max((dove.fractionX * world.sceneWidth).rounded(), edge), world.sceneWidth - edge)
                let restX = world.sceneOrigin(sceneIndex) + localX
                let restY = min(max(AppArt.groundTop - dove.aboveGround, belowHeader), AppArt.groundTop - AppArt.dove.height).rounded()
                // Gentle hover, snapped to whole art pixels for retro motion.
                let dx = (sin(time * 0.7 + dove.phase) * 3).rounded()
                let dy = (sin(time * 1.6 + dove.phase) * 2).rounded()
                let wingsUp = Int(time * 4 + dove.phase).isMultiple(of: 2)
                let position = CGPoint(x: restX + dx, y: restY + dy)

                AppSprite(name: wingsUp ? "dove_wings_up" : "dove_wings_down", size: AppArt.dove, scale: world.scale)
                    .scaleEffect(x: dove.facesRight ? 1 : -1)
                    // A slightly larger target than the sprite, for comfortable tapping.
                    .padding(3 * world.scale)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if canShoot { game.shoot(dove: index, at: position) }
                    }
                    .position(world.point(position.x, position.y, camera: frame.camera))
                    .accessibilityElement()
                    .accessibilityLabel("Dove")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { if canShoot { game.shoot(dove: index, at: position) } }
            }
        }
    }

    /// The dove perched on the cabin chimney after the visit inside.
    private func chimneyDove(world: AdventureWorld, frame: AdventureFrame, time: Double) -> some View {
        let cabinX = world.sceneOrigin(game.scene) + world.cabinCenter(fraction: AdventureScenes.all[game.scene].cabin?.fractionX ?? 0.6)
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
                .scaleEffect(0.7 + 0.6 * age)
                .opacity(1 - age * 0.8)
                .position(world.point(poof.position.x, poof.position.y, camera: frame.camera))
        }
        .allowsHitTesting(false)
    }

    private func hunter(world: AdventureWorld, frame: AdventureFrame) -> some View {
        let size = AppArt.hunter
        let top = AppArt.groundTop + 3 - size.height
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
        let cabinX = world.sceneOrigin(game.scene) + world.cabinCenter(fraction: AdventureScenes.all[game.scene].cabin?.fractionX ?? 0.6)
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
        let last = min(AdventureScenes.all.count - 1, Int(((camera + sceneWidth - 1) / sceneWidth).rounded(.down)))
        return first <= last ? Array(first...last) : []
    }

    private func handleBackgroundTap() {
        switch game.phase {
        case .hunting: game.shootMiss()
        case .cabinPrompt: game.enterCabin()
        case .finished: game.restart()
        default: break
        }
    }

    private var backgroundTapLabel: String {
        switch game.phase {
        case .cabinPrompt: "Enter the cabin"
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
    var doorOpen = false
    var blackout: Double = 0

    init(game: AdventureGame, now: Date, sceneWidth: CGFloat) {
        let restCamera = CGFloat(game.scene) * sceneWidth
        camera = restCamera
        // After visiting the cabin, the hunter stands at its door.
        let restOffset = game.cabinVisited && AdventureScenes.all[game.scene].cabin != nil
            ? Self.cabinDoorOffset(scene: game.scene, sceneWidth: sceneWidth)
            : 4
        hunterLeft = restCamera + restOffset
        if let fadeStart = game.fadeInStart {
            blackout = max(0, 1 - now.timeIntervalSince(fadeStart) / AdventureGame.fadeInDuration)
        }

        switch game.phase {
        case .hunting, .cabinPrompt:
            break

        case .walking(let from, let start, let fromCabinDoor):
            // The hunter walks one full scene at a steady pace. The camera lets him stride
            // toward the middle of the screen, then catches up so he arrives back at the left
            // edge of the next scene, like a classic side-scroller.
            let elapsed = max(0, now.timeIntervalSince(start))
            let progress = min(elapsed / AdventureGame.walkDuration, 1)
            let origin = CGFloat(from) * sceneWidth
            let startOffset = fromCabinDoor ? Self.cabinDoorOffset(scene: from, sceneWidth: sceneWidth) : 4
            hunterLeft = (origin + startOffset + (sceneWidth + 4 - startOffset) * progress).rounded()
            camera = (origin + sceneWidth * progress - 0.3 * sceneWidth * sin(.pi * progress)).rounded()
            hunterSprite = Self.walkFrame(elapsed: elapsed)

        case .enteringCabin(let start):
            let elapsed = max(0, now.timeIntervalSince(start))
            let walk = min(elapsed / AdventureGame.enterWalkDuration, 1)
            let cabinX = restCamera + AdventureWorld.cabinCenter(fraction: AdventureScenes.all[game.scene].cabin?.fractionX ?? 0.6, sceneWidth: sceneWidth)
            let doorX = cabinX - AppArt.cabin.width / 2 + AppArt.cabinDoorCenterX
            let target = doorX - AppArt.hunterBodyCenterX
            hunterLeft = (restCamera + 4 + (target - restCamera - 4) * walk).rounded()
            hunterSprite = walk < 1 ? Self.walkFrame(elapsed: elapsed) : "hunter"
            doorOpen = walk > 0.6
            let inside = elapsed - AdventureGame.enterWalkDuration
            hunterOpacity = inside <= 0 ? 1 : max(0, 1 - inside / 0.35)
            blackout = min(max(inside / AdventureGame.enterFadeDuration, 0), 1)

        case .interior:
            doorOpen = true
            hunterOpacity = 0
            blackout = 1

        case .finished(let start):
            blackout = min(now.timeIntervalSince(start) / AdventureGame.enterFadeDuration, 1)
        }
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
