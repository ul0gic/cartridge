import SwiftUI

struct TopBar: View {
    let controller: ControllerInfo?
    let showsWordmark: Bool
    let safeTop: CGFloat

    var body: some View {
        HStack {
            if showsWordmark {
                HStack(spacing: Space.n2) {
                    AppIconImage(size: Layout.wordmarkIconSmall)
                    Text("Cartridge")
                        .typeStyle(.topbarWordmark)
                        .foregroundStyle(Palette.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: Space.n6)
            StatusChip(controller: controller)
        }
        .frame(height: Layout.topbarHeight)
        .padding(.horizontal, Layout.marginX)
        .padding(.top, safeTop + Space.n2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
