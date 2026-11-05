import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        ZStack {
            screen
                .id(model.route.screen)
                .transition(.opacity)
        }
        .animation(Motion.easeInOut(Motion.handover), value: model.route.screen)
        .background(Palette.background)
        .background(WindowConfigurator(model: model))
        .ignoresSafeArea()
        .onAppear { AppDelegate.lifecycleHandler = model }
        .task { await model.start() }
    }

    @ViewBuilder private var screen: some View {
        switch model.route {
        case .launch: IntroScreen(model: model)
        case .welcome: WelcomeScreen(model: model)
        case .denied: DeniedScreen(model: model)
        case .scanning, .library: LibraryScreen(model: model)
        case .gamePanel(let id): GamePanelScreen(model: model, id: id)
        case .settings: SettingsScreen(model: model)
        case .about: AboutScreen(model: model)
        case .controller(let tab): ControllerGuideScreen(model: model, tab: tab)
        case .play: PlayScreen(model: model)
        }
    }
}
