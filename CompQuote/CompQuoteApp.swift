import SwiftUI
import SwiftData

@main
struct CompQuoteApp: App {

    let container: ModelContainer
    @State private var showStoreAlert = false

    init() {
        let schema = Schema([
            Vendor.self,
            Customer.self,
            Product.self,
            Quotation.self,
            LineItem.self,
            PurchaseOrder.self,
            ServiceReport.self,
            Invoice.self
        ])

        // CloudKit sync — syncs across all devices signed into the same iCloud account.
        // To enable: Xcode → Signing & Capabilities → + Capability → iCloud → enable CloudKit.
        // Then set the CloudKit container identifier to match your bundle ID.
        // Sync is an In-App Purchase: CloudKit is only used once it is bought AND
        // switched on in Settings (see SyncStore). Otherwise data stays on this device.
        let useCloudKit = SyncStore.launchedWithCloudKit
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: useCloudKit ? .automatic : .none
        )

        do {
            container = try ModelContainer(for: schema, configurations: config)
            // The container opens even when iCloud isn't really available (no
            // iCloud capability, or not signed in), and then data stays on this
            // device. Only report iCloud when an iCloud account is reachable.
            let iCloudReady = FileManager.default.ubiquityIdentityToken != nil
            let label: String
            if !useCloudKit { label = "Local only (Sync off)" }
            else { label = iCloudReady ? "iCloud (CloudKit)" : "Local only (iCloud not available)" }
            UserDefaults.standard.set(label, forKey: AppStorageKeys.storageMode)
        } catch {
            // CloudKit unavailable (simulator, no iCloud account, or first launch) —
            // fall back to local storage so the app always works.
            print("⚠️ CloudKit unavailable: \(error)")
            print("⚠️ Falling back to local storage.")
            let localConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .none   // the default is .automatic, which fails the same way
            )
            do {
                container = try ModelContainer(for: schema, configurations: localConfig)
                UserDefaults.standard.set("Local only", forKey: AppStorageKeys.storageMode)
            } catch {
                let memConfig = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                container = try! ModelContainer(for: schema, configurations: memConfig)
                UserDefaults.standard.set("Temporary (in-memory)", forKey: AppStorageKeys.storageMode)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .iPadTextScale()
                .onAppear {
                    // Warn the user if we're in memory-only mode
                    if container.configurations.first?.isStoredInMemoryOnly == true {
                        showStoreAlert = true
                    }
                }
                .alert("Storage Issue", isPresented: $showStoreAlert) {
                    Button("OK") {}
                } message: {
                    Text("The app could not open its database. Your data is not lost — go to Settings and tap 'Export All Data' to save a backup, then delete and reinstall the app.")
                }
        }
        .modelContainer(container)
    }
}

// MARK: - Keyboard Dismiss Helper
extension View {
    func dismissKeyboardOnTap() -> some View {
        self.onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        }
    }
}
