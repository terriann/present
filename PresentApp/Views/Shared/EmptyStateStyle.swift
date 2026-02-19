import SwiftUI

extension View {
    func emptyStateStyle() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 40)
    }
}
