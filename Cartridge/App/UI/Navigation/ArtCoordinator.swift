import Foundation

enum BackdropSource: Equatable {
    case screenshot(LoadedArt)
    case boxArt(LoadedArt)
    case collage
    case console(GameSystem)

    var id: String {
        switch self {
        case .screenshot(let art): "snap-\(ObjectIdentifier(art).hashValue)"
        case .boxArt(let art): "box-\(ObjectIdentifier(art).hashValue)"
        case .collage: "collage"
        case .console(let system): "console-\(system.rawValue)"
        }
    }
}

struct ArtCoordinator {
    let art: any ArtProviding
    let launchedAt: Date

    func tileArt(for game: GameRecord) async -> TileArt {
        if let loaded = await cachedArt(for: game) {
            return .image(loaded)
        }
        if case .missing(let since) = game.artStatus, since >= launchedAt {
            return .placeholder
        }
        let status = await art.requestArt(for: game)
        if status == .cached, let loaded = await cachedArt(for: game) {
            return .image(loaded)
        }
        return .placeholder
    }

    func ambientColors(for game: GameRecord) async -> AmbientColors {
        if let loaded = await cachedArt(for: game) {
            return .art(loaded.colors, id: game.id.rawValue)
        }
        return .placeholder(title: game.title)
    }

    func backdrop(for game: GameRecord) async -> BackdropSource {
        if let url = art.cachedBackdropURL(for: game), let loaded = await ArtDecoder.load(url) {
            return .screenshot(loaded)
        }
        try? await Task.sleep(for: Motion.ambientDelay)
        guard !Task.isCancelled else { return .collage }
        if let url = await art.requestBackdrop(for: game), let loaded = await ArtDecoder.load(url) {
            return .screenshot(loaded)
        }
        if let loaded = await cachedArt(for: game) {
            return .boxArt(loaded)
        }
        return .collage
    }

    private func cachedArt(for game: GameRecord) async -> LoadedArt? {
        guard let url = art.cachedArtURL(for: game) else { return nil }
        return await ArtDecoder.load(url)
    }
}
