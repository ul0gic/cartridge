import SwiftUI

enum CaseMaterial {
    static let shellPlastic = Color(.sRGB, red: 0x1C / 255, green: 0x1C / 255, blue: 0x1F / 255)
    static let trayPlastic = Color(.sRGB, red: 0x15 / 255, green: 0x15 / 255, blue: 0x18 / 255)
    static let jewelEdge = Color(.sRGB, red: 196 / 255, green: 206 / 255, blue: 222 / 255, opacity: 0.16)
    static let jewelTint = Color(.sRGB, red: 210 / 255, green: 220 / 255, blue: 235 / 255)
    static let darkInk = Color(.sRGB, red: 0x11 / 255, green: 0x12 / 255, blue: 0x16 / 255)
    static let xboxPlastic = Color(.sRGB, red: 0x5E / 255, green: 0x8E / 255, blue: 0x36 / 255)
    static let xboxTray = Color(.sRGB, red: 0x44 / 255, green: 0x69 / 255, blue: 0x2A / 255)
    static let xboxHub = Color(.sRGB, red: 0x2E / 255, green: 0x4A / 255, blue: 0x1C / 255)
}

struct CaseFront: View {
    let look: CaseLook
    let pose: CasePose

    var body: some View {
        ZStack {
            switch look.profile.kind {
            case .cardboard:
                art
                RoundedRectangle(cornerRadius: look.profile.cornerRadius)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            case .clamshell:
                CaseMaterial.shellPlastic
                art
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(5)
                RoundedRectangle(cornerRadius: look.profile.cornerRadius)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                Rectangle()
                    .fill(.white.opacity(0.18))
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .jewel:
                CaseJewelFront(look: look, art: art)
            case .keep:
                CaseMaterial.xboxPlastic
                art
                    .clipShape(RoundedRectangle(cornerRadius: look.profile.cornerRadius - Space.half))
                    .padding(0.015 * look.size.width)
            }
        }
        .overlay {
            CaseSheen(
                strength: look.profile.sheen,
                position: 0.5 - 0.024 * pose.yaw,
                size: look.size
            )
        }
    }

    private var art: ArtFace {
        ArtFace(title: look.title, system: look.system, art: look.art, style: .panel)
    }
}

struct CaseCoverInside: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.25), location: 0),
                .init(color: .clear, location: 0.3),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .background(CaseMaterial.xboxTray)
    }
}

struct CaseKeepTray: View {
    let size: CGSize

    var body: some View {
        RadialGradient(
            stops: [
                .init(color: CaseMaterial.xboxHub, location: 0),
                .init(color: CaseMaterial.xboxHub, location: 0.08),
                .init(color: CaseMaterial.xboxTray, location: 0.085),
                .init(color: CaseMaterial.xboxTray, location: 0.45),
                .init(color: CaseMaterial.xboxTray.mix(with: .black, by: 0.12), location: 0.46),
            ],
            center: .center,
            startRadius: 0,
            endRadius: hypot(size.width / 2, size.height / 2)
        )
    }
}

private struct CaseJewelFront: View {
    let look: CaseLook
    let art: ArtFace

    var body: some View {
        let height = look.size.height
        let hinge = look.size.width - 0.98 * height
        ZStack(alignment: .leading) {
            LinearGradient(
                stops: [
                    .init(color: CaseMaterial.jewelTint.opacity(0.22), location: 0),
                    .init(color: CaseMaterial.jewelTint.opacity(0.16), location: hinge / look.size.width),
                    .init(color: CaseMaterial.jewelTint.opacity(0.04), location: hinge / look.size.width),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            Canvas { context, size in
                for offset in stride(from: 0, to: size.width, by: 4) {
                    context.fill(Path(CGRect(x: offset, y: 0, width: 1, height: size.height)), with: .color(.white))
                }
            }
            .opacity(0.16)
            .frame(width: hinge)
            art
                .frame(width: 0.96 * height, height: 0.96 * height)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 0.02 * height)
            RoundedRectangle(cornerRadius: look.profile.cornerRadius)
                .strokeBorder(.white.opacity(0.34), lineWidth: 1)
        }
    }
}

private struct CaseSheen: View {
    let strength: Double
    let position: Double
    let size: CGSize

