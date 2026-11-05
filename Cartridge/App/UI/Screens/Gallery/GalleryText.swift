import Foundation

extension CaptureItem {
    var kindName: String {
        switch kind {
        case .screenshot: "Screenshot"
        case .clip: "Clip"
        case .gif: "GIF"
        }
    }

    var noun: String {
        kind == .gif ? "GIF" : kindName.lowercased()
    }

    var durationText: String? {
        guard let durationSeconds else { return nil }
        let total = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var cellLine: String {
        "\(kindName), \(DisplayDate.text(capturedAt))"
    }

    var viewerLine: String {
        let date = DisplayDate.text(capturedAt)
        if kind == .clip, let durationText {
            return "Clip, \(durationText), from \(date)"
        }
        return "\(kindName) from \(date)"
    }
}
