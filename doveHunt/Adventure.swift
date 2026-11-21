//
//  Adventure.swift
//  doveHunt
//
//  "The Hunter's Quest": the companion app's side-scrolling adventure that starts from the
//  home screen. Shoot every dove in a scene and the hunter walks on to the next one, until
//  he reaches the cabin. Its score and records are separate from the widget game's.
//

import Foundation
import Observation

// MARK: - Scene data

/// A dove hovering in a scene. Positions are relative so scenes fit any screen shape.
struct AdventureDove {
    /// Horizontal position as a fraction of the screen width.
    let fractionX: CGFloat
    /// Height above the grass, in art pixels.
    let aboveGround: CGFloat
    /// Offsets the bob and wing beat so doves don't move in lockstep.
    let phase: Double
    let facesRight: Bool
}

/// Scenery standing on the grass.
struct AdventureProp {
    enum Kind {
        case tree
        case bush
        case cabin
    }

    let kind: Kind
    /// Horizontal center as a fraction of the screen width.
    let fractionX: CGFloat
}

/// One screen-wide "slide" of the side-scroller.
struct AdventureScene {
    let doves: [AdventureDove]
    let props: [AdventureProp]
    /// What the hunter walks on in this scene (picks the footstep sound).
    var surface: StepSurface = .grass

    var cabin: AdventureProp? { props.first { $0.kind == .cabin } }
}

enum AdventureScenes {
    static let all: [AdventureScene] = [
        // 1. The home screen meadow.
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0.66, aboveGround: 50, phase: 0.0, facesRight: true),
                AdventureDove(fractionX: 0.84, aboveGround: 72, phase: 1.7, facesRight: true),
                AdventureDove(fractionX: 0.58, aboveGround: 90, phase: 3.1, facesRight: false),
            ],
            props: []
        ),
        // 2. Same meadow, now with a tree, bushes, and one more dove.
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0.50, aboveGround: 58, phase: 0.4, facesRight: true),
                AdventureDove(fractionX: 0.64, aboveGround: 96, phase: 2.2, facesRight: false),
                AdventureDove(fractionX: 0.78, aboveGround: 66, phase: 1.1, facesRight: true),
                AdventureDove(fractionX: 0.88, aboveGround: 104, phase: 2.9, facesRight: true),
            ],
            props: [
                AdventureProp(kind: .bush, fractionX: 0.56),
                AdventureProp(kind: .tree, fractionX: 0.93),
                AdventureProp(kind: .bush, fractionX: 0.76),
            ]
        ),
        // 3. The log cabin. After the visit inside, a dove perches on the chimney.
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .bush, fractionX: 0.18),
                AdventureProp(kind: .cabin, fractionX: 0.62),
                AdventureProp(kind: .bush, fractionX: 0.94),
            ]
        ),
        // 4. Past the cabin: the meadow continues (more to come).
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .tree, fractionX: 0.08),
                AdventureProp(kind: .bush, fractionX: 0.42),
                AdventureProp(kind: .bush, fractionX: 0.86),
            ]
        ),
    ]
}

// MARK: - Records

/// The Hunter's Quest records, kept in the app's own defaults, separate from the widget
/// game's shared `GameStore`.
enum QuestStore {
    static let pointsPerDove = 100

    private enum Key {
        static let lifetimeDoves = "questLifetimeDoves"
        static let completed = "questsCompleted"
        static let bestScore = "questBestScore"
    }

    private static var defaults: UserDefaults { .standard }

    static var lifetimeDoves: Int { defaults.integer(forKey: Key.lifetimeDoves) }
    /// Times the hunter has made it into the cabin.
    static var completed: Int { defaults.integer(forKey: Key.completed) }
    static var bestScore: Int { defaults.integer(forKey: Key.bestScore) }

    static func recordDove() {
        defaults.set(lifetimeDoves + 1, forKey: Key.lifetimeDoves)
    }

    static func recordCabinVisit() {
        defaults.set(completed + 1, forKey: Key.completed)
    }

    static func recordScore(_ score: Int) {
        defaults.set(max(bestScore, score), forKey: Key.bestScore)
    }
}

/// A feather poof left behind by a downed dove, in world art pixels.
struct AdventurePoof: Identifiable {
    let id: Int
    let position: CGPoint
    let date: Date
}

// MARK: - Game state

/// The steps of the cut-scene inside the cabin.
enum InteriorStep: Equatable {
    /// Fading in; the hunter steps through the door and Anna turns to face him.
    case arriving
    /// Anna is talking; tap to continue.
    case speaking(line: Int)
    /// Anna walks out the kitchen's back door.
    case annaLeaving
    /// The hunter looks left, then right, and a "?" pops up.
    case puzzled
    /// The hunter walks back out the front door.
    case leaving
}

