import SwiftUI

enum DualSenseControl: CaseIterable {
    case dpad
    case leftStick
    case rightStick
    case cross
    case circle
    case square
    case triangle
    case l1
    case r1
    case l2
    case r2
    case create
    case options
    case touchpad

    fileprivate var leftTwin: DualSenseControl? {
        switch self {
        case .rightStick: .leftStick
        case .r1: .l1
        case .r2: .l2
        case .options: .create
        default: nil
        }
    }
}

enum DualSenseInk {
    static let shellLit = MediaInk.gray(0xFC, 0xFC, 0xFD)
    static let shell = MediaInk.gray(0xE9, 0xEB, 0xEF)
    static let shellShade = MediaInk.gray(0xC8, 0xCB, 0xD2)
    static let trigger = MediaInk.gray(0xDE, 0xE1, 0xE6)
    static let triggerShade = MediaInk.gray(0xB4, 0xB8, 0xC0)
    static let bodyLit = MediaInk.gray(0x3A, 0x3C, 0x43)
    static let body = MediaInk.gray(0x17, 0x18, 0x1C)
    static let cap = MediaInk.gray(0xF7, 0xF8, 0xFA)
    static let capShade = MediaInk.gray(0xD3, 0xD7, 0xDE)
    static let capEdge = MediaInk.gray(0x9C, 0xA1, 0xAB)
    static let symbol = MediaInk.gray(0x7D, 0x82, 0x8C)
    static let stick = MediaInk.gray(0x0F, 0x10, 0x13)
    static let stickLit = MediaInk.gray(0x44, 0x46, 0x4E)
    static let grille = MediaInk.gray(0x05, 0x05, 0x06)
    static let lightBar = MediaInk.gray(0x5A, 0x96, 0xFF)
}

struct DualSenseDrawing: View {
    let lit: Set<DualSenseControl>

    var body: some View {
        Canvas { context, size in
            let unit = size.width / DualSenseShape.board.width
            context.scaleBy(x: unit, y: size.height / DualSenseShape.board.height)
            let sketch = ConsoleSketch(context: context, ink: DualSenseInk.symbol)
            DualSenseShape.drawShoulders(sketch)
            DualSenseShape.drawShell(sketch)
            DualSenseShape.drawCenter(sketch)
            DualSenseShape.drawDpad(sketch)
            DualSenseShape.drawFaceButtons(sketch)
            DualSenseShape.drawStick(sketch, at: DualSenseShape.center(.leftStick))
            DualSenseShape.drawStick(sketch, at: DualSenseShape.center(.rightStick))
            for control in DualSenseControl.allCases where lit.contains(control) {
                ring(control, in: context, unit: unit)
            }
        }
        .accessibilityHidden(true)
    }

    private func ring(_ control: DualSenseControl, in context: GraphicsContext, unit: CGFloat) {
        let shape = DualSenseShape.outline(control)
        let gap = Layout.focusGapWidth / unit
        let outer = (Layout.focusGapWidth + Layout.focusRingWidth) / unit
        let inner = shape.union(shape.strokedPath(StrokeStyle(lineWidth: 2 * gap, lineJoin: .round)))
        let ring = shape.union(shape.strokedPath(StrokeStyle(lineWidth: 2 * outer, lineJoin: .round)))
        var glow = context
        glow.addFilter(.blur(radius: 8 / unit))
        glow.fill(ring.subtracting(inner), with: .color(Palette.focusRing.opacity(0.5)))
        context.fill(inner.subtracting(shape), with: .color(Palette.focusGap))
        context.fill(ring.subtracting(inner), with: .color(Palette.focusRing))
    }
}

enum DualSenseShape {
    static let board = CGSize(width: 400, height: 270)
    static let width = board.width
    static let dpad = CGPoint(x: 84, y: 96)
    static let face = CGPoint(x: 316, y: 96)
    static let faceSpread = 26.0
    static let faceRadius = 12.0
    static let leftStick = CGPoint(x: 146, y: 166)
    static let stickWell = 25.0
    static let stickCap = 18.0
    static let touchpad = CGRect(x: 136, y: 37, width: 128, height: 78)
    static let l1 = CGRect(x: 44, y: 25, width: 80, height: 14)
    static let l2 = CGRect(x: 52, y: 9, width: 66, height: 22)
    static let create = CGRect(x: 118, y: 43, width: 7, height: 15)
    static let psButton = CGPoint(x: 200, y: 152)

