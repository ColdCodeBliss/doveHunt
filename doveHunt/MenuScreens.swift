//
//  MenuScreens.swift
//  doveHunt
//
//  The screens reachable from the hamburger menu.
//

import SwiftUI

/// App-only preferences and info.
enum AppSettings {
    static let animatedDovesKey = "animatedDoves"
    nonisolated static let soundEffectsKey = "soundEffects"

    static var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

/// Wraps each menu destination in a retro-styled sheet.
struct MenuScreen: View {
    let destination: MenuDestination
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(20)
            }
            .background(Color.pixelNavyLight.ignoresSafeArea())
            .navigationTitle(destination.title.capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    PixelText(destination.title, pixelSize: 3)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(.pixelCream)
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .topScores: TopScoresView()
        case .howToPlay: HowToPlayView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }
}

/// Body copy style used inside panels.
private extension View {
    func retroBody() -> some View {
        font(.system(.callout, design: .monospaced))
            .foregroundStyle(Color.pixelCream)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Top scores

struct TopScoresView: View {
    @Environment(HuntRecords.self) private var records

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The Hunter's Quest (companion app game) records.
            PixelText("THE HUNTER'S QUEST", pixelSize: 3, scalesWithDynamicType: false)
            VStack(alignment: .leading, spacing: 12) {
                PixelText("QUEST RECORDS", pixelSize: 3, color: .pixelOrange)
                statRow("BEST SCORE", value: String(format: "%06d", min(records.questBestScore, 999_999)))
                statRow("DOVES BAGGED", value: "\(records.questLifetimeDoves)")
                statRow("CABIN VISITS", value: "\(records.questsCompleted)")
            }
            .pixelPanel()

            // The Home Screen widget game records, kept separate from the quest.
            PixelText("WIDGET HUNT", pixelSize: 3, scalesWithDynamicType: false)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 12) {
                PixelText("CURRENT HUNT", pixelSize: 3, color: .pixelOrange)
                statRow("SCORE", value: String(format: "%06d", min(records.score, 999_999)))
                statRow("DOVES", value: "\(records.huntDoves)")
            }
            .pixelPanel()

            VStack(alignment: .leading, spacing: 12) {
                PixelText("LIFETIME", pixelSize: 3, color: .pixelOrange)
                statRow("DOVES BAGGED", value: "\(records.lifetimeDoves)")
                statRow("WAVES CLEARED", value: "\(records.lifetimeWaves)")
            }
            .pixelPanel()

            VStack(alignment: .leading, spacing: 14) {
                PixelText("TOP HUNTS", pixelSize: 3, color: .pixelOrange)

                if records.topScores.isEmpty {
                    Text("No finished hunts yet. Start a new hunt in Settings to bank your score here.")
                        .retroBody()
                } else {
                    ForEach(Array(records.topScores.enumerated()), id: \.element.id) { index, record in
                        HStack(alignment: .center, spacing: 12) {
                            PixelText("\(index + 1).", pixelSize: 3, color: index == 0 ? .pixelOrange : .pixelCream)
                                .frame(width: 44, alignment: .leading)
                            PixelText(String(format: "%06d", min(record.score, 999_999)), pixelSize: 3)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(record.doves) doves")
                                Text(record.date, format: .dateTime.month(.abbreviated).day().year())
                                    .foregroundStyle(Color.pixelCream.opacity(0.7))
                            }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.pixelCream)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .pixelPanel()
        }
        .onAppear { records.refresh() }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            PixelText(label, pixelSize: 2)
            Spacer()
            PixelText(value, pixelSize: 3)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - How to play

struct HowToPlayView: View {
    private let steps: [(title: String, body: String)] = [
        ("ADD THE WIDGET", "Touch and hold your Home Screen, tap Edit, then Add Widget. Search for Dove Hunt and pick small, medium, or large."),
        ("PICK A LANDSCAPE", "Touch and hold the widget, tap Edit Widget, and choose Sunny Meadow, Night Woods, or Sunset Marsh."),
        ("TAP TO SHOOT", "Tap a dove to fire. Every dove is worth \(GameStore.pointsPerDove) points. Clear the sky to bring in a new flock."),
        ("BANK YOUR HUNT", "When you're ready for a fresh start, go to Settings and tap Start New Hunt. Your score is saved to Top Scores."),
        ("THE HUNTER'S QUEST", "This app's own adventure starts right on the home screen. Shoot every dove and the hunter walks on to the next scene. Its score and records are separate from the widget's."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 10) {
                    PixelText("\(index + 1). \(step.title)", pixelSize: 3, color: .pixelOrange)
                    Text(step.body).retroBody()
                }
                .pixelPanel()
            }

            Text("Widgets can't play sound, so the hunt on your Home Screen is a quiet one.")
                .retroBody()
                .opacity(0.75)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(HuntRecords.self) private var records
    @AppStorage(AppSettings.animatedDovesKey) private var animatedDoves = true
    @AppStorage(AppSettings.soundEffectsKey) private var soundEffects = true
    @State private var confirmingNewHunt = false
    @State private var confirmingClearScores = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                PixelText("DISPLAY & SOUND", pixelSize: 3, color: .pixelOrange)
                Toggle("Animated doves", isOn: $animatedDoves)
                    .retroBody()
                    .tint(.pixelOrange)
                Toggle("Sound effects", isOn: $soundEffects)
                    .retroBody()
                    .tint(.pixelOrange)
                Text("Doves on the home screen bob and flap; Reduce Motion turns this off automatically. Sound effects play in The Hunter's Quest and follow your silent switch.")
                    .retroBody()
                    .font(.system(.caption, design: .monospaced))
                    .opacity(0.75)
            }
            .pixelPanel()

            VStack(alignment: .leading, spacing: 16) {
                PixelText("WIDGET HUNT", pixelSize: 3, color: .pixelOrange)

                Button {
                    confirmingNewHunt = true
                } label: {
                    PixelText("START NEW HUNT", pixelSize: 3)
                }
                .buttonStyle(PixelButtonStyle())
                .confirmationDialog("Start a new hunt?", isPresented: $confirmingNewHunt, titleVisibility: .visible) {
                    Button("Start New Hunt") { records.startNewHunt() }
                } message: {
                    Text(records.score > 0
                         ? "Your current score of \(records.score) will be saved to Top Scores, and your widget will reset to zero."
                         : "Your widget will start a fresh wave of doves.")
                }

                Button {
                    confirmingClearScores = true
                } label: {
                    PixelText("CLEAR TOP SCORES", pixelSize: 3)
                }
                .buttonStyle(PixelButtonStyle(fill: Color(red: 0.55, green: 0.16, blue: 0.14)))
                .disabled(records.topScores.isEmpty)
                .opacity(records.topScores.isEmpty ? 0.5 : 1)
                .confirmationDialog("Clear all top scores?", isPresented: $confirmingClearScores, titleVisibility: .visible) {
                    Button("Clear Top Scores", role: .destructive) { records.clearTopScores() }
                } message: {
                    Text("This can't be undone. Your current hunt and lifetime stats are kept.")
                }
            }
            .pixelPanel()

            VStack(alignment: .leading, spacing: 12) {
                PixelText("APP", pixelSize: 3, color: .pixelOrange)
                HStack {
                    Text("Version").retroBody()
                    Spacer()
                    Text(AppSettings.versionString).retroBody()
                }
            }
            .pixelPanel()
        }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 24) {
            AppSprite(name: "hunter", size: AppArt.hunter, scale: 4)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                PixelText("DOVE HUNT", pixelSize: 4, color: .pixelOrange)
                Text("A retro Home Screen hunting game inspired by the 8-bit classics, plus The Hunter's Quest, a side-scrolling adventure right here in the app. Every pixel and sound is generated from code, with nearest-neighbor scaling for that crisp console look.")
                    .retroBody()
                Text("No real doves were harmed. They just poof into feathers and fly home.")
                    .retroBody()
                    .opacity(0.75)
            }
            .pixelPanel()

            PixelText("V\(AppSettings.versionString)", pixelSize: 2, color: .pixelCream.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Top Scores") {
    MenuScreen(destination: .topScores)
        .environment(HuntRecords())
}

#Preview("Settings") {
    MenuScreen(destination: .settings)
        .environment(HuntRecords())
}
