import SwiftUI

struct PlayScreen: View {
    let model: AppModel

    var body: some View {
        ZStack {
            Palette.playBackground
            if let session = model.session {
                session.frameView
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(session.game.title), \(isPaused ? "paused" : "running")")
            }
            if model.hub?.isRestarting == true {
                Palette.playBackground
            }
            if let chips = model.playChips, !isPaused {
                PlayChipsView(model: chips, safeTop: model.chrome.safeTop)
            }
            if let hub = model.hub {
                HubScreen(model: model, hub: hub)
            }
            if let menu = model.captureMenu {
                CaptureMenuView(model: model, menu: menu)
            }
        }
        .ignoresSafeArea()
    }

    private var isPaused: Bool {
        model.hub != nil || model.captureMenu != nil
    }
}
