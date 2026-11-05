@MainActor
extension HintGlyphs {
    static func resolve(from controller: any ControllerMonitoring) -> HintGlyphs? {
        guard controller.connected != nil else { return nil }
        return HintGlyphs(
            confirm: controller.glyphName(for: .confirm) ?? "xmark.circle",
            back: controller.glyphName(for: .back) ?? "circle.circle",
            options: controller.glyphName(for: .options) ?? "line.3.horizontal.circle",
            secondary: controller.glyphName(for: .secondary) ?? "triangle.circle",
            left: controller.glyphName(for: .move(.left)) ?? "dpad.left.filled",
            right: controller.glyphName(for: .move(.right)) ?? "dpad.right.filled",
            up: controller.glyphName(for: .move(.up)) ?? "dpad.up.filled",
            down: controller.glyphName(for: .move(.down)) ?? "dpad.down.filled",
            sectionLeft: controller.glyphName(for: .section(.left)) ?? "l1.button.roundedbottom.horizontal",
            sectionRight: controller.glyphName(for: .section(.right)) ?? "r1.button.roundedbottom.horizontal"
        )
    }
}
