import SwiftUI

@main
struct JoinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item is an AppKit NSStatusItem (see StatusItemController). SwiftUI still needs
        // one scene; a never-inserted MenuBarExtra keeps the standard Edit menu without adding UI.
        MenuBarExtra("Join!", systemImage: "calendar", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}
