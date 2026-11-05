import Foundation
import Observation

enum CaptureCardID: Hashable {
    case screenshot
    case recording
    case replay
}

@MainActor
@Observable
final class CaptureMenuModel {
    private(set) var highlighted = CaptureCardID.screenshot
    private(set) var isBusy = false

    let recorder: CaptureRecorder
    let chips: PlayChipsModel

    @ObservationIgnored private let resume: () -> Void

    init(recorder: CaptureRecorder, chips: PlayChipsModel, resume: @escaping () -> Void) {
        self.recorder = recorder
        self.chips = chips
        self.resume = resume
        highlighted = recorder.isRecording ? .recording : .screenshot
    }

    var cards: [CaptureCardID] {
        [.screenshot, .recording, .replay]
    }

    var subtitle: String {
        recorder.isRecording
            ? "Paused. Recording, \(chips.elapsedText) so far."
            : "Paused. Choose what to keep."
    }

    func handle(_ event: NavigationEvent) {
        guard !isBusy else { return }
        switch event.action {
        case .move(.left):
            step(-1)
        case .move(.right):
            step(1)
        case .confirm:
            activate(highlighted)
        case .back:
            resume()
        case .move, .pause, .options, .secondary, .section, .text, .erase:
            break
        }
    }

    private func step(_ offset: Int) {
        guard let index = cards.firstIndex(of: highlighted), cards.indices.contains(index + offset) else { return }
        highlighted = cards[index + offset]
    }

    private func activate(_ card: CaptureCardID) {
        switch card {
        case .screenshot:
            isBusy = true
            Task {
                await chips.perform(
                    progress: nil,
                    success: "Screenshot saved to the Gallery",
                    work: recorder.screenshot
                )
                resume()
            }
        case .recording:
            toggleRecording()
        case .replay:
            resume()
            Task {
                await chips.perform(
                    progress: "Saving the last 30 seconds…",
                    success: "Clip saved to the Gallery",
                    work: recorder.saveReplay
                )
            }
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            resume()
            Task {
                await chips.perform(
                    progress: "Saving the clip…",
                    success: "Clip saved to the Gallery",
                    work: recorder.stopRecording
                )
            }
            return
        }
        do throws(CaptureError) {
            try recorder.startRecording()
        } catch {
            chips.fail(error)
        }
        resume()
    }
}
