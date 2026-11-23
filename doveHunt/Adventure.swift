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

/// The birds of The Hunter's Quest.
enum BirdKind {
    case dove
    /// Tougher: the first shot only wounds it, the second brings it down. Worth double.
    case mallard

    var shotsToDown: Int {
        switch self {
        case .dove: 1
        case .mallard: 2
        }
    }

    var points: Int {
        switch self {
        case .dove: QuestStore.pointsPerDove
        case .mallard: QuestStore.pointsPerDove * 2
        }
    }
}

/// A bird hovering in a scene. Positions are relative so scenes fit any screen shape.
struct AdventureDove {
    /// Horizontal position as a fraction of the screen width.
    let fractionX: CGFloat
    /// Height above the grass, in art pixels.
    let aboveGround: CGFloat
    /// Offsets the bob and wing beat so doves don't move in lockstep.
    let phase: Double
    let facesRight: Bool
    var kind: BirdKind = .dove
}

/// Scenery standing on the grass.
struct AdventureProp {
    enum Kind {
        case tree
        case bush
        case cabin
        /// The fishing pond (placed by `PondLayout`, which ignores `fractionX`).
        case pond
        case pine
        /// A distant mountain range on the horizon (list it first so it sits behind everything).
        case mountains
        /// A winding stream in the grass (placed by `StreamLayout`, which ignores `fractionX`).
        case stream
        /// The far mountain behind the restricted gate (placed by `ForkLayout`, which ignores `fractionX`).
        case farMountain
        /// A dirt trail across the whole scene (ignores `fractionX`).
        case dirtPath
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
    /// The fisherman-and-Max scene: doves fly out of the pond after his greeting, and the
    /// gunfire sends both of them running.
    var hasPondEvent = false
    /// The fisherman and Max again: they bolt at the sight of the hunter, and the fisherman
    /// drops his tackle box for the hunter to pick up.
    var hasTackleBoxEvent = false
    /// The fisherman again, with Max on a leash: they walk up to the hunter for a word.
    var hasReunionEvent = false
    /// Doves fly over the hunter (unshootable) and poop on him.
    var hasPoopEvent = false
    /// A bear rears up, bluff-charges, and roars; two warning shots send it off, and dusk falls.
    var hasBearEvent = false
    /// Deer drink at a stream while two mallards float on it. The deer bolt, then the mallards take off.
    var hasStreamEvent = false
    /// The fork in the trail: a campground sign, and a fenced-off "Restricted Access" path.
    var hasForkEvent = false
    /// The campsite: an RV, a campfire, and a dad and kid roasting marshmallows.
    var hasCampsiteEvent = false
    /// The restricted route: night, a dirt trail, and an eerie wind.
    var isEerie = false
    /// The UFO abduction.
    var hasAbductionEvent = false
    /// For a scene with no birds: how long the hunter waits before walking on.
    var linger: TimeInterval = AdventureGame.pauseBeforeWalking
    /// The doves only appear once the scene's scripted moment is over (pond, tackle box, stream).
    var dovesFlyIn: Bool { hasPondEvent || hasTackleBoxEvent || hasStreamEvent }
    /// The birds start floating on the stream and take off from it, instead of flying in from the edge.
    var birdsStartOnWater: Bool { hasStreamEvent }

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
        // 4. Past the cabin: the meadow continues, with five doves.
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0.40, aboveGround: 60, phase: 0.3, facesRight: true),
                AdventureDove(fractionX: 0.52, aboveGround: 96, phase: 1.9, facesRight: false),
                AdventureDove(fractionX: 0.64, aboveGround: 70, phase: 0.9, facesRight: true),
                AdventureDove(fractionX: 0.76, aboveGround: 104, phase: 2.6, facesRight: false),
                AdventureDove(fractionX: 0.88, aboveGround: 62, phase: 1.4, facesRight: true),
            ],
            props: [
                AdventureProp(kind: .tree, fractionX: 0.08),
                AdventureProp(kind: .bush, fractionX: 0.42),
                AdventureProp(kind: .bush, fractionX: 0.86),
            ]
        ),
        // 5. The pond: a fisherman and his dog, Max. Three doves fly out over the water
        //    (their positions come from `PondLayout`).
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0, aboveGround: 46, phase: 0.5, facesRight: true),
                AdventureDove(fractionX: 0, aboveGround: 72, phase: 2.1, facesRight: false),
                AdventureDove(fractionX: 0, aboveGround: 56, phase: 1.2, facesRight: true),
            ],
            props: [
                AdventureProp(kind: .pond, fractionX: 0.5),
            ],
            hasPondEvent: true
        ),
        // 6. Mountains on the horizon; five doves and the first mallard (takes two shots).
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0.38, aboveGround: 64, phase: 0.2, facesRight: true),
                AdventureDove(fractionX: 0.50, aboveGround: 100, phase: 1.6, facesRight: false),
                AdventureDove(fractionX: 0.62, aboveGround: 58, phase: 2.4, facesRight: true),
                AdventureDove(fractionX: 0.74, aboveGround: 92, phase: 0.8, facesRight: false),
                AdventureDove(fractionX: 0.86, aboveGround: 70, phase: 2.9, facesRight: true),
                AdventureDove(fractionX: 0.68, aboveGround: 118, phase: 1.2, facesRight: false, kind: .mallard),
            ],
            props: [
                AdventureProp(kind: .mountains, fractionX: 0.55),
                AdventureProp(kind: .pine, fractionX: 0.12),
                AdventureProp(kind: .bush, fractionX: 0.46),
                AdventureProp(kind: .tree, fractionX: 0.93),
            ]
        ),
        // 7. Pines and rolling mountains; four doves and two mallards.
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0.42, aboveGround: 72, phase: 0.6, facesRight: true),
                AdventureDove(fractionX: 0.58, aboveGround: 104, phase: 2.0, facesRight: false),
                AdventureDove(fractionX: 0.72, aboveGround: 60, phase: 1.3, facesRight: true),
                AdventureDove(fractionX: 0.88, aboveGround: 96, phase: 2.7, facesRight: false),
                AdventureDove(fractionX: 0.50, aboveGround: 124, phase: 0.4, facesRight: true, kind: .mallard),
                AdventureDove(fractionX: 0.80, aboveGround: 128, phase: 1.9, facesRight: false, kind: .mallard),
            ],
            props: [
                AdventureProp(kind: .mountains, fractionX: 0.30),
                AdventureProp(kind: .mountains, fractionX: 0.85),
                AdventureProp(kind: .bush, fractionX: 0.34),
                AdventureProp(kind: .pine, fractionX: 0.64),
                AdventureProp(kind: .pine, fractionX: 0.90),
            ]
        ),
        // 8. The fisherman and Max, mid-meadow. They run off and he drops his tackle box.
        //    Once it's picked up, three doves and a mallard fly in.
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0.46, aboveGround: 64, phase: 0.7, facesRight: true),
                AdventureDove(fractionX: 0.62, aboveGround: 98, phase: 2.3, facesRight: false),
                AdventureDove(fractionX: 0.80, aboveGround: 70, phase: 1.5, facesRight: true),
                AdventureDove(fractionX: 0.70, aboveGround: 124, phase: 0.2, facesRight: false, kind: .mallard),
            ],
            props: [
                AdventureProp(kind: .bush, fractionX: 0.20),
                AdventureProp(kind: .tree, fractionX: 0.88),
            ],
            hasTackleBoxEvent: true
        ),
        // 9. The fisherman has Max on a leash by a tree. They walk over for a word.
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .bush, fractionX: 0.62),
                AdventureProp(kind: .tree, fractionX: 0.86),
            ],
            hasReunionEvent: true
        ),
        // 10. Doves fly over and poop on the hunter. Karma.
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .tree, fractionX: 0.14),
                AdventureProp(kind: .bush, fractionX: 0.58),
                AdventureProp(kind: .pine, fractionX: 0.86),
            ],
            hasPoopEvent: true
        ),
        // 11. A brown bear in the pines. Two warning shots send it off, and the sun starts to set.
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .mountains, fractionX: 0.50),
                AdventureProp(kind: .pine, fractionX: 0.40),
                AdventureProp(kind: .pine, fractionX: 0.94),
            ],
            hasBearEvent: true
        ),
        // 12. A doe and her fawn drink at a stream with two mallards floating on it.
        AdventureScene(
            doves: [
                AdventureDove(fractionX: 0.48, aboveGround: 104, phase: 0.6, facesRight: true, kind: .mallard),
                AdventureDove(fractionX: 0.60, aboveGround: 124, phase: 1.8, facesRight: false, kind: .mallard),
            ],
            props: [
                AdventureProp(kind: .stream, fractionX: 0.6),
                AdventureProp(kind: .bush, fractionX: 0.20),
                AdventureProp(kind: .tree, fractionX: 0.94),
            ],
            hasStreamEvent: true
        ),
        // 13. A fork in the trail. Tap a sign to pick the route (see `QuestRoute`).
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .farMountain, fractionX: 0),
                AdventureProp(kind: .bush, fractionX: 0.70),
            ],
            hasForkEvent: true
        ),
    ]

    /// After the fork: the campground route.
    static let campgroundRoute: [AdventureScene] = [
        // The campsite: an RV, a campfire, a dad and kid roasting marshmallows.
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .pine, fractionX: 0.52),
            ],
            hasCampsiteEvent: true
        ),
        // More to come.
        AdventureScene(
            doves: [],
            props: [
                AdventureProp(kind: .bush, fractionX: 0.3),
                AdventureProp(kind: .pine, fractionX: 0.9),
            ]
        ),
    ]

    /// After the fork: through the gate on the restricted route. It's night now.
    static let restrictedRoute: [AdventureScene] = [
        // A bare dirt trail in the wind. The hunter pauses, then walks on by himself.
        AdventureScene(
            doves: [],
            props: [AdventureProp(kind: .dirtPath, fractionX: 0)],
            isEerie: true,
            linger: 3.0
        ),
        // The UFO.
        AdventureScene(
            doves: [],
            props: [AdventureProp(kind: .dirtPath, fractionX: 0)],
            isEerie: true,
            hasAbductionEvent: true
        ),
    ]
}

