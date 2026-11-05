import SwiftUI

struct CheatsView: View {
    let page: CheatsPage
    let confirmGlyph: String?

    var body: some View {
        if let pad = page.pad {
            CodePadView(page: page, pad: pad)
        } else {
            ColumnScroll(scrollTarget: scrollTarget) {
                list
            }
        }
    }

    private var scrollTarget: CheatTarget {
        if case .delete(let id) = page.target {
            return .myCode(id)
        }
        return page.target
    }

    private var list: some View {
        LazyVStack(spacing: Space.n2) {
            if !page.hasList {
                InfoRow(message: .info(
                    "No cheat list for this game",
                    "You can still type a code from a cheat book or site."
                ))
            }
            EnterCodeRow(page: page)
                .id(CheatTarget.enterCode)
            if !page.myCodes.isEmpty {
                if page.hasList {
                    CheatHeading(text: "My codes")
                }
                ForEach(page.myCodes) { code in
                    MyCodeRow(page: page, code: code)
                        .id(CheatTarget.myCode(code.id))
                }
            }
            if page.hasList, !page.entries.isEmpty {
                CheatHeading(text: "Cheat list")
                ForEach(page.entries) { entry in
                    CheatRow(page: page, entry: entry)
                        .id(CheatTarget.entry(entry.key))
                }
            }
        }
    }
}

private struct CheatHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .typeStyle(.meta)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.textSecondary)
            .padding(.leading, Space.n5)
            .padding(.top, Space.n4 - Space.n2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct EnterCodeRow: View {
    let page: CheatsPage

    var body: some View {
        HubRowFrame(state: page.target == .enterCode ? .highlighted : .resting) {
            HStack(spacing: Space.n4) {
                RowGlyph(symbol: "keyboard")
                HubRowText(label: "Enter Code", detail: .text(page.enterCodeDetail))
                Spacer(minLength: Space.n3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Enter Code, \(page.enterCodeDetail)")
        .accessibilityAddTraits(.isButton)
    }
}

private struct MyCodeRow: View {
    let page: CheatsPage
    let code: MyCode

    var body: some View {
        HStack(spacing: Space.n2) {
            HubRowFrame(state: page.target == .myCode(code.id) ? .highlighted : .resting) {
                HStack(spacing: Space.n4) {
                    VStack(alignment: .leading, spacing: Space.half) {
                        Text(code.code)
                            .typeStyle(.body)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                        Text("Added \(HubFormat.date(code.addedAt))")
                            .typeStyle(.meta)
                            .lineLimit(1)
                    }
                    .modifier(RowTextColor())
                    Spacer(minLength: Space.n3)
                    HubOnOff(isOn: code.isEnabled)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(code.code), \(code.isEnabled ? "on" : "off")")
            .accessibilityAddTraits(.isButton)
            HubSquareButton(
                glyph: "trash",
                isHighlighted: page.target == .delete(code.id),
                isArmed: page.arming.isArmed(code.id),
                label: "Delete \(code.code)"
            )
        }
    }
}

private struct RowTextColor: ViewModifier {
    @Environment(\.isHubRowInverted) private var isInverted

    func body(content: Content) -> some View {
        content.foregroundStyle(isInverted ? Palette.actionText : Palette.textPrimary)
    }
}

private struct CheatRow: View {
    let page: CheatsPage
    let entry: CheatEntry

    var body: some View {
        let isOn = page.isOn(entry)
        HubRowFrame(state: page.target == .entry(entry.key) ? .highlighted : .resting) {
            HStack(spacing: Space.n4) {
                VStack(alignment: .leading, spacing: Space.n1) {
                    Text(entry.description)
                        .typeStyle(.body)
                        .fontWeight(.semibold)
                        .lineLimit(HubStyle.cardSubtitleLines)
                        .multilineTextAlignment(.leading)
                        .modifier(RowTextColor())
                    HubPill(text: entry.device)
                }
                Spacer(minLength: Space.n3)
                HubOnOff(isOn: isOn)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.description), \(entry.device), \(isOn ? "on" : "off")")
        .accessibilityAddTraits(.isButton)
    }
}
