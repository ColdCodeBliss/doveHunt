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
    @State private var isMenuOpen = false
    @State private var destination: MenuDestination?

    var body: some View {
        ZStack(alignment: .topLeading) {
            HuntingScene()
                .ignoresSafeArea()

            header
                .frame(maxWidth: .infinity)
                .padding(.top, 72)

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
    }

    private var header: some View {
        VStack(spacing: 14) {
            PixelText("DOVE HUNT", pixelSize: 6, scalesWithDynamicType: false)

            PixelText("SCORE \(String(format: "%06d", min(records.score, 999_999)))", pixelSize: 3)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.pixelInk.opacity(0.55))

            if records.score == 0 {
                PixelText("ADD THE WIDGET TO HUNT!", pixelSize: 2)
            }
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
            .background(Color.pixelNavy)
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

// MARK: - Hunting scene

/// The pixel backdrop: blue sky, the hunter on the grass, and doves bobbing ahead of his aim.
struct HuntingScene: View {
    @AppStorage(AppSettings.animatedDovesKey) private var animatedDoves = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Resting positions (art pixels) of the doves floating ahead of the hunter.
    private let doves: [(x: CGFloat, y: CGFloat, phase: Double, facesRight: Bool)] = [
        (60, 120, 0.0, true),
        (76, 98, 1.7, true),
        (52, 80, 3.1, false),
    ]

    var body: some View {
        GeometryReader { proxy in
            let art = AppArt.background
            // One art pixel in points; the art fills the screen and the overflow is cropped.
            let scale = max(proxy.size.width / art.width, proxy.size.height / art.height)
            let origin = CGPoint(
                x: (proxy.size.width - art.width * scale) / 2,
                y: (proxy.size.height - art.height * scale) / 2
            )
            let point = { (x: CGFloat, y: CGFloat) in
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }
            let isAnimating = animatedDoves && !reduceMotion

            ZStack {
                AppSprite(name: "app_background", size: art, scale: scale)
                    .position(point(art.width / 2, art.height / 2))

                AppSprite(name: "hunter", size: AppArt.hunter, scale: scale)
                    .position(point(4 + AppArt.hunter.width / 2, AppArt.groundTop + 3 - AppArt.hunter.height / 2))

                TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: !isAnimating)) { context in
                    let time = isAnimating ? context.date.timeIntervalSinceReferenceDate : 0

                    ZStack {
                        ForEach(doves.indices, id: \.self) { index in
                            let dove = doves[index]
                            // Offsets snap to whole art pixels to keep the retro motion.
                            let dx = (sin(time * 0.7 + dove.phase) * 3).rounded()
                            let dy = (sin(time * 1.6 + dove.phase) * 2).rounded()
                            let wingsUp = Int(time * 4 + dove.phase).isMultiple(of: 2)

                            AppSprite(name: wingsUp ? "dove_wings_up" : "dove_wings_down", size: AppArt.dove, scale: scale)
                                .scaleEffect(x: dove.facesRight ? 1 : -1)
                                .position(point(dove.x + dx, dove.y + dy))
                        }
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("A hunter in an orange cap aims his shotgun at doves flying across a blue sky")
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
                Button(action: onClose) {
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
