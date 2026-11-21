//
//  ContentView.swift
//  doveHunt
//
//  Created by Ryan Bliss on 11/16/26.
//

import SwiftUI

/// Items in the hamburger menu.
enum MenuDestination: String, Identifiable, CaseIterable {
    case topScores
    case howToPlay
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topScores: "TOP SCORES"
        case .howToPlay: "HOW TO PLAY"
        case .settings: "SETTINGS"
        case .about: "ABOUT"
        }
    }
}

struct ContentView: View {
    @Environment(HuntRecords.self) private var records
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isMenuOpen = false
    @State private var destination: MenuDestination?
    /// The side-scrolling adventure that starts right here on the home screen.
    @State private var game = AdventureGame()

    var body: some View {
        ZStack(alignment: .topLeading) {
            AdventureView(game: game)
                .ignoresSafeArea()

            if game.showsTitle {
                header
                    .frame(maxWidth: .infinity)
                    .padding(.top, 72)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            } else if !game.isFinished {
                // The Hunter's Quest HUD: this run's score and doves, separate from the widget's.
                PixelText("SCORE \(String(format: "%06d", min(game.score, 999_999)))  BAGGED \(game.bagged)", pixelSize: horizontalSizeClass == .regular ? 3 : 2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.pixelInk.opacity(0.55), ignoresSafeAreaEdges: [])
                    .frame(maxWidth: .infinity)
                    // Keep clear of the menu button on the left.
                    .padding(.leading, 72)
                    .padding(.trailing, 16)
                    .padding(.top, 18)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            menuButton
                .padding(.leading, 16)
                .padding(.top, 8)

            if isMenuOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { setMenu(open: false) }
                    .accessibilityLabel("Close menu")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)

                MenuDrawer(
                    onClose: { setMenu(open: false) },
                    onSelect: { selection in
                        setMenu(open: false)
                        destination = selection
                    }
                )
                .transition(.move(edge: .leading))
            }
        }
        .sheet(item: $destination) { destination in
            MenuScreen(destination: destination)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { records.refresh() }
        }
        .animation(.easeInOut(duration: 0.6), value: game.showsTitle)
        .onChange(of: game.phase) { _, phase in
            if case .finished = phase { records.refresh() }
        }
    }

    /// The Hunter's Quest title screen. Its score is the quest's own, separate from the widget game.
    private var header: some View {
        VStack(spacing: 14) {
            PixelText("DOVE HUNT", pixelSize: 6, scalesWithDynamicType: false)

            PixelText("THE HUNTER'S QUEST", pixelSize: 3, color: .pixelOrange)

            PixelText("BEST \(String(format: "%06d", min(records.questBestScore, 999_999)))", pixelSize: 3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.pixelInk.opacity(0.55), ignoresSafeAreaEdges: [])

            PixelText("SHOOT THE DOVES TO BEGIN!", pixelSize: 2)
        }
    }

    private var menuButton: some View {
        Button {
            setMenu(open: true)
        } label: {
            VStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.pixelCream)
                        .frame(width: 24, height: 4)
                }
            }
            .frame(width: 48, height: 48)
            .background(Color.pixelNavy, ignoresSafeAreaEdges: [])
            .overlay(Rectangle().strokeBorder(Color.pixelCream, lineWidth: 3))
            .background(Rectangle().fill(Color.pixelInk).offset(x: 3, y: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
    }

    private func setMenu(open: Bool) {
        withAnimation(.snappy(duration: 0.25)) {
            isMenuOpen = open
        }
    }
}

// MARK: - Menu drawer

struct MenuDrawer: View {
    let onClose: () -> Void
    let onSelect: (MenuDestination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PixelText("MENU", pixelSize: 4, color: .pixelOrange)
                Spacer()
                Button {
                    onClose()
                } label: {
                    PixelText("X", pixelSize: 3)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close menu")
            }

            ForEach(MenuDestination.allCases) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack {
                        PixelText(item.title, pixelSize: 3)
                        Spacer()
                        PixelText(">", pixelSize: 3)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(PixelButtonStyle())
            }

            Spacer()

            PixelText("V\(AppSettings.versionString)", pixelSize: 2, color: .pixelCream.opacity(0.6))
        }
        .padding(20)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.pixelNavy.ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.pixelCream)
                .frame(width: 4)
                .ignoresSafeArea()
        }
    }
}

#Preview {
    ContentView()
        .environment(HuntRecords())
}
