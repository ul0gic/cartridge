import SwiftUI

struct ChromeState: Equatable {
    let controller: ControllerInfo?
    let glyphs: HintGlyphs?
    let safeTop: CGFloat
}

struct ScreenScaffold<Backdrop: View, Content: View>: View {
    let chrome: ChromeState
    let showsWordmark: Bool
    let hints: [Hint]
    var counter: String?
    var bar: ShellBarState?
    var console: GameSystem?
    var chromeOpacity = 1.0
    @ViewBuilder let backdrop: Backdrop
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Palette.background
            backdrop
            content
            if let bar {
                ShellBar(state: bar, controller: chrome.controller, safeTop: chrome.safeTop)
            } else {
                TopBar(controller: chrome.controller, showsWordmark: showsWordmark, safeTop: chrome.safeTop)
                    .opacity(chromeOpacity)
            }
            HintBar(hints: hints, glyphs: chrome.glyphs, counter: counter)
                .opacity(chromeOpacity)
        }
        .environment(\.consoleSystem, console)
        .environment(\.colorScheme, console == nil ? colorScheme : .dark)
        .ignoresSafeArea()
    }
}
