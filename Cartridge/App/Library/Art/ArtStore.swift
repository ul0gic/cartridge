import Foundation
import os

private enum ArtFetchError: Error {
    case badStatus(Int)
    case notPNG
    case tooLarge
}

private final class ArtDownloads: NSObject, URLSessionDataDelegate, Sendable {
    private struct Pending {
        var data = Data()
        let continuation: CheckedContinuation<Data, any Error>
    }

    private let maxBytes: Int
    private let pending = OSAllocatedUnfairLock(initialState: [Int: Pending]())

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func data(from url: URL, using session: URLSession) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: url)
            pending.withLock { $0[task.taskIdentifier] = Pending(continuation: continuation) }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            finish(dataTask, with: .failure(ArtFetchError.badStatus(status)))
            return .cancel
        }
        if response.expectedContentLength > Int64(maxBytes) {
            finish(dataTask, with: .failure(ArtFetchError.tooLarge))
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceeded = pending.withLock { entries -> Bool in
            entries[dataTask.taskIdentifier]?.data.append(data)
            return (entries[dataTask.taskIdentifier]?.data.count ?? 0) > maxBytes
        }
        if exceeded {
            finish(dataTask, with: .failure(ArtFetchError.tooLarge))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error {
            finish(task, with: .failure(error))
        } else {
            finish(task, with: nil)
        }
    }

    private func finish(_ task: URLSessionTask, with failure: Result<Data, any Error>?) {
        guard let entry = pending.withLock({ $0.removeValue(forKey: task.taskIdentifier) }) else { return }
        entry.continuation.resume(with: failure ?? .success(entry.data))
    }
}

actor ArtStore: ArtProviding {
    private static let maxConcurrentFetches = 4
    private static let maxImageBytes = 4 * 1024 * 1024
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private let library: LibraryStore
    private let session: URLSession
    private let downloads: ArtDownloads
    private var inFlight: [GameID: Task<ArtStatus, Never>] = [:]
    private var outcomes: [GameID: ArtStatus] = [:]
    private var backdropInFlight: [GameID: Task<URL?, Never>] = [:]
    private var backdropMisses = Set<GameID>()
    private var activeFetches = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(library: LibraryStore) {
        self.library = library
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 15
        downloads = ArtDownloads(maxBytes: Self.maxImageBytes)
        session = URLSession(configuration: configuration, delegate: downloads, delegateQueue: nil)
    }

    nonisolated func cachedArtURL(for game: GameRecord) -> URL? {
        let url = StoragePaths.artFile(for: game.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func requestArt(for game: GameRecord) async -> ArtStatus {
        if cachedArtURL(for: game) != nil {
            if game.artStatus != .cached {
                await library.updateArtStatus(.cached, for: game.id)
            }
            return .cached
        }
        if let outcome = outcomes[game.id] {
            return outcome
        }
        if let pending = inFlight[game.id] {
            return await pending.value
        }
        let fetch = Task { await fetch(game) }
        inFlight[game.id] = fetch
        let status = await fetch.value
        inFlight[game.id] = nil
        return status
    }

    nonisolated func cachedBackdropURL(for game: GameRecord) -> URL? {
        let url = StoragePaths.backdropFile(for: game.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func requestBackdrop(for game: GameRecord) async -> URL? {
        if let cached = cachedBackdropURL(for: game) {
            return cached
        }
        if backdropMisses.contains(game.id) {
            return nil
        }
        if let pending = backdropInFlight[game.id] {
            return await pending.value
        }
        let fetch = Task { await fetchBackdrop(game) }
        backdropInFlight[game.id] = fetch
        let url = await fetch.value
        backdropInFlight[game.id] = nil
        return url
    }

    private func fetch(_ game: GameRecord) async -> ArtStatus {
        await acquireSlot()
        defer { releaseSlot() }

        let status: ArtStatus
        do {
            try await store(game, kind: .boxart, at: StoragePaths.artFile(for: game.id))
            status = .cached
        } catch {
            LibraryLog.logger.error(
                "art missing id=\(game.id.rawValue): \(String(describing: error))"
            )
            status = .missing(since: .now)
        }
        outcomes[game.id] = status
        await library.updateArtStatus(status, for: game.id)
        return status
    }

    private func fetchBackdrop(_ game: GameRecord) async -> URL? {
        await acquireSlot()
        defer { releaseSlot() }

        let file = StoragePaths.backdropFile(for: game.id)
        var reasons: [String] = []
        for kind in [ThumbnailKind.snap, .title] {
            do {
                try await store(game, kind: kind, at: file)
                return file
            } catch {
                reasons.append("\(kind.rawValue) \(String(describing: error))")
            }
        }
        LibraryLog.logger.error(
            "art missing id=\(game.id.rawValue) backdrop: \(reasons.joined(separator: ", "))"
        )
        backdropMisses.insert(game.id)
        return nil
    }

    private func store(_ game: GameRecord, kind: ThumbnailKind, at file: URL) async throws {
        let data = try await download(firstOf: ThumbnailURL.candidates(for: game, kind: kind))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    private func download(firstOf urls: [URL]) async throws -> Data {
        var failure: (any Error)?
        for url in urls {
            do {
                return try await download(url)
            } catch {
                failure = error
            }
        }
        throw failure ?? ArtFetchError.notPNG
    }

    private func download(_ url: URL) async throws -> Data {
        let data = try await downloads.data(from: url, using: session)
        guard data.prefix(Self.pngSignature.count).elementsEqual(Self.pngSignature) else { throw ArtFetchError.notPNG }
        return data
    }

    private func acquireSlot() async {
        if activeFetches < Self.maxConcurrentFetches {
            activeFetches += 1
        } else {
            await withCheckedContinuation { waiting.append($0) }
        }
    }

    private func releaseSlot() {
        if waiting.isEmpty {
            activeFetches -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
