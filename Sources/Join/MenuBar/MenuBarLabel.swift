import SwiftUI

@MainActor
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let title = model.menuBarTitle {
            Label(title, systemImage: "calendar")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "calendar")
        }
    }
}
