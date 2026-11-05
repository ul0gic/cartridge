import Foundation
import Observation

struct PlayChip: Identifiable, Equatable {
    enum Kind: Equatable {
        case recording
        case speed
        case notice
        case failure
    }

    let id: UUID
    let kind: Kind
    let glyph: String?
    let head: String
    var detail: String?
    var isBusy = false
}

@MainActor
@Observable
final class PlayChipsModel {
    private static let poll = Duration.milliseconds(100)

    private(set) var recordingSeconds = 0
    private(set) var speedChip: PlayChip?
    private(set) var notices: [PlayChip] = []

    @ObservationIgnored private let recorder: CaptureRecorder
    @ObservationIgnored private let session: any PlaySessionControlling
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var holdTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var tips: [PlayChip] = []
    @ObservationIgnored private var tipTask: Task<Void, Never>?

    init(recorder: CaptureRecorder, session: any PlaySessionControlling) {
        self.recorder = recorder
        self.session = session
        pollTask = Task { [weak self] in
            var elapsed = Duration.zero
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.poll)
                guard let self else { return }
                let now = ContinuousClock.now
                elapsed = tick(elapsed: elapsed, since: last, now: now)
                last = now
            }
        }
    }

    var recordingChip: PlayChip? {
        recorder.isRecording
            ? PlayChip(id: Self.recordingID, kind: .recording, glyph: "record.circle.fill", head: "Recording")
            : nil
    }

    var elapsedText: String {
        Self.clock(recordingSeconds)
    }

    var chips: [PlayChip] {
        [recordingChip, speedChip].compactMap(\.self) + notices
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        tipTask?.cancel()
        tipTask = nil
        tips.removeAll()
        for task in holdTasks.values {
            task.cancel()
        }
        holdTasks.removeAll()
    }

    func perform(
        progress: String?,
        success: String,
        work: @MainActor () async throws(CaptureError) -> CaptureItem
    ) async {
        let busy = progress.map { post(PlayChip(id: UUID(), kind: .notice, glyph: nil, head: $0, isBusy: true)) }
        do throws(CaptureError) {
            _ = try await work()
            remove(busy)
            post(
                PlayChip(id: UUID(), kind: .notice, glyph: "checkmark.circle.fill", head: success),
                hold: Motion.chipHold
            )
        } catch {
            remove(busy)
            fail(error)
        }
    }

    func fail(_ error: CaptureError) {
        let cause = error == .diskFull ? "Your Mac is out of disk space" : "The file couldn’t be written"
        post(
            PlayChip(
                id: UUID(),
                kind: .failure,
                glyph: nil,
                head: "Couldn’t save the capture",
                detail: "\(cause). The game keeps running."
            ),
            hold: HubStyle.alertHold
        )
    }

    func recordingEnded(_ result: Result<CaptureItem, CaptureError>) {
        switch result {
        case .success:
            post(
                PlayChip(id: UUID(), kind: .notice, glyph: "checkmark.circle.fill", head: "Clip saved to the Gallery"),
                hold: Motion.chipHold
            )
        case .failure(let error):
            fail(error)
        }
    }

    func tip(head: String, detail: String) {
        tips.append(PlayChip(id: UUID(), kind: .notice, glyph: "gamecontroller.fill", head: head, detail: detail))
        guard tipTask == nil else { return }
        tipTask = Task { [weak self] in
            while let chip = self?.tips.first {
                self?.post(chip, hold: HubStyle.alertHold)
                try? await Task.sleep(for: HubStyle.alertHold)
                guard !Task.isCancelled else { return }
                self?.tips.removeFirst()
            }
            self?.tipTask = nil
        }
    }

    static func clock(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private static let recordingID = UUID()

    private func tick(
        elapsed: Duration,
        since last: ContinuousClock.Instant,
        now: ContinuousClock.Instant
    ) -> Duration {
        updateSpeedChip()
        guard recorder.isRecording else {
            recordingSeconds = 0
            return .zero
        }
        let total = session.state == .running ? elapsed + last.duration(to: now) : elapsed
        recordingSeconds = Int(total.seconds)
        return total
    }

    private func updateSpeedChip() {
        let chip: PlayChip? = switch session.activeSpeed {
        case .rewinding:
            PlayChip(id: Self.speedID, kind: .speed, glyph: "backward.fill", head: "Rewinding")
        case .rewindHolding:
            PlayChip(id: Self.speedID, kind: .speed, glyph: "backward.fill", head: "Can’t rewind further")
        case .fastForward where session.requestedSpeed == .fastForward:
            PlayChip(
                id: Self.speedID,
                kind: .speed,
                glyph: "forward.fill",
                head: "Fast forward",
                detail: "Open the menu to stop"
            )
        case .fastForward, .normal, nil:
            nil
        }
        if chip != speedChip {
            speedChip = chip
        }
    }

    private static let speedID = UUID()

    @discardableResult
    private func post(_ chip: PlayChip, hold: Duration? = nil) -> UUID {
        notices.append(chip)
        if let hold {
            holdTasks[chip.id] = Task { [weak self] in
                try? await Task.sleep(for: hold)
                guard !Task.isCancelled else { return }
                self?.remove(chip.id)
            }
        }
        return chip.id
    }

    private func remove(_ id: UUID?) {
        guard let id else { return }
        holdTasks.removeValue(forKey: id)?.cancel()
        notices.removeAll { $0.id == id }
    }
}
