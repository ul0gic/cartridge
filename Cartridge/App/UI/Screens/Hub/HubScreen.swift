import SwiftUI

struct HubScreen: View {
    let model: AppModel
    let hub: HubModel

    @State private var art = TileArt.loading
    @State private var isShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chrome = model.chrome
        ZStack {
            HubStyle.scrimPicture
            TopBar(controller: chrome.controller, showsWordmark: false, safeTop: chrome.safeTop)
            HubColumn(
                game: hub.session.game,
                title: hub.title,
                subtitle: hub.subtitle,
                art: art,
                hints: hub.hints,
                glyphs: chrome.glyphs,
                showsRewind: hub.showsRewindHint,
                counter: hub.counter
            ) {
                bodyContent(glyphs: chrome.glyphs)
                    .id(hub.title)
                    .transition(transition)
            }
            .animation(Motion.easeOut(Motion.sheet), value: hub.title)
            .offset(x: isShown || reduceMotion ? 0 : -Layout.sheetRise)
            .opacity(isShown ? 1 : 0)
            .padding(.leading, Layout.sheetInsetX)
            .padding(.bottom, Layout.sheetBottom)
            .padding(.top, chrome.safeTop + Space.n5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            HubMessageStack(messages: hub.messageStack)
                .padding(.trailing, Layout.sheetInsetX)
                .padding(.bottom, Layout.sheetBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .task {
            art = await model.tileArt(for: hub.session.game)
        }
        .onAppear {
            withAnimation(Motion.easeOut(Motion.sheet)) { isShown = true }
            model.hubDidAppear()
        }
        .onChange(of: hub.messageStack) {
            if let message = hub.messageStack.last {
                AccessibilityNotification
                    .Announcement([message.head, message.detail].compactMap(\.self).joined(separator: ". ")).post()
            }
        }
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .offset(x: Layout.sheetRise).combined(with: .opacity), removal: .identity)
    }

    @ViewBuilder
    private func bodyContent(glyphs: HintGlyphs?) -> some View {
        let confirm = glyphs?.confirm
        switch hub.page {
        case .states(let page): SaveStatesView(page: page, confirmGlyph: confirm)
        case .cheats(let page): CheatsView(page: page, confirmGlyph: confirm)
        case .file(let page): SaveFileView(page: page, isRestarting: hub.isRestarting, confirmGlyph: confirm)
        case .display(let page): DisplayView(page: page)
        case .disc(let page): DiscView(page: page)
        case nil: HubCardsView(hub: hub, confirmGlyph: confirm)
        }
    }
}

struct HubCardsView: View {
    let hub: HubModel
    let confirmGlyph: String?

    var body: some View {
        let cards = Dictionary(uniqueKeysWithValues: hub.cards.map { ($0.id, $0) })
        VStack(spacing: Space.n3) {
            ForEach(hub.rows, id: \.self) { row in
                HStack(spacing: Space.n3) {
                    ForEach(row, id: \.self) { id in
                        if let card = cards[id] {
                            HubCardView(card: card, isHighlighted: hub.highlighted == id, confirmGlyph: confirmGlyph)
                        }
                    }
                }
            }
        }
    }
}
