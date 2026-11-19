//
//  GameStore.swift
//  Shared (compiled into both the app and the widget extension)
//

import Foundation

/// A finished hunt, archived when the player starts a new one.
nonisolated struct HuntRecord: Codable, Hashable, Identifiable, Sendable {
    let score: Int
    let doves: Int
    let date: Date

    var id: Date { date }
}

/// Persists game state in the shared App Group so the widget and the app see the same data.
nonisolated enum GameStore {
    static let appGroupID = "group.com.ColdCodeBliss.doveHunt"
    static let pointsPerDove = 100
    static let maxTopScores = 10

    private enum Key {
        static let score = "score"
        static let huntDoves = "huntDoves"
        static let wave = "wave"
        static let huntStartWave = "huntStartWave"
        static let shotDoveIDs = "shotDoveIDs"
        static let lastHitDoveID = "lastHitDoveID"
        static let lastShotDate = "lastShotDate"
        static let lastMissTarget = "lastMissTarget"
        static let lastShotTick = "lastShotTick"
        static let lifetimeDoves = "lifetimeDoves"
        static let lifetimeWaves = "lifetimeWaves"
        static let topScores = "topScores"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    // MARK: Current hunt

    static var score: Int { defaults.integer(forKey: Key.score) }

    /// Doves bagged during the current hunt.
    static var huntDoves: Int { defaults.integer(forKey: Key.huntDoves) }

    /// Increments each time a wave of doves is cleared; seeds the next wave's layout.
    static var wave: Int { defaults.integer(forKey: Key.wave) }

    /// The wave the current hunt started on. Doves fly faster with each wave cleared since then.
    static var huntStartWave: Int { defaults.integer(forKey: Key.huntStartWave) }

    static var shotDoveIDs: Set<String> {
        Set(defaults.stringArray(forKey: Key.shotDoveIDs) ?? [])
    }

    /// The most recent trigger pull, used to flash and aim the shotgun (and poof the dove, if
    /// it was a hit). `hitDoveID` is nil for a miss; `missTarget` is where a miss was aimed,
    /// in art pixels, when known; `tick` is the widget's flight frame that was on screen.
    static var lastShot: (date: Date, hitDoveID: String?, missTarget: CGPoint?, tick: Int?)? {
        guard let date = defaults.object(forKey: Key.lastShotDate) as? Date else { return nil }
        let target = (defaults.array(forKey: Key.lastMissTarget) as? [Double])
            .flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
        let tick = defaults.object(forKey: Key.lastShotTick) as? Int
        return (date, defaults.string(forKey: Key.lastHitDoveID), target, tick)
    }

    // MARK: Lifetime stats

    static var lifetimeDoves: Int { defaults.integer(forKey: Key.lifetimeDoves) }
    static var lifetimeWaves: Int { defaults.integer(forKey: Key.lifetimeWaves) }

    /// Best archived hunts, highest score first.
    static var topScores: [HuntRecord] {
        guard let data = defaults.data(forKey: Key.topScores),
              let records = try? JSONDecoder().decode([HuntRecord].self, from: data) else { return [] }
        return records
    }

    // MARK: Mutations

    /// Records a hit, awards points, and advances to a new wave once every dove is down.
    static func registerHit(doveID: String, waveSize: Int, tick: Int? = nil) {
        var shot = shotDoveIDs
        guard !shot.contains(doveID) else { return }
        shot.insert(doveID)

        defaults.set(score + pointsPerDove, forKey: Key.score)
        defaults.set(huntDoves + 1, forKey: Key.huntDoves)
        defaults.set(lifetimeDoves + 1, forKey: Key.lifetimeDoves)
        defaults.set(doveID, forKey: Key.lastHitDoveID)
        defaults.removeObject(forKey: Key.lastMissTarget)
        setShotTick(tick)
        defaults.set(Date(), forKey: Key.lastShotDate)

        if shot.count >= waveSize {
            defaults.set(wave + 1, forKey: Key.wave)
            defaults.set(lifetimeWaves + 1, forKey: Key.lifetimeWaves)
            shot.removeAll()
        }
        defaults.set(Array(shot), forKey: Key.shotDoveIDs)
    }

    /// Records a shot that hit nothing, so the shotgun still fires (aimed at `target`, if known).
    static func registerMiss(target: CGPoint?, tick: Int? = nil) {
        defaults.removeObject(forKey: Key.lastHitDoveID)
        setShotTick(tick)
        if let target {
            defaults.set([Double(target.x), Double(target.y)], forKey: Key.lastMissTarget)
        } else {
            defaults.removeObject(forKey: Key.lastMissTarget)
        }
        defaults.set(Date(), forKey: Key.lastShotDate)
    }

    /// Archives the current hunt into the top scores (if it scored) and starts fresh with a new wave.
    static func startNewHunt() {
        if score > 0 {
            let record = HuntRecord(score: score, doves: huntDoves, date: Date())
            let ranked = (topScores + [record])
                .sorted { $0.score == $1.score ? $0.date < $1.date : $0.score > $1.score }
                .prefix(maxTopScores)
            saveTopScores(Array(ranked))
        }
        defaults.set(0, forKey: Key.score)
        defaults.set(0, forKey: Key.huntDoves)
        let freshWave = wave + 1
        defaults.set(freshWave, forKey: Key.wave)
        defaults.set(freshWave, forKey: Key.huntStartWave)
        defaults.removeObject(forKey: Key.shotDoveIDs)
        defaults.removeObject(forKey: Key.lastHitDoveID)
        defaults.removeObject(forKey: Key.lastShotDate)
        defaults.removeObject(forKey: Key.lastMissTarget)
        defaults.removeObject(forKey: Key.lastShotTick)
    }

    private static func setShotTick(_ tick: Int?) {
        if let tick {
            defaults.set(tick, forKey: Key.lastShotTick)
        } else {
            defaults.removeObject(forKey: Key.lastShotTick)
        }
    }

    static func clearTopScores() {
        defaults.removeObject(forKey: Key.topScores)
    }

    private static func saveTopScores(_ records: [HuntRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.topScores)
    }
}
