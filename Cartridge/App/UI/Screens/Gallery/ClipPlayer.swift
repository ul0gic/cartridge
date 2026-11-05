import AVFoundation
import Observation

@MainActor
@Observable
final class ClipPlayer {
    private static let tickInterval: Duration = .milliseconds(100)

    let player: AVPlayer
    let total: Double
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0

    @ObservationIgnored var onEnded: (@MainActor () -> Void)?
    @ObservationIgnored private var hasEnded = false
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    init(url: URL, total: Double) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        self.total = total
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didEnd() }
        }
    }

    var fraction: Double {
        total > 0 ? min(max(elapsed / total, 0), 1) : 0
    }

    func play() {
        if hasEnded {
            hasEnded = false
            elapsed = 0
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func didEnd() {
        hasEnded = true
        isPlaying = false
        elapsed = total
        onEnded?()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do {
                    try await Task.sleep(for: Self.tickInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func tick() {
        guard isPlaying else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            elapsed = min(max(seconds, 0), total)
        }
    }
}
