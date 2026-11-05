import SwiftUI

struct InsertGeometry {
    let canvas: CGSize
    let scale: CGFloat
    let caseSize: CGSize
    let depth: CGFloat
    let restX: CGFloat
    let floorY: CGFloat
    let media: CGRect

    init(system: GameSystem, isMoment: Bool, canvas: CGSize) {
        let scale = min(canvas.width / Layout.panelCanvas.width, canvas.height / Layout.panelCanvas.height)
        let extent = (isMoment ? Layout.panelArtSizeMoment : Layout.panelArtSize) * scale
        let height = switch system.tileAspect {
        case ..<1: extent
        case 1: extent * Layout.panelArtSquareShare
        default: extent * Layout.panelArtWideShare / system.tileAspect
        }
        let profile = system.caseProfile
        self.canvas = canvas
        self.scale = scale
        caseSize = CGSize(width: height * profile.aspect, height: height)
        depth = height * profile.depth
        restX = (isMoment ? Layout.panelArtCenterXMoment : Layout.panelArtCenterX) * canvas.width
            / Layout.panelCanvas.width
        floorY = Layout.panelFloorY * canvas.height / Layout.panelCanvas.height
        media = system.mediaRect(in: caseSize)
    }

    var camera: CGFloat {
        Layout.caseCamera * scale
    }

    var slotCenter: CGPoint {
        CGPoint(x: canvas.width / 2, y: floorY)
    }

    func caseX(_ frame: InsertFrame) -> CGFloat {
        restX + (slotCenter.x - restX) * frame.glide
    }

    var glidedScale: CGFloat {
        min(1, Layout.panelInsertBoxHeight * scale / caseSize.height)
    }

    var risenCart: CGFloat {
        0.2 * media.height - media.maxY
    }

    func caseScale(_ frame: InsertFrame) -> CGFloat {
        1 + (glidedScale - 1) * frame.glide
    }

    func glided(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: slotCenter.x + (point.x - caseSize.width / 2) * glidedScale,
            y: floorY + (point.y - caseSize.height) * glidedScale
        )
    }

    func screen(_ point: CGPoint, _ frame: InsertFrame) -> CGPoint {
        let scale = caseScale(frame)
        return CGPoint(
            x: caseX(frame) + (point.x - caseSize.width / 2) * scale,
            y: floorY + (point.y - caseSize.height) * scale
        )
    }
}

struct PanelCaseStage: View {
    let controller: any ControllerMonitoring
    let game: GameRecord
    let art: TileArt
    let isMoment: Bool
    let canvas: CGSize
    let frame: InsertFrame?

    var body: some View {
        let system = game.system
        let geometry = InsertGeometry(system: system, isMoment: isMoment, canvas: canvas)
        let height = geometry.caseSize.height
        let inFront = frame.map {
            system.isDisc ? !$0.discInTray : $0.mediaInFront(depth: geometry.depth, scale: geometry.scale)
        } ?? false
        let cartInBox = frame?.console?.cartInBox ?? true
        ZStack {
            if let frame, !system.isDisc, !inFront, cartInBox {
                InsertMedia(title: game.title, system: system, art: art, frame: frame, geometry: geometry)
            }
            GameCase(
                title: game.title,
                system: system,
                art: art,
                height: height,
                camera: geometry.camera,
                tilt: controller.menuTilt,
                insert: frame?.casePose(system: system, scale: geometry.scale) ?? .rest
            )
            .scaleEffect(frame.map(geometry.caseScale) ?? 1, anchor: .bottom)
            .position(x: frame.map(geometry.caseX) ?? geometry.restX, y: geometry.floorY - height / 2)
            if let frame, let console = frame.console {
                if inFront, cartInBox {
                    InsertMedia(title: game.title, system: system, art: art, frame: frame, geometry: geometry)
                }
                ConsoleScene(title: game.title, art: art, frame: console, geometry: geometry)
            } else if let frame {
                InsertSlot(system: system, part: .back, geometry: geometry, frame: frame)
                if inFront {
                    InsertMedia(title: game.title, system: system, art: art, frame: frame, geometry: geometry)
                }
                InsertSlot(system: system, part: .front, geometry: geometry, frame: frame)
            }
        }
        .offset(y: (frame?.shake ?? 0) * geometry.scale)
        .accessibilityHidden(true)
    }
}

