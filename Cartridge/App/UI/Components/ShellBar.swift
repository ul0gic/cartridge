import SwiftUI

struct ShellBarState: Equatable {
    let active: ShellSection
    let focused: ShellSection?
    let consoleName: String?
}

struct ShellBar: View {
    let state: ShellBarState
    let controller: ControllerInfo?
    let safeTop: CGFloat

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: Space.n5) {
            HStack(spacing: Space.n6) {
                HStack(spacing: Space.n2) {
                    AppIconImage(size: Layout.wordmarkIconSmall)
                    Text("Cartridge")
                        .typeStyle(.topbarWordmark)
                        .foregroundStyle(Palette.textPrimary)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: Space.half) {
                    ForEach([ShellSection.home, .favorites, .consoles, .gallery, .search], id: \.self) { section in
                        item(section)
                    }
                }
                .padding(Space.n1)
                .glassSurface(in: Capsule())
                Spacer(minLength: Space.n4)
                item(.settings)
                    .padding(Space.n1)
                    .glassSurface(in: Capsule())
                StatusChip(controller: controller)
            }
        }
        .frame(height: Layout.topbarHeight)
        .padding(.horizontal, Layout.marginX)
        .padding(.top, safeTop + Space.n2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : Motion.easeOut(Motion.focus), value: state)
    }

    private func item(_ section: ShellSection) -> some View {
        let isActive = state.active == section
        let isFocused = state.focused == section
        return HStack(spacing: Space.n2) {
            if section == .settings {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: Layout.shellGlyph, weight: .semibold))
            } else {
                Text(section.title)
                if section == .consoles, let console = state.consoleName {
                    Image(systemName: "chevron.right")
                        .font(.system(size: Layout.shellChevron, weight: .bold))
                        .opacity(0.6)
                    Text(console)
                }
            }
        }
        .typeStyle(.rail)
        .fontWeight(isActive || isFocused ? .bold : .medium)
        .foregroundStyle(isFocused ? Palette.actionText : isActive ? Palette.textPrimary : Palette.textSecondary)
        .padding(.horizontal, section == .settings ? Space.n3 : Space.n4)
        .frame(height: Layout.shellItemHeight)
        .background {
            if isFocused {
                Capsule()
                    .fill(Palette.actionFill)
                    .shadow(color: Palette.actionFill.opacity(0.35), radius: 18)
                    .matchedGeometryEffect(id: "focus", in: pill)
            } else if isActive {
                Capsule()
                    .fill(Palette.textPrimary.opacity(0.14))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(section == .settings ? "Settings" : section.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}
