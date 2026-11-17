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

/// Lets people pick a landscape when editing the widget.
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Dove Hunt Settings" }
    static var description: IntentDescription { "Choose the landscape for your hunt." }

    @Parameter(title: "Landscape", default: .meadow)
    var landscape: Landscape
}
