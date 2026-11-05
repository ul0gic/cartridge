import SwiftUI

struct ConsoleScreen: View {
    let model: AppModel
    let system: GameSystem

    var body: some View {
        let games = model.consoleGames(system)
        let index = min(model.shell.grid[system] ?? 0, max(0, games.count - 1))
        let focusedGame = games.indices.contains(index) ? games[index] : nil
        let isFocused = model.shell.barFocus == nil
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: model.shellHints([
                Hint(kind: .move, label: "Move"),
                Hint(kind: .confirm, label: "Open"),
                Hint(kind: .back, label: "Consoles"),
            ]),
            counter: games.isEmpty ? nil : "\(index + 1) of \(games.count)",
            bar: model.shellBar,
            console: system,
            backdrop: {
                ZStack {
                    GameBackdrop(model: model, game: focusedGame)
                    ConsoleFrame(
                        system: system,
                        showsArtwork: false,
                        intensity: Layout.consoleFrameDetailStrength
                    )
                }
            },
            content: {
                VStack(alignment: .leading, spacing: 0) {
                    if let focusedGame {
                        GameHero(model: model, game: focusedGame)
                            .frame(maxWidth: .infinity, alignment: .bottomLeading)
                            .frame(height: Layout.consoleHeroHeight, alignment: .bottomLeading)
                            .padding(.horizontal, Layout.marginX)
                    }
                    GameGrid(
                        model: model,
                        games: games,
                        focused: isFocused ? index : nil,
                        cellWidth: Layout.tileWidth(for: system.tileAspect)
                    ) { model.shell.gridColumns = $0 }
                        .padding(.horizontal, Layout.marginX)
                        .padding(.top, Space.n5)
                        .background {
                            ConsoleWell(system: system)
                                .padding(.horizontal, Layout.consoleFrameInset)
                        }
                }
                .padding(.top, model.contentTop)
                .padding(.bottom, Layout.hintbarHeight)
            }
        )
    }
}

struct ConsolesShelfScreen: View {
    let model: AppModel

    @State private var appeared = false
    @State private var position: Double
    @State private var shown: Int
    @State private var turn = 0
    @State private var ghost: Double?
    @State private var dissolve = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: AppModel) {
        self.model = model
        let index = min(model.shell.shelfIndex, max(0, model.consoleSummaries.count - 1))
        _position = State(initialValue: Double(index))
        _shown = State(initialValue: index)
    }

    var body: some View {
        let consoles = model.consoleSummaries
        let index = min(model.shell.shelfIndex, max(0, consoles.count - 1))
        let isFocused = model.shell.barFocus == nil
        let hero = consoles.indices.contains(shown) ? consoles[shown] : nil
        ScreenScaffold(
            chrome: model.chrome,
            showsWordmark: true,
            hints: model.shellHints([
                Hint(kind: .game, label: "Choose"),
                Hint(kind: .confirm, label: "Open"),
                Hint(kind: .back, label: "Home"),
            ]),
            bar: model.shellBar,
            console: consoles.indices.contains(index) ? consoles[index].system : nil,
            backdrop: {
                if consoles.indices.contains(index) {
                    ConsoleFrame(system: consoles[index].system, showsArtwork: false)
                }
            },
            content: {
                ZStack(alignment: .topLeading) {
                    if !consoles.isEmpty {
                        ConsoleHubRing(
                            position: position,
                            model: model,
                            consoles: consoles,
                            focused: isFocused ? index : nil,
                            hubSystem: hero?.system,
                            ghost: ghost,
                            dissolve: dissolve,
                            reduceMotion: reduceMotion
                        )
                    }
                    if let hero {
                        ConsoleHero(summary: hero)
                            .padding(.horizontal, Layout.marginX)
                            .padding(.top, model.contentTop + Space.n7)
                            .id(hero.system)
                            .transition(heroHandover)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(y: appeared || reduceMotion ? 0 : -Layout.shelfDrop)
                .opacity(appeared ? 1 : 0)
                .onAppear {
                    withAnimation(Motion.easeOut(Motion.shelf)) { appeared = true }
                }
            }
        )
        .onChange(of: index) { old, new in
            follow(from: old, to: new, count: consoles.count)
        }
    }

    private var heroHandover: AnyTransition {
        let slide = AnyTransition.offset(x: Space.n5 * CGFloat(turn))
        let arrival: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: slide)
        return .asymmetric(
            insertion: arrival.animation(Motion.easeOut(Motion.ambient - Motion.focus).delay(Motion.focus.seconds)),
            removal: .opacity.animation(Motion.easeIn(Motion.focus))
        )
    }

    private func follow(from old: Int, to new: Int, count: Int) {
        guard count > 0 else { return }
        let step = ConsoleHubRing.step(from: old, to: new, count: count)
        if reduceMotion {
            ghost = position
            position += Double(step)
            dissolve += 1
            withAnimation(.linear(duration: Motion.handover.seconds)) {
                turn = step
                shown = new
            }
        } else {
            withAnimation(Motion.ringTurn) {
                position += Double(step)
                turn = step
                shown = new
            }
        }
    }
}

private struct ConsoleHero: View {
    let summary: ConsoleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SystemBadge(name: "\(summary.system.maker) · \(String(summary.system.launchYear))")
                .padding(.bottom, Space.n4)
            Text(summary.system.fullName)
                .typeStyle(.titleL)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 6)
            HStack(spacing: Space.n5) {
                Text(LibraryRows.gameCount(summary.gameCount))
                if summary.inProgress > 0 {
                    Text("\(summary.inProgress) in progress")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.resumeMark)
                }
            }
            .typeStyle(.lede)
            .foregroundStyle(Palette.textSecondary)
            .padding(.top, Space.n4)
        }
        .frame(maxWidth: Layout.consoleHeroWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension GameSystem {
    var backdropImage: String {
        "Console-\(rawValue)"
    }

    var cutoutImage: String {
        "ConsoleCutout-\(rawValue)"
    }

    var fullName: String {
        switch self {
        case .nes: "Nintendo Entertainment System"
        case .snes: "Super Nintendo"
        case .genesis: "Sega Genesis"
        case .n64: "Nintendo 64"
        case .ps1: "PlayStation"
        case .xbox: "Xbox"
        }
    }

    var maker: String {
        switch self {
        case .nes, .snes, .n64: "Nintendo"
        case .genesis: "Sega"
        case .ps1: "Sony"
        case .xbox: "Microsoft"
        }
    }

    var launchYear: Int {
        switch self {
        case .nes: 1985
        case .snes: 1991
        case .genesis: 1989
        case .n64: 1996
        case .ps1: 1995
        case .xbox: 2001
        }
    }
}
