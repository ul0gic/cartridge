import SwiftUI

struct ScanningHero: View {
    let scan: ScanProgress

    var body: some View {
        ScanHero(
            gamesFound: scan.gamesFound,
            filesChecked: scan.filesChecked,
            filesFound: scan.filesFound,
            folderName: scan.folderName,
            folderPath: AppModel.abbreviated(scan.folderPath)
        )
    }
}
