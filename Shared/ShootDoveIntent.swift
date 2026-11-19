//
//  ShootDoveIntent.swift
//  Shared (compiled into both the app and the widget extension, as Apple recommends for
//  interactive widget intents)
//

import AppIntents
import WidgetKit

/// Runs when a dove is tapped. WidgetKit reloads the widget's timeline after `perform()` returns.
struct ShootDoveIntent: AppIntent {
    static var title: LocalizedStringResource { "Shoot Dove" }
    static var isDiscoverable: Bool { false }
    /// Always runs in the background: a shot must never bring the app to the foreground.
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Dove ID")
    var doveID: String

    @Parameter(title: "Wave Size")
    var waveSize: Int

    /// The flight frame the tapped button was drawn in, so the shot lines up with what was on screen.
    @Parameter(title: "Frame")
    var tick: Int

    init() {}

    init(doveID: String, waveSize: Int, tick: Int) {
        self.doveID = doveID
        self.waveSize = waveSize
        self.tick = tick
    }

    func perform() async throws -> some IntentResult {
        GameStore.registerHit(doveID: doveID, waveSize: waveSize, tick: tick)
        return .result()
    }
}

/// Runs when the player taps anywhere that isn't a dove. The shotgun still fires (aimed toward
/// the tapped spot when known), and, just as important, the tap is absorbed so a near-miss
/// never opens the app.
struct MissShotIntent: AppIntent {
    static var title: LocalizedStringResource { "Fire Shotgun" }
    static var isDiscoverable: Bool { false }
    /// Always runs in the background: a miss must never bring the app to the foreground.
    static var supportedModes: IntentModes { .background }

    /// Where the player tapped, in art pixels on the screen (negative = unknown).
    @Parameter(title: "Target X")
    var targetX: Double

    @Parameter(title: "Target Y")
    var targetY: Double

    /// The flight frame the tapped button was drawn in (negative = unknown).
    @Parameter(title: "Frame")
    var tick: Int

    init() {
        targetX = -1
        targetY = -1
        tick = -1
    }

    init(target: CGPoint?, tick: Int) {
        targetX = target.map { Double($0.x) } ?? -1
        targetY = target.map { Double($0.y) } ?? -1
        self.tick = tick
    }

    func perform() async throws -> some IntentResult {
        let target = targetX >= 0 && targetY >= 0 ? CGPoint(x: targetX, y: targetY) : nil
        GameStore.registerMiss(target: target, tick: tick >= 0 ? tick : nil)
        return .result()
    }
}
