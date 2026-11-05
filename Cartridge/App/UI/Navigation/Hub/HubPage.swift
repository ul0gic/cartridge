import Foundation

enum RestartReason {
    case restore
    case importSave

    var logName: String {
        switch self {
        case .restore: "restore"
        case .importSave: "import"
        }
    }
}

enum HubCardID: Hashable {
    case resume
    case fastForward
    case saveStates
    case cheats
    case saveFile
    case display
    case changeDisc
    case reset
    case quit
}

enum HubPageExit {
    case main(highlight: HubCardID)
    case restart(RestartReason)
}

@MainActor
struct HubContext {
    let session: any PlaySessionControlling
    let dependencies: AppDependencies
    let cheats: SessionCheats
    let messages: HubMessageBox
    let exit: (HubPageExit) -> Void
    let confirmName: () -> String
    let chooseSaveFile: (_ message: String) async -> URL?
}

@MainActor
protocol HubPage: AnyObject {
    var title: String { get }
    var subtitle: String { get }
    var hints: [Hint] { get }
    var counter: String? { get }

    func handle(_ event: NavigationEvent)
}

@MainActor
enum HubPageModel {
    case states(SaveStatesPage)
    case cheats(CheatsPage)
    case file(SaveFilePage)
    case display(DisplayPage)
    case disc(DiscPage)

    var base: any HubPage {
        switch self {
        case .states(let page): page
        case .cheats(let page): page
        case .file(let page): page
        case .display(let page): page
        case .disc(let page): page
        }
    }
}
