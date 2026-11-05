import SwiftUI

struct StatusChip: View {
    let controller: ControllerInfo?

    var body: some View {
        HStack(spacing: Space.n2) {
            if controller == nil {
                NoControllerGlyph()
            } else {
                GlyphLabel(symbol: "gamecontroller.fill", size: Layout.glyphStatus)
            }
            Text(summary)
                .typeStyle(.meta)
                .foregroundStyle(Palette.textSecondary)
        }
        .foregroundStyle(Palette.textPrimary)
        .padding(.horizontal, Space.n4)
        .frame(height: Layout.chipHeight)
        .plate(radius: Radius.pill)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var summary: AttributedString {
        guard let controller else {
            var text = AttributedString("No controller")
            text.font = TypeStyle.meta.font.weight(.semibold)
            text.foregroundColor = Palette.textPrimary
            return text + AttributedString(" · Keyboard works")
        }
        var name = AttributedString(controller.name)
        name.font = TypeStyle.meta.font.weight(.semibold)
        name.foregroundColor = Palette.textPrimary
        switch controller.transport {
        case .bluetooth: return name + AttributedString(" · Bluetooth")
        case .usb: return name + AttributedString(" · USB")
        case .unknown: return name
        }
    }

    private var spoken: String {
        guard let controller else { return "No controller. The keyboard works." }
        switch controller.transport {
        case .bluetooth: return "\(controller.name) connected over Bluetooth"
        case .usb: return "\(controller.name) connected with a USB cable"
        case .unknown: return "\(controller.name) connected"
        }
    }
}