    static func center(_ control: DualSenseControl) -> CGPoint {
        let bounds = outline(control).boundingRect
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    static func reach(_ control: DualSenseControl) -> CGFloat {
        let bounds = outline(control).boundingRect
        return control == .touchpad ? bounds.height / 2 : bounds.width / 2
    }

    static func mirror(_ point: CGPoint) -> CGPoint {
        CGPoint(x: width - point.x, y: point.y)
    }

    static func mirror(_ path: Path) -> Path {
        path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0))
    }

    static func both(_ path: Path) -> Path {
        path.union(mirror(path))
    }

    static func circle(_ center: CGPoint, _ radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
    }

    static func outline(_ control: DualSenseControl) -> Path {
        if let twin = control.leftTwin {
            return mirror(outline(twin))
        }
        switch control {
        case .dpad: return dpadKeys.reduce(Path()) { $0.union($1) }
        case .leftStick: return circle(leftStick, stickWell)
        case .cross, .circle, .square, .triangle: return circle(faceCenter(control), faceRadius)
        case .l1: return Path(roundedRect: l1, cornerRadius: 6)
        case .l2: return trigger
        case .create: return Path(roundedRect: create, cornerRadius: 3.5)
        default: return touchpadShape
        }
    }

    static func faceCenter(_ control: DualSenseControl) -> CGPoint {
        let offset: (Double, Double) = switch control {
        case .cross: (0, 1)
        case .circle: (1, 0)
        case .square: (-1, 0)
        default: (0, -1)
        }
        return CGPoint(x: face.x + offset.0 * faceSpread, y: face.y + offset.1 * faceSpread)
    }

    static var trigger: Path {
        Path { path in
            path.move(to: CGPoint(x: l2.minX, y: l2.maxY))
            path.addCurve(
                to: CGPoint(x: l2.minX + 16, y: l2.minY),
                control1: CGPoint(x: l2.minX, y: l2.minY + 8),
                control2: CGPoint(x: l2.minX + 6, y: l2.minY)
            )
            path.addLine(to: CGPoint(x: l2.maxX - 12, y: l2.minY))
            path.addCurve(
                to: CGPoint(x: l2.maxX, y: l2.maxY),
                control1: CGPoint(x: l2.maxX - 4, y: l2.minY),
                control2: CGPoint(x: l2.maxX, y: l2.minY + 8)
            )
            path.closeSubpath()
        }
    }

    static var touchpadShape: Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 3,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 12,
            topTrailingRadius: 3,
            style: .continuous
        )
        .path(in: touchpad)
    }

    static var dpadKeys: [Path] {
        let key = Path { path in
            path.addLines([
                CGPoint(x: -9, y: -31), CGPoint(x: 9, y: -31), CGPoint(x: 9, y: -13),
                CGPoint(x: 0, y: -5), CGPoint(x: -9, y: -13),
            ])
            path.closeSubpath()
        }
        let rounded = key.union(key.strokedPath(StrokeStyle(lineWidth: 4, lineJoin: .round)))
        return [0.0, 90, 180, 270].map { degrees in
            rounded
                .applying(CGAffineTransform(rotationAngle: degrees * .pi / 180))
                .applying(CGAffineTransform(translationX: dpad.x, y: dpad.y))
        }
    }

    static var shellHalf: Path {
        Path { path in
            path.move(to: CGPoint(x: 200, y: 38))
            path.addLine(to: CGPoint(x: 130, y: 38))
            path.addCurve(to: CGPoint(x: 40, y: 40), control1: CGPoint(x: 100, y: 38), control2: CGPoint(x: 60, y: 33))
            path.addCurve(to: CGPoint(x: 11, y: 92), control1: CGPoint(x: 21, y: 46), control2: CGPoint(x: 12, y: 66))
            path.addCurve(
                to: CGPoint(x: 28, y: 216),
                control1: CGPoint(x: 10, y: 132),
                control2: CGPoint(x: 16, y: 178)
            )
            path.addCurve(
                to: CGPoint(x: 78, y: 262),
                control1: CGPoint(x: 38, y: 246),
                control2: CGPoint(x: 56, y: 264)
            )
            path.addCurve(
                to: CGPoint(x: 104, y: 232),
                control1: CGPoint(x: 94, y: 260),
                control2: CGPoint(x: 100, y: 248)
            )
            path.addCurve(
                to: CGPoint(x: 140, y: 194),
                control1: CGPoint(x: 110, y: 212),
                control2: CGPoint(x: 122, y: 198)
            )
            path.addCurve(
                to: CGPoint(x: 200, y: 198),
                control1: CGPoint(x: 160, y: 190),
                control2: CGPoint(x: 182, y: 196)
            )
            path.closeSubpath()
        }
    }

    static var wing: Path {
        Path { path in
            path.move(to: CGPoint(x: 134, y: 38))
            path.addLine(to: CGPoint(x: 130, y: 38))
            path.addCurve(to: CGPoint(x: 40, y: 40), control1: CGPoint(x: 100, y: 38), control2: CGPoint(x: 60, y: 33))
            path.addCurve(to: CGPoint(x: 11, y: 92), control1: CGPoint(x: 21, y: 46), control2: CGPoint(x: 12, y: 66))
            path.addCurve(
                to: CGPoint(x: 28, y: 216),
                control1: CGPoint(x: 10, y: 132),
                control2: CGPoint(x: 16, y: 178)
            )
            path.addCurve(
                to: CGPoint(x: 78, y: 262),
                control1: CGPoint(x: 38, y: 246),
                control2: CGPoint(x: 56, y: 264)
            )
            path.addCurve(
                to: CGPoint(x: 100, y: 196),
                control1: CGPoint(x: 84, y: 240),
                control2: CGPoint(x: 88, y: 214)
            )
            path.addCurve(
                to: CGPoint(x: 122, y: 140),
                control1: CGPoint(x: 110, y: 180),
                control2: CGPoint(x: 120, y: 160)
            )
            path.addCurve(
                to: CGPoint(x: 134, y: 46),
                control1: CGPoint(x: 126, y: 110),
                control2: CGPoint(x: 132, y: 72)
            )
            path.closeSubpath()
        }
    }
}

