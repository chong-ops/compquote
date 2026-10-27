import SwiftUI

struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    // Set when "Export All Data" runs in Settings. 0 = never.
    @AppStorage("lastBackupExportedAt") private var lastBackupAt: Double = 0

    /// True when there is no backup yet, or the last one is 30+ days old.
    private var backupOverdue: Bool {
        guard lastBackupAt > 0 else { return true }
        let days = Calendar.current.dateComponents([.day], from: Date(timeIntervalSince1970: lastBackupAt), to: Date()).day ?? 0
        return days >= 30
    }

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .readableWidth()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                DocumentsView()
                    .readableWidth()
            }
            .tabItem { Label("Documents", systemImage: "doc.text.fill") }

            NavigationStack {
                ServiceReportsView()
                    .readableWidth()
            }
            .tabItem { Label("Reports", systemImage: "wrench.and.screwdriver.fill") }

            NavigationStack {
                DirectoryView()
                    .readableWidth()
            }
            .tabItem { Label("Directory", systemImage: "person.2.fill") }

            NavigationStack {
                AdminGate {
                    SettingsView()
                        .readableWidth()
                }
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .badge(backupOverdue ? 1 : 0)
        }
        // Lock Settings whenever the app goes to the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AdminAuth.shared.lock() }
        }
        // iPad: shows all five tabs via a sidebar toggle instead of a "more" chevron.
        .tabViewStyle(.sidebarAdaptable)
    }
}
