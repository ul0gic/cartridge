import Foundation
import os
import Synchronization
import System

enum LogLevel: String, Sendable {
    case debug
    case info
    case notice
    case error

    var osType: OSLogType {
        switch self {
        case .debug: .debug
        case .info: .info
        case .notice: .default
        case .error: .error
        }
    }
}

struct LogChannel: Sendable {
    let category: String
    private let logger: Logger

    init(category: String) {
        self.category = category
        logger = Logger(subsystem: LogFile.subsystem, category: category)
    }

    func debug(_ message: String) {
        log(level: .debug, message)
    }

    func info(_ message: String) {
        log(level: .info, message)
    }

    func notice(_ message: String) {
        log(level: .notice, message)
    }

    func error(_ message: String) {
        log(level: .error, message)
    }

    func log(level: LogLevel, _ message: String) {
        logger.log(level: level.osType, "\(message, privacy: .public)")
        LogFile.shared.append(category: category, level: level, message: message)
    }
}

private struct LogLine: Sendable {
    let time: Date
    let category: String
    let level: LogLevel
    let message: String
}

private enum LogEntry: Sendable {
    case line(LogLine)
    case open(URL)
    case close
}

final class LogFile: Sendable {
    static let subsystem = "io.corelift.Cartridge"
    static let folder = URL.libraryDirectory.appending(path: "Logs/Cartridge", directoryHint: .isDirectory)

    private static let capacity = 1024
    private static let drainSeconds = 0.5

    private let pending: Mutex<[LogEntry]>
    private let dropped = Atomic<Int>(0)
    private let writer: Mutex<LogWriter>

    init(process: String, idleFile: URL?, prunes: Bool) {
        var queue: [LogEntry] = []
        queue.reserveCapacity(Self.capacity)
        var spare: [LogEntry] = []
        spare.reserveCapacity(Self.capacity)
        pending = Mutex(queue)
        writer = Mutex(LogWriter(process: process, idleFile: idleFile, prunes: prunes, spare: spare))
        let thread = Thread { [self] in
            while true {
                Thread.sleep(forTimeInterval: Self.drainSeconds)
                flush()
            }
        }
        thread.name = "io.corelift.Cartridge.log"
        thread.qualityOfService = .utility
        thread.start()
    }

    static func sessionFile(token: String) -> URL {
        folder.appending(path: "session-\(token).log", directoryHint: .notDirectory)
    }

    static func launchFile(prefix: String, at date: Date) -> URL {
        let stamp = Date.ISO8601FormatStyle(timeSeparator: .omitted, timeZone: .current).format(date)
        return folder.appending(path: "\(prefix)-\(stamp).log", directoryHint: .notDirectory)
    }

    func append(category: String, level: LogLevel, message: String) {
        let entry = LogEntry.line(LogLine(time: Date(), category: category, level: level, message: message))
        // Try-lock only: the real-time core thread must never wait on the writer, so a busy queue drops the line.
        let queued = pending.withLockIfAvailable { entries in
            guard entries.count < Self.capacity else { return false }
            entries.append(entry)
            return true
        }
        if queued != true {
            dropped.wrappingAdd(1, ordering: .relaxed)
        }
    }

    func open(_ file: URL) {
        pending.withLock { $0.append(.open(file)) }
    }

    func close() {
        pending.withLock { $0.append(.close) }
    }

    func flush() {
        writer.withLock { drain(&$0) }
    }

    private func drain(_ writer: inout LogWriter) {
        var batch: [LogEntry] = []
        swap(&batch, &writer.spare)
        pending.withLock { swap(&$0, &batch) }
        var text = ""
        for entry in batch {
            switch entry {
            case .line(let line):
                text += writer.format(line)
            case .open(let file):
                writer.write(text)
                text = ""
                writer.session = file
            case .close:
                writer.write(text)
                text = ""
                writer.session = nil
            }
        }
        let lost = dropped.exchange(0, ordering: .relaxed)
        if lost > 0 {
            let line = LogLine(time: Date(), category: "log", level: .error, message: "log-dropped count=\(lost)")
            text += writer.format(line)
        }
        writer.write(text)
        batch.removeAll(keepingCapacity: true)
        writer.spare = batch
    }
}

