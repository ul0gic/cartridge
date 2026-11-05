import SwiftUI

struct ShellScreen: View {
    let model: AppModel

    var body: some View {
        ZStack {
            switch model.shell.section {
            case .home, .settings:
                HomeScreen(model: model)
            case .favorites:
                HomeScreen(model: model, page: .favorites)
            case .consoles:
                if let system = model.shell.console {
                    ConsoleScreen(model: model, system: system)
                } else {
                    ConsolesShelfScreen(model: model)
                }
            case .gallery:
                GalleryScreen(model: model)
            case .search:
                SearchScreen(model: model)
            }
        }
        .task(id: LightKey(console: model.shell.console, controller: model.chrome.controller)) {
            let light = model.shell.console.map(Palette.consoleRGB) ?? Palette.brandRGB
            model.dependencies.controller.setLight(red: light.red, green: light.green, blue: light.blue)
        }
        .id(ShellPage(section: model.shell.section, console: model.shell.console))
        .transition(.opacity)
        .animation(Motion.easeInOut(Motion.handover), value: ShellPage(
            section: model.shell.section,
            console: model.shell.console
        ))
    }
}

private struct LightKey: Equatable {
    let console: GameSystem?
    let controller: ControllerInfo?
}

private struct ShellPage: Hashable {
    let section: ShellSection
    let console: GameSystem?
}

extension AppModel {
    var shellBar: ShellBarState {
        ShellBarState(
            active: route == .settings ? .settings : shell.section,
            focused: shell.barFocus,
            consoleName: shell.section == .consoles ? shell.console?.displayName : nil
        )
    }

    var contentTop: CGFloat {
        chrome.safeTop + Space.n2 + Layout.topbarHeight + Space.n4
    }

    func shellHints(_ content: [Hint]) -> [Hint] {
        if shell.barFocus != nil {
            return [
                Hint(kind: .game, label: "Move"),
                Hint(kind: .confirm, label: "Select"),
                Hint(kind: .back, label: "Back"),
            ]
        }
        return [Hint(kind: .sections, label: "Sections")] + content
    }
}

struct GameBackdrop: View {
    let model: AppModel
    let game: GameRecord?
    var style = BackdropStyle.hero

    @State private var colors = AmbientColors.brand
    @State private var source = BackdropSource.collage

    var body: some View {
        ZStack {
            CinematicBackdrop(source: source, style: style)
            AmbientBackdrop(colors: colors, layout: .cinematic, drawsBase: false, intensity: 0.3)
        }
        .task(id: game?.id) {
            guard let game else {
                source = .collage
                return
            }
            colors = await model.ambientColors(for: game)
            source = await model.backdrop(for: game)
        }
    }
}

struct GameHero: View {
    let model: AppModel
    let game: GameRecord

    var body: some View {
        Hero(
            system: game.system.displayName,
            title: game.title,
            metadata: model.metadata(for: game),
            state: model.resumeDate(for: game).map { .resume(DisplayDate.text($0)) } ?? .unplayed
        )
    }
}