/// Which way the hunter went at the fork in the trail.
enum QuestRoute {
    case campground
    case restricted

    var scenes: [AdventureScene] {
        switch self {
        case .campground: AdventureScenes.campgroundRoute
        case .restricted: AdventureScenes.restrictedRoute
        }
    }
}

// MARK: - Inventory

/// Something the hunter picks up and carries for the rest of the run.
enum InventoryItem: String, CaseIterable, Identifiable {
    case tackleBox
    case clipboard

    var id: String { rawValue }

    var name: String {
        switch self {
        case .tackleBox: "TACKLE BOX"
        case .clipboard: "CLIPBOARD"
        }
    }

    var spriteName: String {
        switch self {
        case .tackleBox: "tackle_box"
        case .clipboard: "clipboard"
        }
    }

    var spriteSize: CGSize {
        switch self {
        case .tackleBox: AppArt.tackleBox
        case .clipboard: AppArt.clipboard
        }
    }

    /// Shown when the item is tapped in the inventory.
    var details: String {
        switch self {
        case .tackleBox:
            "The fisherman dropped this while chasing Max. Hooks, lures, and half a pickle sandwich. We should probably return it... it's the least we can do after ruining his peace and quiet."
        case .clipboard:
            "An alien scientist dropped this while fleeing his own experiment. It's all squiggles, except a doodle of a dove with a big X on it... and a little drawing of a pickle sandwich. Probably important."
        }
    }
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

/// A feather poof left behind by a downed bird (or a small puff when a mallard is wounded),
/// in world art pixels.
struct AdventurePoof: Identifiable {
    let id: Int
    let position: CGPoint
    let date: Date
    var scale: CGFloat = 1
}

// MARK: - Alien console

/// The alien console mini game: Simon says on a 4x4 grid. Three sequences right wins;
/// two wrong locks the console down and it starts over.
struct ConsoleState {
    enum Stage: Equatable {
        /// Powering up (fading in from black).
        case booting
        /// The sequence plays back.
        case showing
        /// The player repeats it.
        case input
        /// Brief feedback after a sequence.
        case correct
        case wrong
        /// Two misses: "SYSTEM LOCKDOWN", fade to black, and start over.
        case lockdown
        /// Three right: "ACCESS GRANTED", then fade to black.
        case granted
    }

    /// The most recent tap on the grid, for its flash.
    struct Tap {
        let cell: Int
        let color: Int
        let date: Date
    }

    static let cells = 16
    static let colorCount = 5
    static let toWin = 3
    static let toLose = 2

    var stage: Stage = .booting
    var stageStart = Date()
    /// Grid cells (0..<16, row by row) to flash, and the color each one flashes.
    var sequence: [Int] = []
    var colors: [Int] = []
    /// How many of the sequence the player has entered so far.
    var entered = 0
    /// Each finished sequence, in order: true if it was matched.
    var results: [Bool] = []
    var lastTap: Tap?
    /// Bumped on every stage change so stale scheduled steps are ignored.
    var token = 0

