import Foundation

enum ProtectedLocations {
    static func location(of url: URL) -> ProtectedLocation? {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser

        func isInside(_ folder: URL) -> Bool {
            let root = folder.standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }

        if isInside(home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)) {
            return .iCloudDrive
        }
        if isInside(home.appending(path: "Desktop", directoryHint: .isDirectory)) {
            return .desktop
        }
        if isInside(home.appending(path: "Documents", directoryHint: .isDirectory)) {
            return .documents
        }
        if isInside(home.appending(path: "Downloads", directoryHint: .isDirectory)) {
            return .downloads
        }

        let keys: Set<URLResourceKey> = [.volumeIsLocalKey, .volumeIsInternalKey, .volumeNameKey]
        guard let values = try? url.resourceValues(forKeys: keys), let name = values.volumeName else { return nil }
        if values.volumeIsLocal == false {
            return .networkVolume(name: name)
        }
        if values.volumeIsInternal == false {
            return .removableVolume(name: name)
        }
        return nil
    }
}
