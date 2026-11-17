//
//  HuntRecords.swift
//  doveHunt
//

import Observation
import WidgetKit

/// App-side view of the shared game state. The widget writes to `GameStore`
/// from its own process, so call `refresh()` whenever the app becomes active.
@Observable
final class HuntRecords {
    private(set) var score = 0
    private(set) var huntDoves = 0
    private(set) var lifetimeDoves = 0
    private(set) var lifetimeWaves = 0
    private(set) var topScores: [HuntRecord] = []

    init() {
        refresh()
    }

    func refresh() {
        score = GameStore.score
        huntDoves = GameStore.huntDoves
        lifetimeDoves = GameStore.lifetimeDoves
        lifetimeWaves = GameStore.lifetimeWaves
        topScores = GameStore.topScores
    }

    /// Archives the current hunt to the top scores and resets the widget for a fresh hunt.
    func startNewHunt() {
        GameStore.startNewHunt()
        WidgetCenter.shared.reloadAllTimelines()
        refresh()
    }

    func clearTopScores() {
        GameStore.clearTopScores()
        refresh()
    }
}
