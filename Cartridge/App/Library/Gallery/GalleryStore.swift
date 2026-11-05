import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class GalleryStore: GalleryStoring {
    nonisolated private static let indexVersion = 1

    private(set) var items: [CaptureItem] = []

    @ObservationIgnored private var reservedNames: Set<String> = []
    @ObservationIgnored private let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    func load() async {
        await Self.removePartialWork()
        do {
            items = try await Self.readIndex().sorted { $0.capturedAt > $1.capturedAt }
        } catch {
            GalleryLog.logger.error("index unreadable: \(error.localizedDescription)")
            await Self.setAsideIndex()
            items = []
        }
    }

    func url(of item: CaptureItem) -> URL {
        StoragePaths.gallery.appending(path: item.fileName, directoryHint: .notDirectory)
    }

    func newFileURL(kind: CaptureKind, gameTitle: String, capturedAt: Date) -> URL {
        let title = gameTitle.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let stem = "\(title) \(stampFormatter.string(from: capturedAt))"
        var name = "\(stem).\(kind.fileExtension)"
        var attempt = 2
        while isTaken(name) {
            name = "\(stem) \(attempt).\(kind.fileExtension)"
            attempt += 1
        }
        reservedNames.insert(name)
        do {
            try FileManager.default.createDirectory(at: StoragePaths.gallery, withIntermediateDirectories: true)
        } catch {
            GalleryLog.logger.error("gallery folder failed: \(error.localizedDescription)")
        }
        return StoragePaths.gallery.appending(path: name, directoryHint: .notDirectory)
    }

    func add(_ item: CaptureItem) throws(GalleryError) {
        let position = items.firstIndex { $0.capturedAt <= item.capturedAt } ?? items.endIndex
        items.insert(item, at: position)
        reservedNames.remove(item.fileName)
        do {
            try persist()
        } catch {
            items.remove(at: position)
            throw error
        }
    }

    func delete(_ id: UUID) throws(GalleryError) {
        guard let position = items.firstIndex(where: { $0.id == id }) else { return }
        do {
            try FileManager.default.removeItem(at: url(of: items[position]))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            GalleryLog.logger.info("delete: file already gone")
        } catch {
            GalleryLog.logger.error("delete failed: \(error.localizedDescription)")
            throw GalleryError.writeFailed
        }
        let removed = items.remove(at: position)
        do {
            try persist()
        } catch {
            items.insert(removed, at: position)
            throw error
        }
    }

    func makeGIF(from id: UUID) async throws(GalleryError) -> CaptureItem {
        guard let source = items.first(where: { $0.id == id }) else { throw GalleryError.missingFile }
        guard source.kind == .clip else { throw GalleryError.notAClip }
        let clip = url(of: source)
        guard FileManager.default.fileExists(atPath: clip.path) else { throw GalleryError.missingFile }

        let started = ContinuousClock.now
        let capturedAt = Date.now
        let destination = newFileURL(kind: .gif, gameTitle: source.gameTitle, capturedAt: capturedAt)
        let work = StoragePaths.galleryPartial
            .appending(path: "\(UUID().uuidString).gif", directoryHint: .notDirectory)
        do {
            try prepareWorkFolder()
            let output = try await GIFMaker.write(clip: clip, to: work)
            try move(work, to: destination)
            let item = CaptureItem(
                id: UUID(),
                kind: .gif,
                fileName: destination.lastPathComponent,
                gameID: source.gameID,
                gameTitle: source.gameTitle,
                capturedAt: capturedAt,
                pixelWidth: output.pixelWidth,
                pixelHeight: output.pixelHeight,
                durationSeconds: output.durationSeconds
            )
            try add(item)
            let milliseconds = Int(started.duration(to: .now) / .milliseconds(1))
            GalleryLog.logger.info("gif-made ms=\(milliseconds) frames=\(output.frames)")
            return item
        } catch {
            discardFile(at: work)
            discardFile(at: destination)
            reservedNames.remove(destination.lastPathComponent)
            throw error
        }
    }

    func revealInFinder(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url(of: item)])
    }

    private func isTaken(_ name: String) -> Bool {
        reservedNames.contains(name)
            || items.contains { $0.fileName == name }
            || FileManager.default.fileExists(atPath: StoragePaths.gallery.appending(path: name).path)
    }

    private func persist() throws(GalleryError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(GalleryIndexFile(version: Self.indexVersion, items: items))
            try FileManager.default.createDirectory(at: StoragePaths.gallery, withIntermediateDirectories: true)
            try data.write(to: StoragePaths.galleryIndex, options: .atomic)
        } catch {
            GalleryLog.logger.error("index write failed: \(error.localizedDescription)")
            let isDiskFull = (error as? CocoaError)?.code == .fileWriteOutOfSpace
            throw isDiskFull ? GalleryError.diskFull : GalleryError.writeFailed
        }
    }

    private func prepareWorkFolder() throws(GalleryError) {
        do {
            try FileManager.default.createDirectory(at: StoragePaths.galleryPartial, withIntermediateDirectories: true)
        } catch {
            GalleryLog.logger.error("work folder failed: \(error.localizedDescription)")
            throw GalleryError.writeFailed
        }
    }

    private func move(_ source: URL, to destination: URL) throws(GalleryError) {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            GalleryLog.logger.error("gif move failed: \(error.localizedDescription)")
            throw GalleryError.writeFailed
        }
    }

    private func discardFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            GalleryLog.logger.error("cleanup failed: \(error.localizedDescription)")
        }
    }

    @concurrent
    private static func readIndex() async throws -> [CaptureItem] {
        guard FileManager.default.fileExists(atPath: StoragePaths.galleryIndex.path) else { return [] }
        let data = try Data(contentsOf: StoragePaths.galleryIndex)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(GalleryIndexFile.self, from: data)
        guard file.version == indexVersion else { throw GalleryError.unsupportedIndexVersion }
        return file.items
    }

    @concurrent
    private static func setAsideIndex() async {
        let aside = StoragePaths.gallery.appending(path: "gallery.unreadable.json", directoryHint: .notDirectory)
        do {
            if FileManager.default.fileExists(atPath: aside.path) {
                try FileManager.default.removeItem(at: aside)
            }
            try FileManager.default.moveItem(at: StoragePaths.galleryIndex, to: aside)
        } catch {
            GalleryLog.logger.error("index set aside failed: \(error.localizedDescription)")
        }
    }

    @concurrent
    private static func removePartialWork() async {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: StoragePaths.galleryPartial.path) else { return }
        do {
            let leftovers = try fileManager.contentsOfDirectory(
                at: StoragePaths.galleryPartial,
                includingPropertiesForKeys: nil
            )
            for leftover in leftovers {
                try fileManager.removeItem(at: leftover)
            }
        } catch {
            GalleryLog.logger.error("partial cleanup failed: \(error.localizedDescription)")
        }
    }
}
