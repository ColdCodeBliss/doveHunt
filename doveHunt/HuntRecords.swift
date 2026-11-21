//
//  HuntRecords.swift
//  doveHunt
//

import Observation
import WidgetKit

/// App-side view of both games' records: the widget game (shared `GameStore`, written by the
/// widget from its own process, so call `refresh()` whenever the app becomes active) and
/// The Hunter's Quest (`QuestStore`, app-only). The two are kept completely separate.
@Observable
final class HuntRecords {
    private(set) var score = 0
    private(set) var huntDoves = 0
    private(set) var lifetimeDoves = 0
    private(set) var lifetimeWaves = 0
    private(set) var topScores: [HuntRecord] = []

    // The Hunter's Quest.
    private(set) var questLifetimeDoves = 0
    private(set) var questsCompleted = 0
    private(set) var questBestScore = 0

    init() {
        refresh()
    }

    func refresh() {
        score = GameStore.score
        huntDoves = GameStore.huntDoves
        lifetimeDoves = GameStore.lifetimeDoves
        lifetimeWaves = GameStore.lifetimeWaves
        topScores = GameStore.topScores
        questLifetimeDoves = QuestStore.lifetimeDoves
        questsCompleted = QuestStore.completed
        questBestScore = QuestStore.bestScore
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
