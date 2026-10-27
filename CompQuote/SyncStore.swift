import SwiftUI
import Combine
import StoreKit
import CoreData
import SwiftData

/// In-App Purchase that unlocks CompQuote Pro (non-consumable): iCloud Sync and Invoices.
/// The product ID keeps its original "sync" name, so the product already created in
/// App Store Connect keeps working. Only its display name and description change.
///
/// The SwiftData container is built once at launch, so the purchase state and the
/// on/off switch are cached in UserDefaults and read synchronously in
/// `CompQuoteApp.init`. Changing either takes effect the next time the app opens.
@MainActor
final class SyncStore: ObservableObject {

    /// Must match the Product ID you create in App Store Connect.
    static let productID = "com.macdirection.compquote.sync"

    static let shared = SyncStore()

    nonisolated private static let unlockedKey = "syncPurchased"
    nonisolated private static let enabledKey  = "syncEnabled"

    /// Read at launch (nonisolated so the App initializer can call it).
    nonisolated static var shouldUseCloudKit: Bool {
        let d = UserDefaults.standard
        return d.bool(forKey: unlockedKey) && d.bool(forKey: enabledKey)
    }

    /// What the running container was built with (captured once, at first access).
    nonisolated static let launchedWithCloudKit: Bool = shouldUseCloudKit

    @Published private(set) var isUnlocked: Bool
    @Published var syncEnabled: Bool {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: Self.enabledKey) }
    }
    @Published private(set) var product: StoreKit.Product?
    @Published private(set) var isBusy = false
    @Published var message: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        isUnlocked  = UserDefaults.standard.bool(forKey: Self.unlockedKey)
        syncEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// True when the switch (or purchase) no longer matches the running container.
    var needsRestart: Bool {
        (isUnlocked && syncEnabled) != Self.launchedWithCloudKit
    }

    // MARK: - Lifecycle

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let t) = result, t.productID == SyncStore.productID {
                    await t.finish()
                    self?.handle(t)
                }
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    func loadProduct() async {
        do {
            product = try await StoreKit.Product.products(for: [Self.productID]).first
        } catch {
            product = nil
        }
    }

    /// Only ever turns access ON from here. An empty answer from StoreKit (offline,
    /// not ready yet, or a test environment) must never lock a paying user out.
    func refreshEntitlement() async {
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == Self.productID,
               t.revocationDate == nil {
                setUnlocked(true)
                return
            }
        }
    }

    /// Access is removed only when Apple says the purchase was refunded or revoked.
    func handle(_ transaction: StoreKit.Transaction) {
        guard transaction.productID == Self.productID else { return }
        setUnlocked(transaction.revocationDate == nil)
    }

    private func setUnlocked(_ value: Bool) {
        isUnlocked = value
        UserDefaults.standard.set(value, forKey: Self.unlockedKey)
        if !value { syncEnabled = false }
    }

    // MARK: - Actions

    /// `enableSync: false` is for buying Pro to use Invoices: sync then stays off
    /// until the person turns it on in Settings.
    func purchase(enableSync: Bool = true) async {
        guard let product else {
            message = "The store isn't available right now. Please try again later."
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    setUnlocked(true)
                    if enableSync { syncEnabled = true }   // turned on straight after purchase
                } else {
                    message = "The purchase couldn't be verified."
                }
            case .pending:
                message = "Purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func restore(enableSync: Bool = true) async {
        isBusy = true
        defer { isBusy = false }
        try? await AppStore.sync()
        await refreshEntitlement()
        if isUnlocked {
            if enableSync { syncEnabled = true }
        } else {
            message = "No previous purchase was found for this Apple ID."
        }
    }
}


// MARK: - Sync activity (last sync time / errors)

/// Listens to CloudKit's own activity notifications so Settings can show what is happening.
@MainActor
final class SyncMonitor: ObservableObject {
    static let shared = SyncMonitor()

    private static let lastSuccessKey = "syncLastSuccessDate"
    @Published private(set) var lastSuccess: Date? = UserDefaults.standard.object(forKey: SyncMonitor.lastSuccessKey) as? Date
    @Published private(set) var lastError: String?
    @Published private(set) var isSyncing = false

    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            isSyncing = true
            return
        }
        isSyncing = false
        if event.succeeded {
            lastSuccess = event.endDate
            UserDefaults.standard.set(event.endDate, forKey: Self.lastSuccessKey)
            lastError = nil
        } else if let error = event.error {
            lastError = error.localizedDescription
        }
    }
}

// MARK: - Settings section

