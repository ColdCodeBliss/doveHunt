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
        static let shotDoveIDs = "shotDoveIDs"
        static let lastHitDoveID = "lastHitDoveID"
        static let lastHitDate = "lastHitDate"
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

    static var shotDoveIDs: Set<String> {
        Set(defaults.stringArray(forKey: Key.shotDoveIDs) ?? [])
    }

    /// The most recent hit, used to show the feather "poof" right after a shot.
    static var lastHit: (doveID: String, date: Date)? {
        guard let id = defaults.string(forKey: Key.lastHitDoveID),
              let date = defaults.object(forKey: Key.lastHitDate) as? Date else { return nil }
        return (id, date)
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
    static func registerHit(doveID: String, waveSize: Int) {
        var shot = shotDoveIDs
        guard !shot.contains(doveID) else { return }
        shot.insert(doveID)

        defaults.set(score + pointsPerDove, forKey: Key.score)
        defaults.set(huntDoves + 1, forKey: Key.huntDoves)
        defaults.set(lifetimeDoves + 1, forKey: Key.lifetimeDoves)
        defaults.set(doveID, forKey: Key.lastHitDoveID)
        defaults.set(Date(), forKey: Key.lastHitDate)

        if shot.count >= waveSize {
            defaults.set(wave + 1, forKey: Key.wave)
            defaults.set(lifetimeWaves + 1, forKey: Key.lifetimeWaves)
            shot.removeAll()
        }
        defaults.set(Array(shot), forKey: Key.shotDoveIDs)
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
        defaults.set(wave + 1, forKey: Key.wave)
        defaults.removeObject(forKey: Key.shotDoveIDs)
        defaults.removeObject(forKey: Key.lastHitDoveID)
        defaults.removeObject(forKey: Key.lastHitDate)
    }

    static func clearTopScores() {
        defaults.removeObject(forKey: Key.topScores)
    }

    private static func saveTopScores(_ records: [HuntRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.topScores)
    }
}
