import SwiftUI

@MainActor
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            CalendarsTab()
                .tabItem { Label("Calendars", systemImage: "calendar") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 760, height: 540)
    }
}