    var correctCount: Int { results.filter { $0 }.count }
    var wrongCount: Int { results.filter { !$0 }.count }
}

// MARK: - Game state

/// The steps of the pond scene.
enum PondStep: Equatable {
    /// "Ahh, finally some peace and quiet." Then the doves fly out of the pond.
    case greeting
    /// The gunfire startles Max: he stands, a "!" pops up, and he runs off to the right.
    case dogStartled
    /// The fisherman yells, puts his pole away, and runs after Max.
    case fishermanYells
    /// "Whoops" over the hunter, then he walks on.
    case whoops
}

/// The steps of the tackle box scene.
enum TackleStep: Equatable {
    /// Max spots the hunter and bolts off to the right; the fisherman chases him and drops his tackle box.
    case fleeing
    /// The box sits in the grass under a bobbing arrow until it's tapped.
    case waiting
    /// Picked up: "Tackle box added to inventory!", then the hunter walks on.
    case collected
}

/// The steps of the leash scene.
enum ReunionStep: Equatable {
    /// The fisherman walks Max over on his new leash.
    case approaching
    /// The conversation; tap to continue.
    case talking(line: Int)
    /// "Tackle box removed from inventory" pops up, then the hunter walks on.
    case returned
}

/// Who's talking outdoors.
enum Speaker {
    case fisherman
    case hunter
}

/// The steps at the fork in the trail.
enum ForkStep: Equatable {
    /// Waiting for the player to tap a sign.
    case choosing
    /// The restricted route: walking up to the gate.
    case toGate
    /// At the gate: the lock flashes until it's shot.
    case locked
    /// The lock is shot off; the gate swings open and the hunter steps through (fade to black).
    case gateOpening
}

/// The steps of the specimen-vat lab aboard the UFO.
enum VatStep: Equatable {
    /// The hunter shoots the vats, the birds rise as skeletons and chase off the scientist.
    case scripted
    /// The dropped clipboard waits under a bobbing arrow until it's tapped.
    case waiting
    /// Picked up: "Clipboard added to inventory!", then the inventory opens on it.
    case collected
    /// The inventory was closed: the hunter walks on.
    case leaving
}

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
        /// The pond scene's scripted moments (dialog, the dog and fisherman running off).
        case pond(PondStep, start: Date)
        /// The tackle box scene: the fisherman and Max run off, and the dropped box waits to be picked up.
        case tackleBox(TackleStep, start: Date)
        /// The fisherman and Max (on a leash) walk up for a word with the hunter.
        case reunion(ReunionStep, start: Date)
        /// Doves fly over the hunter and poop on him; then his remark.
        case poop(start: Date)
        /// The bear encounter; then dusk and the hunter's remark.
        case bear(start: Date)
        /// The deer at the stream run off; the mallards are about to take off.
        case stream(start: Date)
        /// The fork in the trail.
        case fork(ForkStep, start: Date)
        /// At the campsite; a proceed arrow appears after a few seconds.
        case campsite(start: Date)
        /// The hunter walks to the middle, a UFO arrives, beams him up, and flies off.
        case abduction(start: Date)
        /// The alien console mini game (state in `console`).
        case console
        /// Aboard the UFO (without his shotgun).
        case aboard(start: Date)
        /// The aliens' lab: two aliens, a table, and the hunter's shotgun.
        case aliens(start: Date)
        /// The specimen-vat lab: a dove and a mallard in vats, a scientist, and two skeletons.
        case vats(VatStep, start: Date)
        /// A lab wrecked by the chase; the hunter looks around, puzzled.
        case wreckedLab(start: Date)
        /// A pristine lab: the scientist in a vat, the skeletons in lab coats; the hunter leaves the clipboard.
        case pristineLab(start: Date)
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

    /// Pond scene timing (seconds from the start of each step).
    enum PondTiming {
        static let greetingShows: TimeInterval = 0.4
        static let greetingHides: TimeInterval = 3.6
        static let dovesRelease: TimeInterval = 3.9
        /// Each pond dove's flight in from the right edge, and the gap between one dove and the next.
        static let doveFlyIn: TimeInterval = 1.6
        static let doveFlyInStagger: TimeInterval = 0.3
        static let pauseAfterLastDove: TimeInterval = 0.5
        static let bangShows: TimeInterval = 0.15
        static let dogRuns: TimeInterval = 1.1
        static let dogRunDuration: TimeInterval = 1.1
        static let dogDone: TimeInterval = 2.3
        static let yellHides: TimeInterval = 3.8
        static let fishermanRunDuration: TimeInterval = 1.3
        static let yellDone: TimeInterval = 5.2
        static let whoopsShows: TimeInterval = 0.2
        static let whoopsDone: TimeInterval = 2.2
    }

    /// Tackle box scene timing (seconds from the start of each step).
    enum TackleTiming {
        static let bangShows: TimeInterval = 0.3
        static let dogRuns: TimeInterval = 0.9
        static let dogRunDuration: TimeInterval = 1.2
        static let fishermanRuns: TimeInterval = 1.4
        static let fishermanRunDuration: TimeInterval = 1.4
        /// The box falling from his hand to the grass as he turns to run.
        static let boxFall: TimeInterval = 0.3
        /// "Max, wait!" over the fisherman as Max bolts.
        static let waitShows: TimeInterval = 1.0
        static let waitHides: TimeInterval = 2.6
        static let fleeDone: TimeInterval = 3.0
        static let collectedDone: TimeInterval = 2.0
    }

    /// Leash scene timing.
    enum ReunionTiming {
        static let approachDuration: TimeInterval = 2.8
        static let talkStarts: TimeInterval = 3.1
        /// How long "Tackle box removed from inventory" shows.
        static let returnedDuration: TimeInterval = 2.4
    }

    /// Poop scene timing (seconds from the start of the scene).
    enum PoopTiming {
        /// Each dove's flight across the screen, and the gap between one dove and the next.
        static let crossDuration: TimeInterval = 2.4
        static let stagger: TimeInterval = 0.6
        /// A dropping's fall from the dove to the hunter.
        static let fall: TimeInterval = 0.45
        /// A splat stays fully visible, then slowly fades.
        static let splatHold: TimeInterval = 0.8
        static let splatFade: TimeInterval = 3.2
        static let remarkShows: TimeInterval = 4.2
        static let remarkHides: TimeInterval = 8.6
        static let done: TimeInterval = 9.0
    }

