//
//  AppIntent.swift
//  DoveHuntWidget
//
//  Created by Ryan Bliss on 11/16/26.
//

import WidgetKit
import AppIntents

/// The scenery shown on the console's screen.
enum Landscape: String, AppEnum {
    case meadow
    case nightWoods
    case sunsetMarsh

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Landscape" }

    static var caseDisplayRepresentations: [Landscape: DisplayRepresentation] {
        [
            .meadow: "Sunny Meadow",
            .nightWoods: "Night Woods",
            .sunsetMarsh: "Sunset Marsh"
        ]
    }
}

/// How fast the doves fly.
enum Difficulty: String, AppEnum {
    case easy
    case normal
    case hard

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Difficulty" }

    static var caseDisplayRepresentations: [Difficulty: DisplayRepresentation] {
        [
            .easy: "Easy",
            .normal: "Normal",
            .hard: "Hard"
        ]
    }

    var speedMultiplier: Double {
        switch self {
        case .easy: 0.6
        case .normal: 1
        case .hard: 1.5
        }
    }
}

/// The color of the handheld console shell around the screen.
enum ConsoleColor: String, AppEnum {
    case classicBlue
    case cherryRed
    case limeGreen
    case grapePurple
    case sunnyYellow
    case bubblegumPink
    case tangerine
    case tealWave
    case charcoal
    case arcticWhite
    case nes

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Console Color" }

    static var caseDisplayRepresentations: [ConsoleColor: DisplayRepresentation] {
        [
            .classicBlue: "Classic Blue",
            .cherryRed: "Cherry Red",
            .limeGreen: "Lime Green",
            .grapePurple: "Grape Purple",
            .sunnyYellow: "Sunny Yellow",
            .bubblegumPink: "Bubblegum Pink",
            .tangerine: "Tangerine",
            .tealWave: "Teal Wave",
            .charcoal: "Charcoal",
            .arcticWhite: "Arctic White",
            .nes: "NES"
        ]
    }
}

/// Lets people pick a landscape, difficulty, and console color when editing the widget
/// (touch and hold the widget, then Edit Widget).
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Dove Hunt Settings" }
    static var description: IntentDescription { "Choose the landscape, difficulty, and console color for your hunt." }

    @Parameter(title: "Landscape", default: .meadow)
    var landscape: Landscape

    @Parameter(title: "Difficulty", default: .normal)
    var difficulty: Difficulty

    @Parameter(title: "Console Color", default: .classicBlue)
    var consoleColor: ConsoleColor
}
