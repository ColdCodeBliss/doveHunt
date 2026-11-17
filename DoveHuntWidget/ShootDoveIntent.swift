//
//  ShootDoveIntent.swift
//  DoveHuntWidget
//

import AppIntents
import WidgetKit

/// Runs when a dove is tapped. WidgetKit reloads the widget's timeline after `perform()` returns.
struct ShootDoveIntent: AppIntent {
    static var title: LocalizedStringResource { "Shoot Dove" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Dove ID")
    var doveID: String

    @Parameter(title: "Wave Size")
    var waveSize: Int

    init() {}

    init(doveID: String, waveSize: Int) {
        self.doveID = doveID
        self.waveSize = waveSize
    }

    func perform() async throws -> some IntentResult {
        GameStore.registerHit(doveID: doveID, waveSize: waveSize)
        return .result()
    }
}