extension DualSenseShape {
    static func drawShoulders(_ sketch: ConsoleSketch) {
        let triggers = both(trigger)
        sketch.fill(triggers, top: DualSenseInk.trigger, bottom: DualSenseInk.triggerShade)
        sketch.context.stroke(triggers, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
        let bumpers = both(outline(.l1))
        sketch.fill(bumpers, top: DualSenseInk.shellLit, bottom: DualSenseInk.trigger)
        sketch.context.stroke(bumpers, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
    }

    static func drawShell(_ sketch: ConsoleSketch) {
        let context = sketch.context
        let body = both(shellHalf)
        var shadow = context
        shadow.addFilter(.blur(radius: 7))
        shadow.fill(body.offsetBy(dx: 0, dy: 7), with: .color(.black.opacity(0.45)))
        sketch.fill(body, top: DualSenseInk.bodyLit, bottom: DualSenseInk.body)
        let wings = both(wing)
        sketch.fill(wings, top: DualSenseInk.shellLit, bottom: DualSenseInk.shellShade)
        context.stroke(wings, with: .color(.black.opacity(0.22)), lineWidth: 0.8)
        context.stroke(body, with: .color(.black.opacity(0.5)), lineWidth: 0.8)
    }

    static func drawCenter(_ sketch: ConsoleSketch) {
        let context = sketch.context
        let pad = touchpadShape
        context.stroke(pad, with: .color(DualSenseInk.body), lineWidth: 3)
        let bar = both(lightBar)
        var glow = context
        glow.addFilter(.blur(radius: 2.5))
        glow.stroke(bar, with: .color(DualSenseInk.lightBar.opacity(0.9)), lineWidth: 4)
        context.stroke(bar, with: .color(DualSenseInk.lightBar), lineWidth: 1.6)
        sketch.fill(pad, top: DualSenseInk.shellLit, bottom: DualSenseInk.shell)
        context.stroke(pad, with: .color(.black.opacity(0.25)), lineWidth: 0.6)
        for index in 0..<6 {
            context.fill(circle(CGPoint(x: 185 + 6 * Double(index), y: 126), 1.3), with: .color(DualSenseInk.grille))
        }
        for index in 0..<5 {
            context.fill(circle(CGPoint(x: 188 + 6 * Double(index), y: 132.5), 1.3), with: .color(DualSenseInk.grille))
        }
        let ps = circle(psButton, 7.5)
        sketch.fill(ps, top: DualSenseInk.stickLit, bottom: DualSenseInk.stick)
        context.stroke(ps, with: .color(.white.opacity(0.14)), lineWidth: 0.6)
        let mute = Path(roundedRect: CGRect(x: 192, y: 168, width: 16, height: 4.5), cornerRadius: 2.25)
        sketch.fill(mute, top: DualSenseInk.capShade, bottom: DualSenseInk.symbol)
        sketch.fill(both(outline(.create)), top: DualSenseInk.shellLit, bottom: DualSenseInk.capShade)
        context.stroke(both(outline(.create)), with: .color(DualSenseInk.capEdge), lineWidth: 0.7)
    }

    static func drawDpad(_ sketch: ConsoleSketch) {
        let context = sketch.context
        let keys = dpadKeys
        let well = keys.reduce(Path()) { $0.union($1) }
        context.stroke(well, with: .color(DualSenseInk.shellShade), lineWidth: 4)
        for (index, key) in keys.enumerated() {
            sketch.fill(key, top: DualSenseInk.cap, bottom: DualSenseInk.capShade)
            context.stroke(key, with: .color(DualSenseInk.capEdge), lineWidth: 0.8)
            let arrow = Path { path in
                path.addLines([CGPoint(x: 0, y: -26), CGPoint(x: 3.6, y: -20), CGPoint(x: -3.6, y: -20)])
                path.closeSubpath()
            }
            let turned = arrow
                .applying(CGAffineTransform(rotationAngle: Double(index) * .pi / 2))
                .applying(CGAffineTransform(translationX: dpad.x, y: dpad.y))
            context.fill(turned, with: .color(DualSenseInk.symbol))
        }
    }

    static func drawFaceButtons(_ sketch: ConsoleSketch) {
        let context = sketch.context
        for control in [DualSenseControl.cross, .circle, .square, .triangle] {
            let center = faceCenter(control)
            context.fill(circle(center, faceRadius + 2), with: .color(DualSenseInk.shellShade.opacity(0.7)))
            let cap = circle(center, faceRadius)
            sketch.fill(cap, top: DualSenseInk.cap, bottom: DualSenseInk.capShade)
            context.stroke(cap, with: .color(DualSenseInk.capEdge), lineWidth: 0.8)
            context.stroke(
                symbol(control).applying(CGAffineTransform(translationX: center.x, y: center.y)),
                with: .color(DualSenseInk.symbol),
                style: StrokeStyle(lineWidth: 1.3, lineJoin: .round)
            )
        }
    }

    static func drawStick(_ sketch: ConsoleSketch, at center: CGPoint) {
        let context = sketch.context
        sketch.fill(circle(center, stickWell), top: DualSenseInk.stick, bottom: DualSenseInk.bodyLit)
        context.stroke(circle(center, stickWell), with: .color(.white.opacity(0.12)), lineWidth: 0.6)
        context.fill(circle(CGPoint(x: center.x, y: center.y + 2), stickCap + 0.5), with: .color(.black.opacity(0.6)))
        sketch.fill(circle(center, stickCap), top: DualSenseInk.stickLit, bottom: DualSenseInk.stick)
        context.stroke(
            circle(center, stickCap - 3),
            with: .color(DualSenseInk.stickLit.opacity(0.7)),
            style: StrokeStyle(lineWidth: 3.5, dash: [0.9, 1.2])
        )
        sketch.fill(circle(center, stickCap - 7), top: DualSenseInk.stick, bottom: DualSenseInk.stickLit)
    }

    private static var lightBar: Path {
        Path { path in
            path.move(to: CGPoint(x: touchpad.minX - 2.5, y: touchpad.minY + 28))
            path.addCurve(
                to: CGPoint(x: touchpad.minX + 12, y: touchpad.maxY + 2.5),
                control1: CGPoint(x: touchpad.minX - 2.5, y: touchpad.maxY - 10),
                control2: CGPoint(x: touchpad.minX - 1, y: touchpad.maxY + 2.5)
            )
        }
    }

    private static func symbol(_ control: DualSenseControl) -> Path {
        Path { path in
            switch control {
            case .cross:
                path.move(to: CGPoint(x: -4.6, y: -4.6))
                path.addLine(to: CGPoint(x: 4.6, y: 4.6))
                path.move(to: CGPoint(x: 4.6, y: -4.6))
                path.addLine(to: CGPoint(x: -4.6, y: 4.6))
            case .circle:
                path.addEllipse(in: CGRect(x: -5, y: -5, width: 10, height: 10))
            case .square:
                path.addRect(CGRect(x: -4.4, y: -4.4, width: 8.8, height: 8.8))
            default:
                path.addLines([CGPoint(x: 0, y: -5.4), CGPoint(x: 5.4, y: 3.8), CGPoint(x: -5.4, y: 3.8)])
                path.closeSubpath()
            }
        }
    }
}
