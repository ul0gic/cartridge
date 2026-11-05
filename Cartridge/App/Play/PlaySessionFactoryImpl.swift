@MainActor
final class PlaySessionFactoryImpl: PlaySessionFactory {
    private let library: any LibraryStoring

    init(library: any LibraryStoring) {
        self.library = library
    }

    func makeSession(
        for game: GameRecord,
        playRecord: PlayRecord?,
        withoutBIOS: Bool,
        start: SessionStart,
        look: DisplayLook
    ) -> any PlaySessionControlling {
        PlaySession(
            game: game,
            playRecord: playRecord,
            withoutBIOS: withoutBIOS,
            start: start,
            look: look,
            library: library
        )
    }
}
