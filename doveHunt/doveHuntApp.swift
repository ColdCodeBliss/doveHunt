//
//  doveHuntApp.swift
//  doveHunt
//
//  Created by Ryan Bliss on 11/16/26.
//

import SwiftUI

@main
struct doveHuntApp: App {
    @State private var records = HuntRecords()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(records)
        }
    }
}
