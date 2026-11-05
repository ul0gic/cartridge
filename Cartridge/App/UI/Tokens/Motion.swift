import SwiftUI

enum Motion {
    static let focus: Duration = .milliseconds(120)
    static let scroll: Duration = .milliseconds(180)
    static let band: Duration = .milliseconds(200)
    static let handover: Duration = .milliseconds(200)
    static let ambient: Duration = .milliseconds(450)
    static let ambientDelay: Duration = .milliseconds(150)
    static let backdropDrift: Duration = .seconds(24)
    static let shimmer: Duration = .milliseconds(1400)
    static let spin: Duration = .milliseconds(900)
    static let sheet: Duration = .milliseconds(160)
    static let shelf: Duration = .milliseconds(320)
    static let confirmArm: Duration = .milliseconds(3000)
    static let chipHold: Duration = .milliseconds(2000)

    static let repeatDelay: Duration = .milliseconds(400)
    static let repeatInterval: Duration = .milliseconds(125)
    static let stickPress: Float = 0.5
    static let stickRelease: Float = 0.3
    static let stickRestDwell: Duration = .milliseconds(100) // a stick that never rests cannot press (drift)
    static let tiltDeadZone: Float = 0.12

    static let ringTurn = Animation.spring(response: 0.62, dampingFraction: 0.74)
    static let ringConsoleRise = Animation.spring(response: 0.5, dampingFraction: 0.7)

    static let caseTilt = Animation.spring(response: 0.48, dampingFraction: 0.85)
    static let caseDriftDelay: Duration = .seconds(3)
    static let caseDriftIn = Animation.timingCurve(1.0 / 3, 0, 2.0 / 3, 1, duration: 1.2) // smoothstep
    static let caseDriftYawPeriod: TimeInterval = 8
    static let caseDriftPitchPeriod: TimeInterval = 11

    static let introGlide: TimeInterval = 1.7
    static let introEnd: TimeInterval = 2.35
    static let introReducedEnd: TimeInterval = 1.4

    static let insertOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.2, y: 0.8),
        endControlPoint: UnitPoint(x: 0.2, y: 1)
    )
    static let insertPull = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.3, y: 0.7),
        endControlPoint: UnitPoint(x: 0.2, y: 1)
    )
    static let insertGlide = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.2, y: 0.9),
        endControlPoint: UnitPoint(x: 0.25, y: 1)
    )
    static let insertIn = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.4, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 1)
    )
    static let insertGravity = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.55, y: 0),
        endControlPoint: UnitPoint(x: 0.9, y: 0.4)
    )
    static let insertPop = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.2, y: 0.9),
        endControlPoint: UnitPoint(x: 0.25, y: 1.25)
    )
    static let insertInOut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.45, y: 0),
        endControlPoint: UnitPoint(x: 0.55, y: 1)
    )
    static let insertSlide = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.35, y: 0),
        endControlPoint: UnitPoint(x: 0.15, y: 1)
    )
    static let insertShut = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.55, y: 0),
        endControlPoint: UnitPoint(x: 1, y: 0.45)
    )
    static let insertSquare = Spring(response: 0.26, dampingRatio: 0.9)
    static let insertConsoleRise = Spring(response: 0.46, dampingRatio: 0.82)
    static let insertDoor = Spring(response: 0.26, dampingRatio: 0.72)
    static let insertHoldPulse: TimeInterval = 1.2
    static let insertHoldGlow: TimeInterval = 1.6
    static let insertCaptionDelay: TimeInterval = 0.6
    static let insertCaptionFade: TimeInterval = 0.2

    static func easeIn(_ duration: Duration) -> Animation {
        .timingCurve(0.4, 0, 1, 1, duration: duration.seconds)
    }

    static func easeOut(_ duration: Duration) -> Animation {
        .timingCurve(0.2, 0.8, 0.2, 1, duration: duration.seconds)
    }

    static func easeInOut(_ duration: Duration) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: duration.seconds)
    }
}

struct InsertBeat {
    let start: Double
    let end: Double
    let curve: UnitCurve

    func progress(_ milliseconds: Double) -> Double {
        curve.value(at: min(1, max(0, (milliseconds - start) / (end - start))))
    }
}

struct InsertKey {
    let time: Double
    let value: Double
    let curve: UnitCurve

    init(_ time: Double, _ value: Double, _ curve: UnitCurve) {
        self.time = time
        self.value = value
        self.curve = curve
    }
}