    private static let spread: CGFloat = 2.6
    private static let angle = Angle.degrees(102)

    var body: some View {
        let width = size.width * Self.spread
        let directionX = sin(Self.angle.radians)
        let directionY = -cos(Self.angle.radians)
        let length = width * abs(directionX) + size.height * abs(directionY)
        let reachX = directionX * length / (2 * width)
        let reachY = directionY * length / (2 * size.height)
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.34),
                .init(color: .white.opacity(strength), location: 0.47),
                .init(color: .white.opacity(strength * 0.35), location: 0.53),
                .init(color: .clear, location: 0.64),
            ],
            startPoint: UnitPoint(x: 0.5 - reachX, y: 0.5 - reachY),
            endPoint: UnitPoint(x: 0.5 + reachX, y: 0.5 + reachY)
        )
        .frame(width: width, height: size.height)
        .offset(x: (size.width - width) * (position - 0.5))
        .blendMode(.screen)
    }
}

struct CaseSpine: View {
    let look: CaseLook

    var body: some View {
        let depth = look.depth
        let height = look.size.height
        let keep = look.profile.kind == .keep
        HStack(spacing: 0.08 * height) {
            Text(look.system.displayName)
                .font(.system(size: 0.26 * depth, weight: .heavy))
                .foregroundStyle(look.tints.spine)
                .padding(.horizontal, keep ? Space.n1 : 3)
                .padding(.vertical, keep ? Space.half : 4)
                .background(look.tints.ink, in: RoundedRectangle(cornerRadius: keep ? Space.half : 3))
            Text(look.title)
                .font(.system(size: 0.5 * depth, weight: .heavy).width(.condensed))
                .foregroundStyle(look.tints.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 0.74 * height, alignment: .leading)
        }
        .padding(.leading, 0.1 * depth)
        .frame(width: height, height: depth, alignment: .leading)
        .rotationEffect(.degrees(90))
        .frame(width: depth, height: height)
        .background(look.tints.spine)
        .overlay {
            switch look.profile.kind {
            case .cardboard, .keep:
                EmptyView()
            case .clamshell:
                VStack {
                    CaseMaterial.shellPlastic.frame(height: 4)
                    Spacer()
                    CaseMaterial.shellPlastic.frame(height: 4)
                }
            case .jewel:
                Rectangle().strokeBorder(.white.opacity(0.3), lineWidth: 1)
            }
        }
    }
}

struct CaseEdge: View {
    let look: CaseLook
    let tint: Color
    let seam: Bool

    var body: some View {
        switch look.profile.kind {
        case .cardboard:
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.06), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.18), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .background(tint)
        case .clamshell:
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.12), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .clear, location: 0.82),
                    .init(color: .white.opacity(0.08), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .background(CaseMaterial.shellPlastic)
            .overlay {
                if seam {
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .frame(width: 2)
                        .shadow(color: .white.opacity(0.1), radius: 0, x: 1, y: 0)
                        .padding(.vertical, 0.06 * look.size.height)
                }
            }
        case .jewel:
            HStack {
                Color.white.opacity(0.4).frame(width: 1)
                Spacer()
                Color.white.opacity(0.4).frame(width: 1)
            }
            .background(CaseMaterial.jewelEdge)
        case .keep:
            LinearGradient(
                stops: [
                    .init(color: .white.opacity(0.12), location: 0),
                    .init(color: .clear, location: 0.18),
                    .init(color: .clear, location: 0.82),
                    .init(color: .white.opacity(0.08), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .background(tint)
        }
    }
}