/// Drives The Hunter's Quest. Time-based motion (walking, scrolling, fades) is computed from
/// the phase's start date each frame; phase changes are scheduled with short tasks.
@Observable
final class AdventureGame {
    enum Phase: Equatable {
        /// Waiting for the player to shoot the scene's doves.
        case hunting
        /// Walking from scene `from` to the next one (from the cabin door if `fromCabinDoor`).
        case walking(from: Int, start: Date, fromCabinDoor: Bool)
        /// At the cabin, showing the "Enter the cabin?" prompt.
        case cabinPrompt
        /// Walking to the door and stepping inside, then fading to black.
        case enteringCabin(start: Date)
        /// Inside the cabin.
        case interior(InteriorStep, start: Date)
        /// End of the content so far: fade to "TO BE CONTINUED...".
        case finished(start: Date)
    }

    // Timing.
    static let walkDuration: TimeInterval = 3.6
    static let walkFrameRate: Double = 8
    static let pauseBeforeWalking: TimeInterval = 0.7
    static let enterWalkDuration: TimeInterval = 2.2
    static let enterFadeDuration: TimeInterval = 1.0
    static let fadeInDuration: TimeInterval = 0.8
    static let flashDuration: TimeInterval = 0.12
    static let poofDuration: TimeInterval = 0.45

    /// Interior cut-scene timing (seconds from the start of each step).
    enum InteriorTiming {
        static let stepInStart: TimeInterval = 0.2
        static let stepInDuration: TimeInterval = 1.2
        static let annaTurns: TimeInterval = 1.5
        static let dialogAppears: TimeInterval = 2.0
        static let annaWalkDuration: TimeInterval = 1.6
        static let backDoorOpens: TimeInterval = 1.1
        static let annaGone: TimeInterval = 1.9
        static let backDoorCloses: TimeInterval = 2.3
        static let annaStepDone: TimeInterval = 2.6
        static let looksRight: TimeInterval = 0.55
        static let questionAppears: TimeInterval = 1.1
        static let puzzledDone: TimeInterval = 2.7
        static let leaveWalkDuration: TimeInterval = 1.4
        static let leaveFadeStart: TimeInterval = 1.2
        static let leaveDone: TimeInterval = 2.1
    }

    /// What Anna says, one box per tap.
    static let annaLines = [
        "A shotgun-wielding stranger won't just walk into our cabin he said, the lock can be fixed tomorrow he said...",
        "Could you lower your weapon sir? I already changed the baby's diaper and now I have to change mine, thanks.",
    ]

    private(set) var scene = 0
    private(set) var phase: Phase = .hunting
    /// Downed doves per scene.
    private(set) var downed: [Int: Set<Int>] = [:]
    private(set) var poofs: [AdventurePoof] = []
    /// The muzzle flash is showing.
    private(set) var isFiring = false
    /// Every trigger pull, for haptics.
    private(set) var shotCount = 0
    /// Doves bagged on this run.
    private(set) var bagged = 0
    /// The hunter has been inside the cabin (he now stands at its door, and a dove sits on the chimney).
    private(set) var cabinVisited = false
    private(set) var chimneyDoveDown = false
    /// Fading in from black after stepping back outside.
    private(set) var fadeInStart: Date?

    /// This run's score.
    var score: Int { bagged * QuestStore.pointsPerDove }

    private let sounds = SoundEffects.shared

    /// Bumped on restart so stale scheduled transitions are ignored.
    private var generation = 0
    private var nextPoofID = 0

    /// The home screen title shows until the hunter sets off.
    var showsTitle: Bool { scene == 0 && phase == .hunting }

    var isInterior: Bool {
        if case .interior = phase { return true }
        return false
    }

    var isFinished: Bool {
        if case .finished = phase { return true }
        return false
    }

    /// Something is animating over time (walking, a cut-scene, or a fade).
    var isMoving: Bool {
        switch phase {
        case .hunting, .cabinPrompt: fadeInStart != nil
        default: true
        }
    }

    /// The chimney dove is waiting to be shot.
    var showsChimneyDove: Bool {
        cabinVisited && !chimneyDoveDown && AdventureScenes.all[scene].cabin != nil
    }

    func isDown(scene: Int, dove: Int) -> Bool {
        downed[scene]?.contains(dove) ?? false
    }

    /// Shoots a dove in the current scene at its current world position.
    func shoot(dove index: Int, at position: CGPoint) {
        guard phase == .hunting, !isDown(scene: scene, dove: index) else { return }
        downed[scene, default: []].insert(index)
        bag(at: position)

        let sceneDoves = AdventureScenes.all[scene].doves.count
        if downed[scene]?.count == sceneDoves {
            after(Self.pauseBeforeWalking) { $0.startWalking() }
        }
    }

    /// Shoots the dove perched on the cabin chimney, which sends the hunter onward.
    func shootChimneyDove(at position: CGPoint) {
        guard phase == .hunting, showsChimneyDove else { return }
        chimneyDoveDown = true
        bag(at: position)
        after(Self.pauseBeforeWalking) { $0.startWalking() }
    }

    /// A shot at empty sky: the gun still fires.
    func shootMiss() {
        guard phase == .hunting else { return }
        fire()
    }