extension InsertBeat {
    static let chrome = InsertBeat(start: 40, end: 260, curve: Motion.insertOut)
    static let glide = InsertBeat(start: 0, end: 380, curve: Motion.insertGlide)
    static let dim = InsertBeat(start: 0, end: 400, curve: Motion.insertOut)
    static let flap = InsertBeat(start: 160, end: 280, curve: Motion.insertOut)
    static let rise = InsertBeat(start: 200, end: 520, curve: Motion.insertPull)
    static let lid = InsertBeat(start: 160, end: 460, curve: Motion.insertPull)
    static let lift = InsertBeat(start: 380, end: 640, curve: Motion.insertOut)
    static let spin = InsertBeat(start: 380, end: 1000, curve: Motion.insertInOut)
    static let recede = InsertBeat(start: 520, end: 760, curve: Motion.insertIn)
    static let discRecede = InsertBeat(start: 560, end: 800, curve: Motion.insertIn)
    static let slot = InsertBeat(start: 480, end: 760, curve: Motion.insertPop)
    static let hang = InsertBeat(start: 520, end: 760, curve: Motion.insertOut)
    static let lay = InsertBeat(start: 640, end: 880, curve: Motion.insertInOut)
    static let drop = InsertBeat(start: 760, end: 900, curve: Motion.insertGravity)
    static let settle = InsertBeat(start: 880, end: 1000, curve: Motion.insertIn)
    static let seat = InsertBeat(start: 900, end: 1000, curve: .linear)
    static let led = InsertBeat(start: 1000, end: 1040, curve: Motion.insertOut)
    static let flashUp = InsertBeat(start: 1000, end: 1040, curve: Motion.insertOut)
    static let flashDown = InsertBeat(start: 1040, end: 1180, curve: Motion.insertOut)
    static let black = InsertBeat(start: 1000, end: 1200, curve: Motion.insertIn)
}

enum ConsoleBeat {
    static let rise = 400.0
    static let handoff = 480.0
    static let crane = InsertBeat(start: 480, end: 980, curve: Motion.insertInOut)
    static let edges = InsertBeat(start: 480, end: 560, curve: Motion.insertOut)
    static let slide = InsertBeat(start: 1000, end: 1240, curve: Motion.insertSlide)
    static let lock = InsertBeat(start: 1250, end: 1330, curve: Motion.insertGravity)
    static let led = InsertBeat(start: 1460, end: 1500, curve: Motion.insertOut)
}

struct InsertSchedule {
    let pace: Double
    let flap: InsertBeat
    let rise: InsertBeat
    let recede: InsertBeat
    let flashUp: InsertBeat
    let flashDown: InsertBeat
    let black: InsertBeat
    let flashPeak: Double
    let dim: Double
    let seated: Double
    let total: Double
    let ejectSpan: Double
    let ejectFloor: Double
    let failedEjectRate: Double?

    static let soundLead = 100.0 // insert*.m4a put their clunk 100 ms in, so it lands on the hit

    static let slot = InsertSchedule(
        pace: 1,
        flap: .flap,
        rise: .rise,
        recede: .recede,
        flashUp: .flashUp,
        flashDown: .flashDown,
        black: .black,
        flashPeak: 0.9,
        dim: Layout.panelInsertDim,
        seated: 1000,
        total: 1200,
        ejectSpan: 240,
        ejectFloor: 1,
        failedEjectRate: nil
    )

    static let console = InsertSchedule(
        pace: 1.25,
        flap: InsertBeat(start: 140, end: 260, curve: Motion.insertOut),
        rise: InsertBeat(start: 180, end: 480, curve: Motion.insertPull),
        recede: InsertBeat(start: 420, end: 640, curve: Motion.insertIn),
        flashUp: InsertBeat(start: 1480, end: 1520, curve: Motion.insertOut),
        flashDown: InsertBeat(start: 1520, end: 1620, curve: Motion.insertOut),
        black: InsertBeat(start: 1540, end: 1820, curve: Motion.insertIn),
        flashPeak: 0.85,
        dim: Layout.panelInsertDimConsole,
        seated: 1330,
        total: 1820,
        ejectSpan: 700,
        ejectFloor: 2,
        failedEjectRate: 2
    )

    var soundAt: Double {
        seated * pace - Self.soundLead
    }

    var seatedAt: Double {
        seated * pace
    }

    var totalAt: Double {
        total * pace
    }

    func ejectRate(from milliseconds: Double, failed: Bool) -> Double {
        if failed, let failedEjectRate {
            return failedEjectRate
        }
        return max(ejectFloor, milliseconds / (ejectSpan * pace))
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