    /// Bear scene timing (seconds from the start of the scene).
    enum BearTiming {
        /// The hunter's wide-eyed double take when he first sees the bear.
        static let shockedStarts: TimeInterval = 0.1
        static let shockedEnds: TimeInterval = 1.2
        static let dropsToFours: TimeInterval = 1.4
        static let chargeStarts: TimeInterval = 1.8
        static let chargeDuration: TimeInterval = 0.6
        static let roarStarts: TimeInterval = 2.5
        static let roarEnds: TimeInterval = 3.7
        static let firstShot: TimeInterval = 4.0
        static let secondShot: TimeInterval = 4.5
        static let fleeStarts: TimeInterval = 4.9
        static let fleeDuration: TimeInterval = 1.4
        /// "Wow, Smokey Bear put on some weight.."
        static let smokeyShows: TimeInterval = 6.6
        static let smokeyHides: TimeInterval = 9.4
        /// The hunter tilts his head up at the sky as the sun starts to set.
        static let duskStarts: TimeInterval = 9.7
        static let remarkShows: TimeInterval = 12.9
        static let remarkHides: TimeInterval = 17.1
        static let done: TimeInterval = 17.5
    }

    /// How long the sky takes to shift to dusk.
    static let duskFadeDuration: TimeInterval = 3.0

    /// Stream scene timing (seconds from the start of the scene).
    enum StreamTiming {
        static let alert: TimeInterval = 1.2
        static let runs: TimeInterval = 2.0
        static let runDuration: TimeInterval = 1.4
        static let takeoff: TimeInterval = 3.6
    }

    static let poopRemark = "I guess I deserved that... there sure have been a lot of poop references today."
    /// Fork scene timing.
    enum ForkTiming {
        static let promptShows: TimeInterval = 0.6
        static let toGateDuration: TimeInterval = 1.8
        /// From the shot: the lock drops, the gate swings open, and he walks through as it fades.
        static let lockFall: TimeInterval = 0.3
        static let gateOpens: TimeInterval = 0.35
        static let walkInStarts: TimeInterval = 0.9
        static let walkInDuration: TimeInterval = 1.2
        static let fadeStarts: TimeInterval = 1.7
        static let fadeDuration: TimeInterval = 1.0
        static let throughGate: TimeInterval = 2.9
        /// How fast the lock flashes while waiting to be shot.
        static let lockFlashPeriod: TimeInterval = 1.2
    }

    /// Campsite timing.
    enum CampTiming {
        static let arrowShows: TimeInterval = 3.0
    }

    /// Abduction timing (seconds from the start of the scene).
    enum AbductionTiming {
        static let walkToCenter: TimeInterval = 2.2
        static let ufoArrives: TimeInterval = 2.6
        static let ufoArriveDuration: TimeInterval = 2.0
        /// The wide-eyed look, from when he spots the UFO.
        static let shocked: TimeInterval = 3.4
        static let beamStarts: TimeInterval = 4.8
        static let liftStarts: TimeInterval = 5.6
        static let liftDuration: TimeInterval = 1.9
        static let beamEnds: TimeInterval = 7.6
        /// With the hunter aboard, the UFO flies off to the left; then fade to black.
        static let ufoLeaves: TimeInterval = 7.9
        static let ufoLeaveDuration: TimeInterval = 1.4
        static let fadeStarts: TimeInterval = 9.0
        static let fadeDuration: TimeInterval = 1.0
        static let done: TimeInterval = 10.2
    }

    /// Alien console timing.
    enum ConsoleTiming {
        static let boot: TimeInterval = 2.2
        /// How long each step of the sequence lights up, and the gap after it.
        static let stepOn: TimeInterval = 0.5
        static let stepGap: TimeInterval = 0.2
        static let tapFlash: TimeInterval = 0.3
        static let feedback: TimeInterval = 1.2
        static let lockdown: TimeInterval = 3.0
        static let granted: TimeInterval = 2.4
        /// The fade to black at the end of a lockdown or an access grant.
        static let fade: TimeInterval = 1.0
        static let fadeIn: TimeInterval = 0.8
    }

    /// Aboard the UFO.
    enum AboardTiming {
        static let fadeIn: TimeInterval = 1.0
        static let remarkShows: TimeInterval = 1.4
        static let remarkHides: TimeInterval = 4.6
        static let bathroomShows: TimeInterval = 4.9
        static let bathroomHides: TimeInterval = 8.4
        /// His stomach gurgles: he clutches it, wide-eyed.
        static let gurgle: TimeInterval = 8.6
        static let gurgleEnds: TimeInterval = 10.4
        /// Then he walks off to the right, into the next room.
        static let walkOffStarts: TimeInterval = 10.8
        static let walkOffDuration: TimeInterval = 2.2
        static let done: TimeInterval = 13.0
    }

    /// The aliens' lab (seconds from the start of the scene).
    enum AlienTiming {
        static let walkInDuration: TimeInterval = 2.0
        /// The aliens notice him ("!") and turn around; he goes wide-eyed.
        static let bangShows: TimeInterval = 2.3
        static let turn: TimeInterval = 2.7
        static let bangHides: TimeInterval = 3.3
        static let shockedStarts: TimeInterval = 2.4
        static let shockedEnds: TimeInterval = 4.2
        static let approachStarts: TimeInterval = 3.4
        static let approachDuration: TimeInterval = 2.0
        /// Alien chatter, one alien after the other.
        static let firstChatterShows: TimeInterval = 5.6
        static let secondChatterShows: TimeInterval = 7.1
        static let chatterHides: TimeInterval = 8.6
        static let questionShows: TimeInterval = 8.9
        static let questionHides: TimeInterval = 10.0
        static let fart: TimeInterval = 10.1
        /// The little gas cloud behind him while the fart plays.
        static let gasDuration: TimeInterval = 1.5
        /// He glances behind him, then forward again.
        static let lookBackStarts: TimeInterval = 10.3
        static let lookBackEnds: TimeInterval = 11.1
        static let mannersShows: TimeInterval = 11.6
        static let mannersHides: TimeInterval = 14.4
        static let niceShows: TimeInterval = 14.7
        static let niceHides: TimeInterval = 16.4
        static let leaveStarts: TimeInterval = 16.7
        static let leaveDuration: TimeInterval = 2.4
        /// He walks up to the table and takes his shotgun back.
        static let toTableStarts: TimeInterval = 19.0
        static let toTableDuration: TimeInterval = 2.0
        static let pickup: TimeInterval = 21.2
        static let exitStarts: TimeInterval = 22.0
        static let exitDuration: TimeInterval = 2.2
        static let fadeStarts: TimeInterval = 23.4
        static let fadeDuration: TimeInterval = 1.0
        static let done: TimeInterval = 24.6
    }

