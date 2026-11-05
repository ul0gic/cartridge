import Foundation
import os

enum GameDatabaseError: Error {
    case unavailable(GameSystem)
    case unreadable(GameSystem, reason: String)
}

final class GameDatabase: Sendable {
    private struct Table: Decodable, Sendable {
        let byCRC: [String: String]?
        let bySerial: [String: String]?
        let meta: [String: GameMetadata]?
    }

    private let directory: URL?
    private let tables = OSAllocatedUnfairLock(initialState: [GameSystem: Table]())

    init(directory: URL? = nil) {
        self.directory = directory ?? Bundle.main.resourceURL?.appending(path: "Database", directoryHint: .isDirectory)
    }

    func preload() throws {
        for system in GameSystem.allCases {
            _ = try table(for: system)
        }
    }

    func name(system: GameSystem, crc: UInt32) throws -> String? {
        try table(for: system).byCRC?[String(format: "%08X", crc)]
    }

    func name(system: GameSystem, serial: String) throws -> String? {
        try table(for: system).bySerial?[serial]
    }

    func metadata(system: GameSystem, crc: UInt32) throws -> GameMetadata? {
        try table(for: system).meta?[String(format: "%08X", crc)]
    }

    func metadata(system: GameSystem, serial: String) throws -> GameMetadata? {
        try table(for: system).meta?[serial]
    }

    private func table(for system: GameSystem) throws -> Table {
        if let loaded = tables.withLock({ $0[system] }) {
            return loaded
        }
        guard let directory else { throw GameDatabaseError.unavailable(system) }
        let table: Table
        do {
            let data = try Data(contentsOf: directory.appending(
                path: "\(system.rawValue).json",
                directoryHint: .notDirectory
            ))
            table = try JSONDecoder().decode(Table.self, from: data)
        } catch {
            throw GameDatabaseError.unreadable(system, reason: error.localizedDescription)
        }
        tables.withLock { $0[system] = table }
        return table
    }
}
