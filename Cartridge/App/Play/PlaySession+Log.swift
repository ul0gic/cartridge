import Foundation

extension PlaySession {
    func openSessionLog() {
        LogFile.shared.open(LogFile.sessionFile(token: token))
        sessionLogOpen = true
        PlayLog.session.notice(
            """
            session-start game="\(game.title)" system=\(game.system.rawValue) core=\(game.system.coreFileName) \
            token=\(token) \(SystemConditions.build) display-hz=\(SystemConditions.displayHz) \(SystemConditions.power)
            """
        )
    }

    func closeSessionLog(outcome: String) {
        guard sessionLogOpen else { return }
        sessionLogOpen = false
        PlayLog.session.notice(
            """
            session-end outcome=\(outcome) duration-s=\(Self.milliseconds(since: createdAt) / 1000) \
            game="\(game.title)" system=\(game.system.rawValue) \(SystemConditions.power)
            """
        )
        LogFile.shared.close()
    }
}