struct InsertMedia: View {
    let title: String
    let system: GameSystem
    let art: TileArt
    let frame: InsertFrame
    let geometry: InsertGeometry

    var body: some View {
        if system.isDisc {
            disc
        } else {
            cart
        }
    }

    private var cart: some View {
        let rest = geometry.media
        let scale = geometry.scale
        let risen = geometry.risenCart
        let hung = risen - 18 * scale
        let landed = geometry.caseSize.height - rest.maxY
        let seated = landed + 0.45 * rest.height
        let lift = risen * frame.rise + (hung - risen) * frame.hang + (landed - hung) * frame.drop
            + (seated - landed) * frame.seat + 3 * scale * frame.jolt
        let grow = 1 + 0.04 * frame.hang - 0.04 * frame.drop
        let caseScale = geometry.caseScale(frame)
        let size = CGSize(width: rest.width * caseScale * grow, height: rest.height * caseScale * grow)
        let center = geometry.screen(CGPoint(x: rest.midX, y: rest.midY + lift), frame)
        let visible = min(size.height, max(0, geometry.floorY - (center.y - size.height / 2)))
        return GameMedia(title: title, system: system, art: art)
            .frame(width: size.width, height: size.height)
            .mask(alignment: .top) {
                Rectangle().frame(height: visible)
            }
            .position(center)
    }

    private var disc: some View {
        let rest = geometry.media
        let scale = geometry.scale
        let size = geometry.caseSize
        let resting = -geometry.depth / 2 + 3 * scale
        let raised = -0.22 * size.height
        let across = size.width / 2 - rest.midX
        let laid = size.height - rest.midY - 4 * scale
        let x: CGFloat
        let y: CGFloat
        let depth: CGFloat
        if frame.console == nil {
            x = 0.4 * across * frame.lift + 0.6 * across * frame.lay
            y = raised * frame.lift + (laid - 10 * scale - raised) * frame.lay + 10 * scale * frame.settle
                + 2 * scale * frame.jolt
            depth = resting + (140 * scale - resting) * frame.lift + (30 - 140) * scale * frame.lay
        } else {
            x = across * frame.lift
            y = -PS1Disc.boxRise * size.height * frame.lift
            depth = resting * (1 - frame.lift)
        }
        let camera = geometry.camera
        let perspective = camera / (camera - depth)
        let eye = CGPoint(x: size.width / 2, y: -Layout.caseEyeLift * size.height)
        let projected = CGPoint(
            x: eye.x + (rest.midX + x - eye.x) * perspective,
            y: eye.y + (rest.midY + y - eye.y) * perspective
        )
        let side = rest.width * perspective * (1 - 0.03 * frame.settle) * geometry.caseScale(frame)
        return GameMedia(title: title, system: system, art: art)
            .frame(width: side, height: side)
            .rotationEffect(.degrees(frame.console == nil ? 900 * frame.spin : 0))
            .rotation3DEffect(.degrees(76 * frame.lay), axis: (x: 1, y: 0, z: 0), perspective: side / camera)
            .position(geometry.screen(projected, frame))
    }
}

struct InsertCurtain: View {
    let insert: CartridgeInsert
    let frame: InsertFrame
    let title: String
    let system: GameSystem
    let isMoment: Bool
    let glyphs: HintGlyphs?
    let date: Date