struct SyncSettingsSection: View {
    @StateObject private var store = SyncStore.shared
    @StateObject private var monitor = SyncMonitor.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showError = false
    @State private var requestedAt: Date?

    var body: some View {
        Section {
            if store.isUnlocked {
                HStack {
                    Label("Invoices", systemImage: "doc.text.fill")
                    Spacer()
                    Text("Unlocked")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Toggle(isOn: $store.syncEnabled) {
                    Label("Turn On iCloud Sync", systemImage: "icloud.fill")
                }
                if store.syncEnabled && SyncStore.launchedWithCloudKit {
                    HStack {
                        Text("Status")
                        Spacer()
                        if monitor.isSyncing {
                            ProgressView()
                        } else if let error = monitor.lastError {
                            Text(error).font(.caption).foregroundColor(.red)
                                .multilineTextAlignment(.trailing)
                        } else if let last = monitor.lastSuccess {
                            Text("Last sync " + last.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline).foregroundColor(.secondary)
                        } else {
                            Text("No sync yet")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    Button {
                        // Saving pushes pending changes to iCloud right away.
                        try? modelContext.save()
                        requestedAt = Date()
                        store.message = "Sync requested. Your changes are uploading. Changes from your other devices arrive automatically while the app is open."
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                if store.needsRestart {
                    Label(store.syncEnabled
                          ? "Close and reopen CompQuote to start syncing."
                          : "Close and reopen CompQuote to stop syncing.",
                          systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            } else {
                Button {
                    Task { await store.purchase() }
                } label: {
                    HStack {
                        Label("Unlock CompQuote Pro", systemImage: "star.circle.fill")
                        Spacer()
                        if store.isBusy {
                            ProgressView()
                        } else {
                            Text(store.product?.displayPrice ?? "—")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .disabled(store.isBusy || store.product == nil)

                Button("Restore Purchase") {
                    Task { await store.restore() }
                }
                .disabled(store.isBusy)
            }
        } header: {
            SettingsSectionHeader(icon: "star.circle", title: "CompQuote Pro")
        } footer: {
            Text(store.isUnlocked
                 ? "Invoices are unlocked. iCloud Sync keeps quotations, purchase orders, invoices, reports and directory in step across your devices signed into the same iCloud account. Export a backup before turning it on for the first time."
                 : "One-time purchase. Unlocks Invoices (bill the delivered items of a quotation) and iCloud Sync across your iPhone, iPad and Mac through your own iCloud account.")
        }
        .onAppear { store.start() }
        .onChange(of: store.message) { _, new in showError = new != nil }
        .alert("CompQuote Pro", isPresented: $showError) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}

// MARK: - Upgrade sheet
// Shown when a Pro feature (Invoices) is used before CompQuote Pro is bought.
struct ProUpgradeSheet: View {
    /// Close the sheet by itself once the purchase goes through.
    /// The invoice flow turns this off and swaps to the invoice form instead.
    var dismissWhenUnlocked: Bool = true

    @ObservedObject private var store = SyncStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.indigo)
                        .padding(.top, 20)

                    VStack(spacing: 6) {
                        Text("CompQuote Pro").font(.title.bold())
                        Text("One purchase. Yours for good.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        benefit(icon: "doc.text.fill", color: .indigo, title: "Invoices",
                                text: "Turn delivered quotation items into invoices, bill in parts, and share them as PDF.")
                        benefit(icon: "icloud.fill", color: .blue, title: "iCloud Sync",
                                text: "Keep your data in step across iPhone, iPad and Mac through your own iCloud account.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 12) {
                        Button {
                            Task { await store.purchase(enableSync: false) }
                        } label: {
                            HStack {
                                Text("Unlock CompQuote Pro")
                                Spacer()
                                if store.isBusy {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(store.product?.displayPrice ?? "—")
                                }
                            }
                            .fontWeight(.semibold)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(store.isBusy || store.product == nil)

                        Button("Restore Purchase") {
                            Task { await store.restore(enableSync: false) }
                        }
                        .disabled(store.isBusy)

                        if store.product == nil && !store.isBusy {
                            Text("The store isn't reachable right now. Check your connection and try again later.")
                                .font(.footnote).foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        if let message = store.message {
                            Text(message)
                                .font(.footnote).foregroundColor(.orange)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Text("Quotations, purchase orders and service reports always stay free.")
                        .font(.footnote).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 16)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "pro-close", placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                store.message = nil
                store.start()
            }
            .onDisappear { store.message = nil }
            .onChange(of: store.isUnlocked) { _, unlocked in
                if unlocked && dismissWhenUnlocked { dismiss() }
            }
        }
    }

    private func benefit(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
