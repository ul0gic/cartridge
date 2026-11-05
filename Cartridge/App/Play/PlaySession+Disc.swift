import Foundation

extension PlaySession {
    func changeDisc(to index: Int) async throws {
        guard let connection, index >= 0, index < discCount, case .multiDisc = game.kind else {
            throw PlayError.discChangeFailed
        }
        do {
            try await connection.setDisc(index: index)
        } catch {
            PlayLog.session.error("disc-change-failed \(error.localizedDescription)")
            throw PlayError.discChangeFailed
        }
        discIndex = index
        playRecord.discIndex = index
        await library.recordPlay(playRecord, for: game.id)
    }

    func reset() async {
        do {
            try await connection?.reset()
        } catch {
            PlayLog.session.error("reset-failed \(error.localizedDescription)")
        }
        resume()
    }
}