    var body: some View {
        GeometryReader { proxy in
            let geometry = InsertGeometry(system: system, isMoment: isMoment, canvas: proxy.size)
            ZStack {
                flash(geometry)
                Color.black.opacity(frame.black)
                if case .holding(let since) = insert.stage {
                    if let console = frame.console {
                        ConsoleHoldingLight(
                            title: title,
                            geometry: geometry,
                            held: date.timeIntervalSince(since),
                            lens: console.ledLens(geometry),
                            ring: console.ledRing,
                            color: system.powerLED
                        )
                        if insert.setsUpXboxDrive {
                            XboxFirstStartCaption(
                                geometry: geometry,
                                held: date.timeIntervalSince(since),
                                lens: console.ledLens(geometry)
                            )
                        }
                        HintBar(hints: [Hint(kind: .back, label: "Cancel")], glyphs: glyphs, counter: nil)
                    } else {
                        holding(geometry, held: date.timeIntervalSince(since))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func flash(_ geometry: InsertGeometry) -> some View {
        let canvas = geometry.canvas
        return ZStack {
            glow(radii: CGSize(width: 0.22 * canvas.width, height: 0.09 * canvas.height), color: .white)
            glow(radii: CGSize(width: 0.7 * canvas.width, height: 0.4 * canvas.height), color: .white.opacity(0.35))
        }
        .position(frame.console?.flashCenter(geometry) ?? geometry.slotCenter)
        .opacity(system.insertSchedule.flashPeak * frame.flash)
    }

    private func glow(radii: CGSize, color: Color) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [color, color.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: radii.width
            ))
            .frame(width: 2 * radii.width, height: 2 * radii.width)
            .scaleEffect(x: 1, y: radii.height / radii.width)
    }

    private func holding(_ geometry: InsertGeometry, held: TimeInterval) -> some View {
        let led = system.powerLED
        let pulse = 0.7 + 0.3 * cos(2 * .pi * held / Motion.insertHoldPulse)
        let caption = Motion.insertOut.value(
            at: min(1, max(0, (held - Motion.insertCaptionDelay) / Motion.insertCaptionFade))
        )
        return ZStack {
            Capsule()
                .fill(led)
                .shadow(color: led, radius: 5 * geometry.scale)
                .shadow(color: led.opacity(0.5), radius: 15 * geometry.scale)
                .frame(width: 14 * geometry.scale, height: 8 * geometry.scale)
                .opacity(pulse)
                .position(InsertSlot.ledCenter(system: system, geometry: geometry))
            Text("Starting \(title)…")
                .typeStyle(.body)
                .foregroundStyle(Palette.textSecondary)
                .opacity(caption)
                .position(
                    x: geometry.canvas.width / 2,
                    y: geometry.floorY + Layout.panelInsertCaptionDrop * geometry.scale
                )
            HintBar(hints: [Hint(kind: .back, label: "Cancel")], glyphs: glyphs, counter: nil)
        }
    }
}

private struct XboxFirstStartCaption: View {
    let geometry: InsertGeometry
    let held: TimeInterval
    let lens: CGRect

    private var lineOffset: CGFloat {
        (TypeStyle.body.size * TypeStyle.body.leading + TypeStyle.meta.size * TypeStyle.meta.leading) / 2
    }

    var body: some View {
        let pace = InsertSchedule.console.pace
        let fade = Motion.insertOut.value(
            at: min(1, max(0, (held - Motion.insertCaptionDelay * pace) / Motion.insertCaptionFade))
        )
        Text("First start: setting up its Xbox drive.")
            .typeStyle(.meta)
            .foregroundStyle(Palette.textTertiary)
            .fixedSize()
            .frame(width: 0, alignment: .leading)
            .opacity(fade)
            .position(x: lens.maxX + Layout.panelInsertCaptionGap * geometry.scale, y: lens.midY + lineOffset)
    }
}

struct InsertSlot: View {
    enum Part {
        case back
        case front
    }

    let system: GameSystem
    let part: Part
    let geometry: InsertGeometry
    let frame: InsertFrame

    private var mediaWidth: CGFloat {
        geometry.media.width
    }

    private var center: CGPoint {
        geometry.slotCenter
    }

    private var scale: CGFloat {
        geometry.scale
    }

    var body: some View {
        ZStack {
            if system.isDisc {
                well
            } else {
                slot
            }
        }
        .opacity(frame.slot)
        .scaleEffect(
            x: 0.3 + 0.7 * frame.slot,
            y: 1,
            anchor: UnitPoint(x: center.x / geometry.canvas.width, y: center.y / geometry.canvas.height)
        )
    }

    static func ledCenter(system: GameSystem, geometry: InsertGeometry) -> CGPoint {
        let mediaWidth = geometry.media.width
        let center = geometry.slotCenter
        let scale = geometry.scale
        if system.isDisc {
            let width = mediaWidth * 1.06
            return CGPoint(x: center.x - width / 2 - 33 * scale, y: center.y + mediaWidth * 0.135)
        }
        let width = mediaWidth + 24 * scale
        return CGPoint(x: center.x - width / 2 - 27 * scale, y: center.y + 20 * scale)
    }

    @ViewBuilder private var slot: some View {
        let width = mediaWidth + 24 * scale
        let plastic = system.slotPlastic
        switch part {
        case .back:
            let plate = 14 * scale
            UnevenRoundedRectangle(topLeadingRadius: plate, topTrailingRadius: plate)
                .fill(LinearGradient(
                    colors: [plastic.mix(with: .white, by: 0.12), plastic],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(alignment: .top) {
                    Color.white.opacity(0.4).frame(height: 1).padding(.horizontal, plate)
                }
                .frame(width: width + 80 * scale, height: 30 * scale)
                .position(x: center.x, y: center.y - 7 * scale)
            Capsule()
                .fill(MediaInk.gray(0x03, 0x03, 0x04))
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1).offset(y: -1).mask(Capsule()))
                .frame(width: width, height: 16 * scale)
                .position(center)
        case .front:
            let lip = UnevenRoundedRectangle(bottomLeadingRadius: 12 * scale, bottomTrailingRadius: 12 * scale)
            lip
                .fill(LinearGradient(
                    colors: [plastic, plastic.mix(with: .black, by: 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(alignment: .top) {
                    Color.white.opacity(0.35).frame(height: 1)
                }
                .clipShape(lip)
                .shadow(color: .black.opacity(0.6), radius: 15 * scale, y: 12 * scale)
                .frame(width: width + 28 * scale, height: 26 * scale)
                .position(x: center.x, y: center.y + 21 * scale)
            light
        }
    }

    @ViewBuilder private var well: some View {
        let width = mediaWidth * 1.06
        let height = mediaWidth * 0.27
        let plastic = system.slotPlastic
        switch part {
        case .back:
            Ellipse()
                .fill(.white.opacity(0.25))
                .frame(width: width + 14 * scale, height: height + 14 * scale)
                .position(center)
            Ellipse()
                .fill(plastic)
                .frame(width: width + 12 * scale, height: height + 12 * scale)
                .position(center)
            Ellipse()
                .fill(RadialGradient(
                    stops: [
                        .init(color: MediaInk.gray(0x2A, 0x2B, 0x30), location: 0.09),
                        .init(color: MediaInk.gray(0x05, 0x05, 0x06), location: 0.11),
                        .init(color: MediaInk.gray(0x05, 0x05, 0x06), location: 0.7),
                        .init(color: MediaInk.gray(0x11, 0x12, 0x16), location: 1),
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: width / 2
                ))
                .frame(width: width, height: height)
                .position(center)
        case .front:
            WellLip(thickness: 6 * scale)
                .fill(plastic, style: FillStyle(eoFill: true))
                .frame(width: width + 12 * scale, height: height + 12 * scale)
                .position(center)
            light
        }
    }

    private var light: some View {
        let color = system.powerLED
        let spot = Self.ledCenter(system: system, geometry: geometry)
        return Capsule()
            .fill(color)
            .shadow(color: color, radius: 5 * scale)
            .shadow(color: color.opacity(0.5), radius: 15 * scale)
            .frame(width: 14 * scale, height: 8 * scale)
            .opacity(frame.led)
            .position(spot)
    }
}

private struct WellLip: Shape {
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: rect)
        path.addPath(Path(ellipseIn: CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: rect.height - thickness
        )))
        return path
    }
}
