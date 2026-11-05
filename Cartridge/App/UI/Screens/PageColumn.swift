import SwiftUI

extension View {
    func pageColumn(width: CGFloat = Layout.panelBodyMax) -> some View {
        frame(maxWidth: width, alignment: .leading)
            .padding(.leading, Layout.marginX)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct WallBackdrop: View {
    var body: some View {
        ZStack {
            CollageBackdrop()
        }
    }
}