    /// The specimen-vat lab (seconds from the start of each step).
    enum VatTiming {
        static let fadeIn: TimeInterval = 0.8
        static let walkInDuration: TimeInterval = 2.0
        /// On instinct, he shoots the dove's vat, then the mallard's.
        static let firstShot: TimeInterval = 2.6
        static let secondShot: TimeInterval = 3.4
        static let liquidFall: TimeInterval = 0.45
        static let birdFall: TimeInterval = 0.4
        /// A scientist runs in with his clipboard.
        static let scientistArrives: TimeInterval = 4.6
        static let scientistArriveDuration: TimeInterval = 1.0
        /// The birds rise as skeletons and turn on him.
        static let transform: TimeInterval = 6.0
        static let shockedStarts: TimeInterval = 6.0
        static let shockedEnds: TimeInterval = 8.4
        /// He drops the clipboard and screams.
        static let drop: TimeInterval = 6.6
        static let clipboardFall: TimeInterval = 0.35
        static let screamShows: TimeInterval = 6.6
        static let screamHides: TimeInterval = 8.0
        static let reachStarts: TimeInterval = 7.0
        static let scientistFlees: TimeInterval = 8.0
        static let scientistFleeDuration: TimeInterval = 1.2
        static let chaseStarts: TimeInterval = 8.4
        static let chaseDuration: TimeInterval = 2.4
        static let waiting: TimeInterval = 11.0
        /// After the pickup: the bubble, then he walks off to the right and it fades.
        static let collectedShows: TimeInterval = 2.0
        static let leaveDuration: TimeInterval = 2.2
        static let fadeDuration: TimeInterval = 1.0
    }

    /// The wrecked lab (seconds from the start of the scene).
    enum WreckedTiming {
        static let walkToCenter: TimeInterval = 2.2
        /// He looks left, then right...
        static let lookLeftStarts: TimeInterval = 2.5
        static let lookRightStarts: TimeInterval = 3.1
        static let lookEnds: TimeInterval = 3.7
        /// ...and scratches his head.
        static let scratchStarts: TimeInterval = 3.9
        static let scratchEnds: TimeInterval = 5.6
        static let walkOffStarts: TimeInterval = 5.8
        static let walkOffDuration: TimeInterval = 2.2
        static let done: TimeInterval = 8.0
    }

    /// The pristine lab (seconds from the start of the scene).
    enum PristineTiming {
        static let walkInDuration: TimeInterval = 2.0
        static let shockedStarts: TimeInterval = 2.0
        static let shockedEnds: TimeInterval = 3.2
        /// The skeletons look over at him.
        static let skeletonsLook: TimeInterval = 2.3
        /// The scientist in the vat says something alien.
        static let chatterShows: TimeInterval = 3.2
        static let chatterHides: TimeInterval = 5.2
        /// He puts his shotgun away and carries the clipboard to the table, whistling.
        static let clipboardOut: TimeInterval = 5.6
        static let toTableStarts: TimeInterval = 5.8
        static let toTableDuration: TimeInterval = 1.8
        static let place: TimeInterval = 7.8
        static let armedAgain: TimeInterval = 8.4
        static let walkOffStarts: TimeInterval = 8.6
        static let walkOffDuration: TimeInterval = 2.2
        static let fadeStarts: TimeInterval = 10.0
        static let fadeDuration: TimeInterval = 1.0
        static let done: TimeInterval = 11.2
    }

    static let scientistScream = "EEEEEEEK!"
    static let vatAlienChatter = "<#: /#> (:#"

    static let aboardRemark = "Whoa... where am I? This sure isn't the campgrounds."
    static let bathroomRemark = "I hope they have a bathroom on this thing, that pickle sandwich is fighting back.."
    /// What the aliens say: alien-looking symbols in the pixel font, then plain English.
    static let alienChatter = ["#<:/ >#( :/#<", "/#> <:#/ (#: >#"]
    static let alienManners = "Seriously man, manners?"
    static let alienNice = "Nice."

    static let smokeyRemark = "Wow, Smokey Bear put on some weight.."
    static let forkPrompt = "Which way should I go?"
    static let bearRemark = "It's getting dark. Probably time to head back to camp soon."

    /// The leash scene's conversation, one bubble per tap.
    static let reunionLines: [(speaker: Speaker, text: String)] = [
        (.fisherman, "Oh great, it's YOU. You scared off every fish in that pond, and Max ran two miles before I caught him. TWO. MILES. I just wanted some peace and quiet!"),
        (.hunter, "Relax, I found your tackle box! ...I did eat the other half of your pickle sandwich, though."),
        (.fisherman, "You're a real piece of work. That sandwich fell on the floor, by the way. You'll probably be pooping your pants soon."),
    ]

    static let fishermanGreeting = "Ahh, finally some peace and quiet."
    static let fishermanYell = "I'm fishing here man, are you crazy! MAX, come back buddy!"

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
    /// Birds bagged on this run.
    private(set) var bagged = 0
    /// This run's score (mallards are worth double).
    private(set) var score = 0
    /// Mallards that have taken their first shot, per scene, with when it happened.
    private(set) var wounded: [Int: [Int: Date]] = [:]

    /// How long a wounded mallard's hit animation plays.
    static let woundDuration: TimeInterval = 0.45
    /// The hunter has been inside the cabin (he now stands at its door, and a dove sits on the chimney).
    private(set) var cabinVisited = false
    private(set) var chimneyDoveDown = false
    /// Fading in from black after stepping back outside.
    private(set) var fadeInStart: Date?
    /// When the current scene's doves were sent flying in (pond and tackle box scenes).
    private(set) var dovesReleased: Date?
    /// The fisherman and Max have run off.
    private(set) var pondEventDone = false
    private var dovesFlying = false
    /// The tackle box scene has played out (the box is picked up and the fisherman is gone).
    private(set) var tackleEventDone = false
    /// The leash scene's conversation is over.
    private(set) var reunionDone = false
    private(set) var poopDone = false
    private(set) var bearDone = false
    /// When the sky started shifting to dusk (after the bear). It stays dusk for the rest of the run.
    private(set) var duskStart: Date?
    /// Asks the app to open the inventory showing this item (set right after the tackle box pickup).
    private(set) var inventoryRequest: InventoryItem?
    /// The route picked at the fork (its scenes follow the fork scene).
    private(set) var route: QuestRoute?
    /// It's night (after stepping through the restricted gate).
    private(set) var isNight = false
    /// The alien console mini game.
    private(set) var console = ConsoleState()
    /// The end screen fades in from an already-black screen (after the UFO interior).
    private(set) var finishesFromBlack = false
    /// The aliens took his shotgun when they abducted him; he gets it back from their lab.
    private(set) var hasShotgun = true
    /// The inventory was opened for a pickup, and the scene moves on once it's closed.
    private var continuesWhenInventoryCloses = false