    func enterCabin() {
        guard phase == .cabinPrompt else { return }
        phase = .enteringCabin(start: Date())
        playFootsteps(for: Self.enterWalkDuration, on: AdventureScenes.all[scene].surface)
        after(Self.enterWalkDuration + Self.enterFadeDuration) { $0.beginInterior() }
    }

    /// Tap during Anna's speech: show her next line, or let her leave after the last one.
    func advanceDialog() {
        guard case .interior(.speaking(let line), _) = phase else { return }
        if line + 1 < Self.annaLines.count {
            phase = .interior(.speaking(line: line + 1), start: Date())
        } else {
            annaLeaves()
        }
    }

    func restart() {
        generation += 1
        scene = 0
        phase = .hunting
        downed = [:]
        poofs = []
        isFiring = false
        bagged = 0
        cabinVisited = false
        chimneyDoveDown = false
        fadeInStart = nil
    }

    #if DEBUG
    /// Jumps straight to a scene, for previews.
    static func preview(scene: Int, phase: Phase = .hunting, cabinVisited: Bool = false) -> AdventureGame {
        let game = AdventureGame()
        game.scene = scene
        game.phase = phase
        game.cabinVisited = cabinVisited
        game.bagged = scene == 0 ? 0 : 3 + (scene > 1 ? 4 : 0)
        return game
    }
    #endif

    // MARK: Private

    private func bag(at position: CGPoint) {
        fire()
        bagged += 1
        QuestStore.recordDove()
        after(0.06) { game in game.sounds.squawk() }
        let poofID = nextPoofID
        nextPoofID += 1
        poofs.append(AdventurePoof(id: poofID, position: position, date: Date()))
        after(Self.poofDuration) { game in game.poofs.removeAll { $0.id == poofID } }
    }

    private func fire() {
        sounds.gunshot()
        shotCount += 1
        isFiring = true
        let shot = shotCount
        after(Self.flashDuration) { game in
            if game.shotCount == shot { game.isFiring = false }
        }
    }

    private func startWalking() {
        guard phase == .hunting, scene + 1 < AdventureScenes.all.count else { return }
        let fromCabinDoor = cabinVisited && AdventureScenes.all[scene].cabin != nil
        phase = .walking(from: scene, start: Date(), fromCabinDoor: fromCabinDoor)
        playFootsteps(for: Self.walkDuration, on: AdventureScenes.all[scene].surface)
        after(Self.walkDuration) { $0.arriveAtNextScene() }
    }

    /// One footstep on each stride frame of the walk cycle (every other frame).
    private func playFootsteps(for duration: TimeInterval, on surface: StepSurface, after delay: TimeInterval = 0) {
        let interval = 2 / Self.walkFrameRate
        for step in 0..<Int(duration / interval) {
            after(delay + Double(step) * interval) { game in game.sounds.step(on: surface) }
        }
    }

    private func arriveAtNextScene() {
        scene += 1
        poofs = []
        let next = AdventureScenes.all[scene]
        if next.cabin != nil, !cabinVisited {
            phase = .cabinPrompt
        } else {
            phase = .hunting
            if next.doves.isEmpty {
                if scene + 1 < AdventureScenes.all.count {
                    after(Self.pauseBeforeWalking) { $0.startWalking() }
                } else {
                    after(1.0) { $0.finish() }
                }
            }
        }
    }

    // MARK: Interior cut-scene

    private func beginInterior() {
        phase = .interior(.arriving, start: Date())
        QuestStore.recordCabinVisit()
        playFootsteps(for: InteriorTiming.stepInDuration, on: .wood, after: InteriorTiming.stepInStart)
        after(InteriorTiming.dialogAppears) { game in
            game.phase = .interior(.speaking(line: 0), start: Date())
        }
    }

    private func annaLeaves() {
        phase = .interior(.annaLeaving, start: Date())
        playFootsteps(for: InteriorTiming.annaWalkDuration, on: .wood)
        after(InteriorTiming.annaStepDone) { game in
            game.phase = .interior(.puzzled, start: Date())
            game.after(InteriorTiming.puzzledDone) { $0.hunterLeaves() }
        }
    }

    private func hunterLeaves() {
        phase = .interior(.leaving, start: Date())
        playFootsteps(for: InteriorTiming.leaveWalkDuration, on: .wood)
        after(InteriorTiming.leaveDone) { $0.stepBackOutside() }
    }

    /// Back on the cabin scene: the hunter stands at the door, a dove waits on the chimney.
    private func stepBackOutside() {
        cabinVisited = true
        poofs = []
        phase = .hunting
        let fadeStart = Date()
        fadeInStart = fadeStart
        after(Self.fadeInDuration + 0.1) { game in
            if game.fadeInStart == fadeStart { game.fadeInStart = nil }
        }
    }

    private func finish() {
        guard phase == .hunting else { return }
        QuestStore.recordScore(score)
        phase = .finished(start: Date())
    }

    /// Runs `action` after `delay`, unless the game was restarted in the meantime.
    private func after(_ delay: TimeInterval, _ action: @escaping (AdventureGame) -> Void) {
        let scheduledGeneration = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.generation == scheduledGeneration else { return }
            action(self)
        }
    }
}