private struct LogWriter {
    private static let timeStyle = Date.ISO8601FormatStyle(
        timeZoneSeparator: .colon,
        includingFractionalSeconds: true,
        timeZone: .current
    )
    private static let keptFilesPerKind = 30
    private static let folderCapBytes = 50 << 20
    private static let kinds = ["session-", "app-"]
    private static let diagnostics = Logger(subsystem: LogFile.subsystem, category: "log")

    let process: String
    let idleFile: URL?
    let prunes: Bool
    var spare: [LogEntry]
    var session: URL?
    private var openFile: URL?
    private var descriptor: FileDescriptor?
    private var failedFile: URL?

    init(process: String, idleFile: URL?, prunes: Bool, spare: [LogEntry]) {
        self.process = process
        self.idleFile = idleFile
        self.prunes = prunes
        self.spare = spare
    }

    func format(_ line: LogLine) -> String {
        let message = line.message.contains(where: \.isNewline)
            ? line.message.split(whereSeparator: \.isNewline).joined(separator: " ")
            : line.message
        return "\(Self.timeStyle.format(line.time)) \(process) \(line.category) \(line.level.rawValue) \(message)\n"
    }

    mutating func write(_ text: String) {
        guard !text.isEmpty, let target = session ?? idleFile, target != failedFile else { return }
        if target != openFile {
            reopen(target)
        }
        guard let descriptor else { return }
        do {
            _ = try descriptor.writeAll(text.utf8)
        } catch {
            Self.report("log-write-failed", target, error)
            closeDescriptor()
            failedFile = target
        }
    }

    private mutating func reopen(_ target: URL) {
        closeDescriptor()
        openFile = target
        do {
            try FileManager.default.createDirectory(at: LogFile.folder, withIntermediateDirectories: true)
            descriptor = try FileDescriptor.open(
                FilePath(target.path),
                .writeOnly,
                options: [.append, .create, .closeOnExec],
                permissions: .ownerReadWrite
            )
        } catch {
            Self.report("log-open-failed", target, error)
            failedFile = target
            return
        }
        if prunes {
            Self.prune(keeping: target)
        }
    }

    private mutating func closeDescriptor() {
        guard let descriptor else { return }
        self.descriptor = nil
        openFile = nil
        do {
            try descriptor.close()
        } catch {
            Self.report("log-close-failed", nil, error)
        }
    }

    private static func report(_ event: String, _ file: URL?, _ error: any Error) {
        let detail = "\(file?.lastPathComponent ?? "-") \(String(describing: error))"
        diagnostics.error("\(event, privacy: .public) \(detail, privacy: .public)")
    }

    private static func prune(keeping current: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: LogFile.folder, includingPropertiesForKeys: keys)
        } catch {
            Self.report("log-prune-list-failed", nil, error)
            return
        }
        var files: [PrunableFile] = []
        for url in urls where url.pathExtension == "log" && url.lastPathComponent != current.lastPathComponent {
            guard let kind = kinds.first(where: url.lastPathComponent.hasPrefix) else { continue }
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                guard let date = values.contentModificationDate, let size = values.fileSize else { continue }
                files.append(PrunableFile(url: url, kind: kind, date: date, size: size))
            } catch {
                Self.report("log-prune-stat-failed", url, error)
            }
        }
        files.sort { $0.date > $1.date }
        var keptPerKind: [String: Int] = [:]
        if let currentKind = kinds.first(where: current.lastPathComponent.hasPrefix) {
            keptPerKind[currentKind] = 1
        }
        var keptBytes = 0
        for file in files {
            let kept = keptPerKind[file.kind, default: 0]
            guard kept >= keptFilesPerKind || keptBytes + file.size > folderCapBytes else {
                keptPerKind[file.kind] = kept + 1
                keptBytes += file.size
                continue
            }
            do {
                try FileManager.default.removeItem(at: file.url)
            } catch {
                Self.report("log-prune-remove-failed", file.url, error)
            }
        }
    }
}

private struct PrunableFile {
    let url: URL
    let kind: String
    let date: Date
    let size: Int
}