    /// Every scene on this run's path: the main trail, then the chosen route's scenes.
    var sceneCount: Int { AdventureScenes.all.count + (route?.scenes.count ?? 0) }

    /// The scene at `index` on this run's path.
    func spec(_ index: Int) -> AdventureScene {
        index < AdventureScenes.all.count ? AdventureScenes.all[index] : (route?.scenes ?? [])[index - AdventureScenes.all.count]
    }
    /// Items picked up on this run.
    private(set) var inventory: [InventoryItem] = []

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
        // The eerie scenes keep animating for their wind.
        case .hunting, .cabinPrompt, .tackleBox(.waiting, _), .reunion(.talking(_), _): fadeInStart != nil || dovesFlying || spec(scene).isEerie
        default: true
        }
    }

    /// The chimney dove is waiting to be shot.
    var showsChimneyDove: Bool {
        cabinVisited && !chimneyDoveDown && spec(scene).cabin != nil
    }

    func isDown(scene: Int, dove: Int) -> Bool {
        downed[scene]?.contains(dove) ?? false
    }

    /// When a mallard took its first shot (nil if it hasn't been hit yet).
    func woundedAt(scene: Int, dove: Int) -> Date? {
        wounded[scene]?[dove]
    }

    /// Shoots a bird in the current scene at its current world position. Mallards need two hits.
    func shoot(dove index: Int, at position: CGPoint) {
        guard phase == .hunting, !isDown(scene: scene, dove: index) else { return }
        let bird = spec(scene).doves[index]
        if bird.kind.shotsToDown > 1, wounded[scene]?[index] == nil {
            // First hit: the mallard flinches, sheds a few feathers, and quacks, but keeps flying.
            fire()
            wounded[scene, default: [:]][index] = Date()
            addPoof(at: position, scale: 0.55)
            after(0.05) { game in game.sounds.quack() }
            return
        }
        downed[scene, default: []].insert(index)
        bag(at: position, kind: bird.kind)

        let current = spec(scene)
        if downed[scene]?.count == current.doves.count {
            if current.hasPondEvent {
                after(PondTiming.pauseAfterLastDove) { $0.startPondReaction() }
            } else {
                after(Self.pauseBeforeWalking) { $0.startWalking() }
            }
        }
    }

    /// Shoots the dove perched on the cabin chimney, which sends the hunter onward.
    func shootChimneyDove(at position: CGPoint) {
        guard phase == .hunting, showsChimneyDove else { return }
        chimneyDoveDown = true
        bag(at: position, kind: .dove)
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
        playFootsteps(for: Self.enterWalkDuration, on: spec(scene).surface)
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

    /// Tap the dropped tackle box: it goes into the inventory, then the hunter walks on.
    func collectTackleBox() {
        guard case .tackleBox(.waiting, _) = phase else { return }
        inventory.append(.tackleBox)
        phase = .tackleBox(.collected, start: Date())
        after(TackleTiming.collectedDone) { game in
            game.tackleEventDone = true
            game.phase = .hunting
            game.releaseDoves()
            game.inventoryRequest = .tackleBox
        }
    }

    /// The app opened the inventory for `inventoryRequest`.
    func inventoryRequestHandled() {
        inventoryRequest = nil
    }

    /// Tap during the leash scene's conversation: the next line, or (after the last) hand back
    /// the tackle box and walk on.
    func advanceReunion() {
        guard case .reunion(.talking(let line), _) = phase else { return }
        if line + 1 < Self.reunionLines.count {
            phase = .reunion(.talking(line: line + 1), start: Date())
        } else {
            // The tackle box goes back to its owner.
            inventory.removeAll { $0 == .tackleBox }
            phase = .reunion(.returned, start: Date())
            after(ReunionTiming.returnedDuration) { game in
                game.reunionDone = true
                game.phase = .hunting
                game.after(0.3) { $0.startWalking() }
            }
        }
    }

    /// Tap a sign at the fork. The campground route just walks on; the restricted route walks
    /// up to the locked gate.
    func choosePath(_ choice: QuestRoute) {
        guard case .fork(.choosing, _) = phase else { return }
        route = choice
        switch choice {
        case .campground:
            phase = .hunting
            startWalking()
        case .restricted:
            phase = .fork(.toGate, start: Date())
            playFootsteps(for: ForkTiming.toGateDuration, on: .grass)
            after(ForkTiming.toGateDuration) { $0.phase = .fork(.locked, start: Date()) }
        }
    }

    /// Shoot the flashing lock off the gate: it opens, and the hunter steps through.
    func shootLock(at position: CGPoint) {
        guard case .fork(.locked, _) = phase else { return }
        fire()
        addPoof(at: position, scale: 0.5)
        phase = .fork(.gateOpening, start: Date())
        playFootsteps(for: ForkTiming.walkInDuration, on: .grass, after: ForkTiming.walkInStarts)
        after(ForkTiming.throughGate) { game in
            // The sun has finally set.
            game.isNight = true
            game.arriveAtNextScene()
            let fadeStart = Date()
            game.fadeInStart = fadeStart
            game.after(Self.fadeInDuration + 0.1) { game in
                if game.fadeInStart == fadeStart { game.fadeInStart = nil }
            }
        }
    }

    /// Tap the proceed arrow at the campsite.
    func leaveCampsite() {
        guard case .campsite(let start) = phase, Date().timeIntervalSince(start) >= CampTiming.arrowShows else { return }
        phase = .hunting
        startWalking()
    }

    func restart() {
        generation += 1
        scene = 0
        phase = .hunting
        downed = [:]
        poofs = []
        isFiring = false
        bagged = 0
        score = 0
        wounded = [:]
        cabinVisited = false
        chimneyDoveDown = false
        fadeInStart = nil
        dovesReleased = nil
        pondEventDone = false
        dovesFlying = false
        tackleEventDone = false
        reunionDone = false
        poopDone = false
        bearDone = false
        duskStart = nil
        inventoryRequest = nil
        route = nil
        isNight = false
        console = ConsoleState()
        finishesFromBlack = false
        hasShotgun = true
        continuesWhenInventoryCloses = false
        inventory = []
    }

    #if DEBUG
    /// Jumps straight to a scene, for previews.
    static func preview(scene: Int, phase: Phase = .hunting, cabinVisited: Bool = false, pondDovesOut: Bool = false, inventory: [InventoryItem] = [], route: QuestRoute? = nil, console: ConsoleState? = nil) -> AdventureGame {
        let game = AdventureGame()
        game.route = route
        if let console { game.console = console }
        game.isNight = route == .restricted && scene > 12
        game.scene = scene
        game.phase = phase
        game.cabinVisited = cabinVisited || scene > 2
        if pondDovesOut { game.dovesReleased = Date().addingTimeInterval(-5) }
        game.tackleEventDone = scene > 7
        game.reunionDone = scene > 8
        game.poopDone = scene > 9
        game.bearDone = scene > 10
        if scene > 10 { game.duskStart = .distantPast }
        game.bagged = scene == 0 ? 0 : 3 + (scene > 1 ? 4 : 0)
        game.score = game.bagged * QuestStore.pointsPerDove
        game.inventory = inventory
        game.pondEventDone = scene > 4
        return game
    }
    #endif

    // MARK: Private

    private func bag(at position: CGPoint, kind: BirdKind) {
        fire()
        bagged += 1
        score += kind.points
        QuestStore.recordDove()
        after(0.06) { game in
            switch kind {
            case .dove: game.sounds.squawk()
            case .mallard: game.sounds.quackDown()
            }
        }
        addPoof(at: position)
    }

    private func addPoof(at position: CGPoint, scale: CGFloat = 1) {
        let poofID = nextPoofID
        nextPoofID += 1
        poofs.append(AdventurePoof(id: poofID, position: position, date: Date(), scale: scale))
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
        guard phase == .hunting, scene + 1 < sceneCount else { return }
        let fromCabinDoor = cabinVisited && spec(scene).cabin != nil
        phase = .walking(from: scene, start: Date(), fromCabinDoor: fromCabinDoor)
        playFootsteps(for: Self.walkDuration, on: spec(scene).surface)
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
        dovesReleased = nil
        let next = spec(scene)
        if next.isEerie { sounds.wind() }
        if next.cabin != nil, !cabinVisited {
            phase = .cabinPrompt
        } else if next.hasPondEvent, !pondEventDone {
            beginPondScene()
        } else if next.hasTackleBoxEvent, !tackleEventDone {
            beginTackleScene()
        } else if next.hasReunionEvent, !reunionDone {
            beginReunion()
        } else if next.hasPoopEvent, !poopDone {
            beginPoopScene()
        } else if next.hasBearEvent, !bearDone {
            beginBearScene()
        } else if next.hasStreamEvent {
            beginStreamScene()
        } else if next.hasForkEvent {
            phase = .fork(.choosing, start: Date())
        } else if next.hasCampsiteEvent {
            phase = .campsite(start: Date())
        } else if next.hasAbductionEvent {
            beginAbduction()
        } else {
            phase = .hunting
            if next.doves.isEmpty {
                if scene + 1 < sceneCount {
                    after(next.linger) { $0.startWalking() }
                } else {
                    after(1.0) { $0.finish() }
                }
            }
        }
    }

    // MARK: Pond scene

    private func beginPondScene() {
        phase = .pond(.greeting, start: Date())
        after(PondTiming.dovesRelease) { game in
            game.phase = .hunting
            game.releaseDoves()
        }
    }

    /// Sends the current scene's doves flying in from the right edge, one after another.
    private func releaseDoves() {
        dovesReleased = Date()
        dovesFlying = true
        let count = spec(scene).doves.count
        let flight = PondTiming.doveFlyIn + Double(max(count - 1, 0)) * PondTiming.doveFlyInStagger
        after(flight + 0.1) { $0.dovesFlying = false }
    }

    /// After the last pond dove: Max bolts, the fisherman yells and follows, the hunter says "Whoops".
    private func startPondReaction() {
        guard phase == .hunting else { return }
        phase = .pond(.dogStartled, start: Date())
        after(PondTiming.dogDone) { game in
            game.phase = .pond(.fishermanYells, start: Date())
            game.after(PondTiming.yellDone) { game in
                game.pondEventDone = true
                game.phase = .pond(.whoops, start: Date())
                game.after(PondTiming.whoopsDone) { game in
                    game.phase = .hunting
                    game.startWalking()
                }
            }
        }
    }

    // MARK: Tackle box scene

    private func beginTackleScene() {
        phase = .tackleBox(.fleeing, start: Date())
        after(TackleTiming.fleeDone) { $0.phase = .tackleBox(.waiting, start: Date()) }
    }

    // MARK: Leash scene

    private func beginReunion() {
        phase = .reunion(.approaching, start: Date())
        after(ReunionTiming.talkStarts) { $0.phase = .reunion(.talking(line: 0), start: Date()) }
    }

    // MARK: Poop, bear, and stream scenes

    private func beginPoopScene() {
        phase = .poop(start: Date())
        after(PoopTiming.done) { game in
            game.poopDone = true
            game.phase = .hunting
            game.startWalking()
        }
    }

    private func beginBearScene() {
        phase = .bear(start: Date())
        after(BearTiming.roarStarts) { $0.sounds.roar() }
        // Two warning shots over its head.
        after(BearTiming.firstShot) { $0.fire() }
        after(BearTiming.secondShot) { $0.fire() }
        after(BearTiming.duskStarts) { $0.duskStart = Date() }
        after(BearTiming.done) { game in
            game.bearDone = true
            game.phase = .hunting
            game.startWalking()
        }
    }

    private func beginStreamScene() {
        phase = .stream(start: Date())
        after(StreamTiming.takeoff) { game in
            game.phase = .hunting
            game.releaseDoves()
            game.sounds.quack()
        }
    }

    // MARK: Abduction

    private func beginAbduction() {
        phase = .abduction(start: Date())
        playFootsteps(for: AbductionTiming.walkToCenter, on: .grass)
        after(AbductionTiming.ufoArrives) { $0.sounds.ufoArrive() }
        after(AbductionTiming.beamStarts) { $0.sounds.ufoBeam() }
        after(AbductionTiming.ufoLeaves) { $0.sounds.ufoArrive() }
        // Beamed up and flown off: fade to black, then the alien console.
        after(AbductionTiming.done) { $0.startConsole() }
    }

    // MARK: Alien console

    /// Tap a cell on the console's grid while it's the player's turn.
    func tapConsoleCell(_ cell: Int) {
        guard phase == .console, console.stage == .input, console.entered < console.sequence.count else { return }
        let expected = console.entered
        console.lastTap = ConsoleState.Tap(cell: cell, color: console.colors[expected], date: Date())
        sounds.consoleBeep(row: cell / 4)
        if cell == console.sequence[expected] {
            console.entered += 1
            if console.entered == console.sequence.count {
                console.results.append(true)
                setConsoleStage(.correct)
                sounds.consoleCorrect()
                consoleAfter(ConsoleTiming.feedback) { game in
                    if game.console.correctCount >= ConsoleState.toWin { game.consoleGranted() } else { game.nextConsoleSequence() }
                }
            }
        } else {
            console.results.append(false)
            setConsoleStage(.wrong)
            sounds.consoleError()
            consoleAfter(ConsoleTiming.feedback) { game in
                if game.console.wrongCount >= ConsoleState.toLose { game.consoleLockdown() } else { game.nextConsoleSequence() }
            }
        }
    }

    private func startConsole() {
        phase = .console
        console = ConsoleState(token: console.token + 1)
        setConsoleStage(.booting)
        consoleAfter(ConsoleTiming.boot) { $0.nextConsoleSequence() }
    }

    /// A fresh random sequence, one step longer for each one already matched.
    private func nextConsoleSequence() {
        let length = 3 + console.correctCount
        var cells: [Int] = []
        while cells.count < length {
            let cell = Int.random(in: 0..<ConsoleState.cells)
            if cell != cells.last { cells.append(cell) }
        }
        console.sequence = cells
        console.colors = cells.map { _ in Int.random(in: 0..<ConsoleState.colorCount) }
        console.entered = 0
        console.lastTap = nil
        setConsoleStage(.showing)
        let step = ConsoleTiming.stepOn + ConsoleTiming.stepGap
        for (index, cell) in cells.enumerated() {
            consoleAfter(0.4 + Double(index) * step) { $0.sounds.consoleBeep(row: cell / 4) }
        }
        consoleAfter(0.4 + Double(length) * step) { $0.setConsoleStage(.input) }
    }

    private func consoleLockdown() {
        setConsoleStage(.lockdown)
        sounds.consoleAlarm()
        // After the fade to black, the console reboots and the player tries again.
        consoleAfter(ConsoleTiming.lockdown + ConsoleTiming.fade) { $0.startConsole() }
    }

    private func consoleGranted() {
        setConsoleStage(.granted)
        sounds.consoleGranted()
        consoleAfter(ConsoleTiming.granted + ConsoleTiming.fade) { $0.beginAboard() }
    }

    // MARK: Aboard the UFO

    private func beginAboard() {
        hasShotgun = false
        phase = .aboard(start: Date())
        after(AboardTiming.gurgle) { $0.sounds.gurgle() }
        playFootsteps(for: AboardTiming.walkOffDuration, on: .wood, after: AboardTiming.walkOffStarts)
        after(AboardTiming.done) { $0.beginAlienLab() }
    }

    private func beginAlienLab() {
        phase = .aliens(start: Date())
        playFootsteps(for: AlienTiming.walkInDuration, on: .wood)
        after(AlienTiming.firstChatterShows) { $0.sounds.alienGibberish() }
        after(AlienTiming.fart) { $0.sounds.squeakyFart() }
        playFootsteps(for: AlienTiming.toTableDuration, on: .wood, after: AlienTiming.toTableStarts)
        after(AlienTiming.pickup) { $0.hasShotgun = true }
        playFootsteps(for: AlienTiming.exitDuration, on: .wood, after: AlienTiming.exitStarts)
        after(AlienTiming.done) { $0.beginVatLab() }
    }

    // MARK: Specimen-vat lab

    private func beginVatLab() {
        phase = .vats(.scripted, start: Date())
        playFootsteps(for: VatTiming.walkInDuration, on: .wood)
        after(VatTiming.firstShot) { game in
            game.fire()
            game.sounds.glassShatter()
            game.sounds.consoleAlarm()
        }
        after(VatTiming.secondShot) { game in
            game.fire()
            game.sounds.glassShatter()
        }
        playFootsteps(for: VatTiming.scientistArriveDuration, on: .wood, after: VatTiming.scientistArrives)
        after(VatTiming.transform) { $0.sounds.boneRattle() }
        after(VatTiming.drop) { $0.sounds.alienScream() }
        after(VatTiming.chaseStarts) { $0.sounds.boneRattle() }
        after(VatTiming.waiting) { $0.phase = .vats(.waiting, start: Date()) }
    }

    /// Tap the dropped clipboard: into the inventory it goes, and the inventory opens on it.
    /// Closing the inventory sends the hunter on (`inventoryClosed()`).
    func collectClipboard() {
        guard case .vats(.waiting, _) = phase else { return }
        inventory.append(.clipboard)
        phase = .vats(.collected, start: Date())
        after(VatTiming.collectedShows) { game in
            game.continuesWhenInventoryCloses = true
            game.inventoryRequest = .clipboard
        }
    }

    /// The app closed the inventory.
    func inventoryClosed() {
        guard continuesWhenInventoryCloses, case .vats(.collected, _) = phase else { return }
        continuesWhenInventoryCloses = false
        phase = .vats(.leaving, start: Date())
        playFootsteps(for: VatTiming.leaveDuration, on: .wood)
        after(VatTiming.leaveDuration + 0.2) { $0.beginWreckedLab() }
    }

    // MARK: Wrecked and pristine labs

    private func beginWreckedLab() {
        phase = .wreckedLab(start: Date())
        playFootsteps(for: WreckedTiming.walkToCenter, on: .wood)
        playFootsteps(for: WreckedTiming.walkOffDuration, on: .wood, after: WreckedTiming.walkOffStarts)
        after(WreckedTiming.done) { $0.beginPristineLab() }
    }

    private func beginPristineLab() {
        phase = .pristineLab(start: Date())
        playFootsteps(for: PristineTiming.walkInDuration, on: .wood)
        after(PristineTiming.chatterShows) { $0.sounds.alienGibberish() }
        after(PristineTiming.toTableStarts) { $0.sounds.whistle() }
        playFootsteps(for: PristineTiming.toTableDuration, on: .wood, after: PristineTiming.toTableStarts)
        // He leaves the clipboard on the table.
        after(PristineTiming.place) { game in game.inventory.removeAll { $0 == .clipboard } }
        playFootsteps(for: PristineTiming.walkOffDuration, on: .wood, after: PristineTiming.walkOffStarts)
        after(PristineTiming.done) { game in
            game.finishesFromBlack = true
            game.phase = .hunting
            game.finish()
        }
    }

    private func setConsoleStage(_ stage: ConsoleState.Stage) {
        console.stage = stage
        console.stageStart = Date()
        console.token += 1
    }

    /// Like `after`, but skipped if the console has moved on to another stage since.
    private func consoleAfter(_ delay: TimeInterval, _ action: @escaping (AdventureGame) -> Void) {
        let token = console.token
        after(delay) { game in
            guard game.phase == .console, game.console.token == token else { return }
            action(game)
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
