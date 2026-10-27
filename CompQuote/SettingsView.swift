import SwiftUI
import SwiftData
import PhotosUI

struct SettingsView: View {
    @AppStorage(AppStorageKeys.selectedPDFLayout) private var selectedPDFLayout = "Corporate Blue (Standard)"
    @AppStorage(AppStorageKeys.companyName) private var companyName = "Computech Solutions"
    @AppStorage(AppStorageKeys.companyAddress) private var companyAddress = "123 Tech St, Silicon Valley"
    @AppStorage(AppStorageKeys.companyContact) private var companyContact = "ops@computech.com"
    @AppStorage(AppStorageKeys.companyTagline) private var companyTagline = "Apple Education Reseller • Your Mac environment expert"
    @AppStorage(AppStorageKeys.defaultBankAccount) private var bankAccount = ""
    @AppStorage(AppStorageKeys.defaultRemarks) private var defaultRemarks = ""
    @AppStorage(AppStorageKeys.showCompanyLogo) private var showCompanyLogo = true
    @AppStorage(AppStorageKeys.uploadedLogoData) private var uploadedLogoData: Data?
    @AppStorage(AppStorageKeys.quotationTitle) private var quotationTitle = "QUOTATION"
    @AppStorage(AppStorageKeys.poTitle) private var poTitle = "PURCHASE ORDER"
    @AppStorage(AppStorageKeys.serviceReportTitle) private var serviceReportTitle = "SERVICE REPORT"
    @AppStorage(AppStorageKeys.invoiceTitle) private var invoiceTitle = "INVOICE"
    @AppStorage(AppStorageKeys.defaultPORemarks) private var defaultPORemarks = ""
    @AppStorage(AppStorageKeys.defaultPODeliveryInstructions) private var defaultPODeliveryInstructions = ""
    @AppStorage(AppStorageKeys.defaultPaymentTerm) private var defaultPaymentTerm = ""
    @AppStorage(AppStorageKeys.quotationNumberPrefix) private var quotationNumberPrefix = ""
    @AppStorage(AppStorageKeys.poNumberPrefix) private var poNumberPrefix = ""
    @AppStorage(AppStorageKeys.reportNumberPrefix) private var reportNumberPrefix = ""
    @AppStorage(AppStorageKeys.invoiceNumberPrefix) private var invoiceNumberPrefix = ""

    @State private var pickedItem: PhotosPickerItem?
    @State private var displayImage: UIImage?
    @State private var showPhotosPicker = false
    @State private var selectedTab = 0
    @State private var showImportView = false
    @State private var showRestorePicker = false
    @State private var showRestoreOptions = false
    @State private var pendingRestoreURL: URL? = nil
    @State private var restoreMessage = ""
    @State private var showClearCustomers = false
    @State private var showClearVendors = false
    @State private var showClearProducts = false
    @State private var showRemoveDuplicates = false
    @State private var duplicateSummary = ""
    @State private var showNoDuplicates = false
    @State private var showDangerPIN = false
    @State private var pendingDangerAction: (() -> Void)? = nil
    @State private var showChangePIN = false
    @State private var backupToShare: IdentifiableURL? = nil
    @AppStorage(AppStorageKeys.storageMode) private var storageMode = "Local only"
    // When "Export All Data" last produced a file. 0 = never. Used for the backup reminder.
    @AppStorage("lastBackupExportedAt") private var lastBackupAt: Double = 0
    @StateObject private var auth = AdminAuth.shared
    @FocusState private var anyFocused: Bool

    @Environment(\.modelContext) private var modelContext
    @Query private var customers: [Customer]
    @Query private var vendors: [Vendor]
    @Query private var products: [Product]
    @Query private var quotations: [Quotation]
    @Query private var purchaseOrders: [PurchaseOrder]
    @Query private var serviceReports: [ServiceReport]
    @Query private var invoices: [Invoice]

    private let tabs: [(label: String, icon: String)] = [
        ("Profile",   "building.2"),
        ("Documents", "doc.text"),
        ("Branding",  "paintpalette")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // ── Custom Tab Bar ────────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = i }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tabs[i].icon)
                                .font(.system(size: 18, weight: selectedTab == i ? .semibold : .regular))
                            Text(tabs[i].label)
                                .font(.system(size: 11, weight: selectedTab == i ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(selectedTab == i ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.systemGroupedBackground))
            .overlay(
                // Active tab indicator
                GeometryReader { geo in
                    let w = geo.size.width / CGFloat(tabs.count)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: w, height: 2)
                        .offset(x: w * CGFloat(selectedTab))
                        .animation(.easeInOut(duration: 0.2), value: selectedTab)
                },
                alignment: .bottom
            )

            Divider()

            // ── Tab Content ───────────────────────────────────────────────
            TabView(selection: $selectedTab) {
                profileTab.contentMargins(.bottom, 100, for: .scrollContent).tag(0)
                documentsTab.contentMargins(.bottom, 100, for: .scrollContent).tag(1)
                brandingTab.contentMargins(.bottom, 100, for: .scrollContent).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { anyFocused = false }
            }
        }
        .onAppear {
            if let data = uploadedLogoData { displayImage = UIImage(data: data) }
        }
        .sheet(isPresented: $showImportView) { ProductImportView() }
        .photosPicker(isPresented: $showPhotosPicker, selection: $pickedItem,
                      matching: .images, photoLibrary: .shared())
        .fileImporter(isPresented: $showRestorePicker,
                      allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                pendingRestoreURL = url
                showRestoreOptions = true
            }
        }
        .confirmationDialog("Restore from Backup", isPresented: $showRestoreOptions, titleVisibility: .visible) {
            Button("Merge — Keep existing + add from backup") {
                if let url = pendingRestoreURL { restoreBackup(from: url, replace: false) }
            }
            Button("Replace — Clear all data then restore", role: .destructive) {
                if let url = pendingRestoreURL { restoreBackup(from: url, replace: true) }
            }
            Button("Cancel", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("Merge adds missing records. Replace deletes everything first. Both cannot be undone.")
        }
        .alert("Restore Complete", isPresented: .constant(!restoreMessage.isEmpty)) {
            Button("OK") { restoreMessage = "" }
        } message: { Text(restoreMessage) }
        .sheet(isPresented: $showDangerPIN) {
            PINEntryView(
                title: "Confirm Admin PIN",
                subtitle: "Re-enter your PIN to proceed",
                onSuccess: {
                    showDangerPIN = false
                    pendingDangerAction?()
                    pendingDangerAction = nil
                },
                onCancel: {
                    showDangerPIN = false
                    pendingDangerAction = nil
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showChangePIN) {
            ChangePINFlow(
                onDone: { showChangePIN = false },
                onCancel: { showChangePIN = false }
            )
            .interactiveDismissDisabled()
        }
        .sheet(item: $backupToShare) { wrapped in
            ActivityShareSheet(items: [wrapped.url])
        }
        .confirmationDialog("Delete all \(customers.count) customers?",
                            isPresented: $showClearCustomers, titleVisibility: .visible) {
            Button("Delete All Customers", role: .destructive) {
                customers.forEach { modelContext.delete($0) }
                try? modelContext.save()
            }
        } message: { Text("This cannot be undone. Export a backup first if needed.") }
        .confirmationDialog("Delete all \(vendors.count) vendors?",
                            isPresented: $showClearVendors, titleVisibility: .visible) {
            Button("Delete All Vendors", role: .destructive) {
                vendors.forEach { modelContext.delete($0) }
                try? modelContext.save()
            }
        } message: { Text("This cannot be undone. Export a backup first if needed.") }
        .confirmationDialog("Delete all \(products.count) products?",
                            isPresented: $showClearProducts, titleVisibility: .visible) {
            Button("Delete All Products", role: .destructive) {
                products.forEach { modelContext.delete($0) }
                try? modelContext.save()
            }
        } message: { Text("This cannot be undone. Export a backup first if needed.") }
        .confirmationDialog("Remove duplicates?",
                            isPresented: $showRemoveDuplicates, titleVisibility: .visible) {
            Button("Remove Duplicates", role: .destructive) { removeDuplicates() }
        } message: {
            Text("\(duplicateSummary)\n\nOne copy of each is kept. With iCloud Sync on, the removal spreads to your other devices. Export a backup first.")
        }
        .alert("No Duplicates Found", isPresented: $showNoDuplicates) {
            Button("OK") {}
        } message: { Text("Every customer, vendor, product and document is already unique.") }
        .onChange(of: pickedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let rawData = try? await newItem.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        uploadedLogoData = rawData
                        displayImage = UIImage(data: rawData)
                    }
                }
            }
        }
    }

    // MARK: - Remove duplicates (e.g. after two devices both uploaded the same data)

    private struct DuplicatePlan {
        var customers: [Customer] = []
        var vendors: [Vendor] = []
        var products: [Product] = []
        var quotations: [Quotation] = []
        var purchaseOrders: [PurchaseOrder] = []
        var reports: [ServiceReport] = []
        var invoices: [Invoice] = []

        var total: Int {
            customers.count + vendors.count + products.count
            + quotations.count + purchaseOrders.count + reports.count + invoices.count
        }
        var summary: String {
            let entries: [(name: String, count: Int)] = [
                ("customers", customers.count),
                ("vendors", vendors.count),
                ("products", products.count),
                ("quotations", quotations.count),
                ("purchase orders", purchaseOrders.count),
                ("service reports", reports.count),
                ("invoices", invoices.count)
            ]
            let descriptions: [String] = entries.compactMap { entry in
                guard entry.count > 0 else { return nil }
                return "\(entry.count) \(entry.name)"
            }
            return descriptions.joined(separator: ", ")
        }
    }

    private func normalized(_ parts: String...) -> String {
        let joined = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "|")
        return parts.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ? "" : joined
    }

    /// Returns the extra copies. The copy with the highest score is kept; ties keep the first.
    private func extras<T>(_ items: [T], key: (T) -> String, score: (T) -> Int = { _ in 0 }) -> [T] {
        var kept: [String: T] = [:]
        var result: [T] = []
        for item in items {
            let k = key(item)
            if k.isEmpty { continue }          // never merge records with no identifying data
            if let current = kept[k] {
                if score(item) > score(current) {
                    result.append(current)
                    kept[k] = item
                } else {
                    result.append(item)
                }
            } else {
                kept[k] = item
            }
        }
        return result
    }

    private func duplicatePlan() -> DuplicatePlan {
        var plan = DuplicatePlan()
        plan.customers = extras(customers) { normalized($0.name, $0.company, $0.contactNumber, $0.address) }
        plan.vendors = extras(vendors) { normalized($0.name, $0.company, $0.contactNumber) }
        plan.products = extras(products) { normalized($0.itemCode) }
        plan.quotations = extras(quotations, key: { normalized($0.quoteNumber) }, score: { $0.items.count })
        plan.purchaseOrders = extras(purchaseOrders, key: { normalized($0.poNumber) }, score: { $0.items.count })
        plan.reports = extras(serviceReports) { normalized($0.reportNumber) }
        plan.invoices = extras(invoices, key: { normalized($0.invoiceNumber) }, score: { $0.items.count })
        return plan
    }

    private func removeDuplicates() {
        let plan = duplicatePlan()
        // Quotation items that point at a duplicate invoice are moved to the copy that stays.
        for dup in plan.invoices {
            let key = normalized(dup.invoiceNumber)
            guard let keeper = invoices.first(where: { inv in
                normalized(inv.invoiceNumber) == key && !plan.invoices.contains(where: { $0 === inv })
            }) else { continue }
            let oldId = dup.id.uuidString
            let descriptor = FetchDescriptor<LineItem>(predicate: #Predicate { $0.invoiceId == oldId })
            if let billed = try? modelContext.fetch(descriptor) {
                for item in billed { item.invoiceId = keeper.id.uuidString }
            }
        }
        plan.invoices.forEach { modelContext.delete($0) }
        plan.customers.forEach { modelContext.delete($0) }
        plan.vendors.forEach { modelContext.delete($0) }
        plan.products.forEach { modelContext.delete($0) }
        plan.quotations.forEach { modelContext.delete($0) }
        plan.purchaseOrders.forEach { modelContext.delete($0) }
        plan.reports.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // MARK: - Tab 1: Profile
    var profileTab: some View {
        Form {
            // Company card
            Section {
                LabeledField(icon: "building.2", color: .blue, label: "Company Name") {
                    TextField("My Company", text: $companyName).focused($anyFocused)
                }
                LabeledField(icon: "location", color: .orange, label: "Address") {
                    TextField("Street, City", text: $companyAddress).focused($anyFocused)
                }
                LabeledField(icon: "phone", color: .green, label: "Contact / Email") {
                    TextField("phone or email", text: $companyContact).focused($anyFocused)
                }
                LabeledField(icon: "quote.bubble", color: .indigo, label: "PDF Footer Tagline") {
                    TextField("Your tagline", text: $companyTagline).focused($anyFocused)
                }
                LabeledField(icon: "creditcard", color: .purple, label: "Bank Account") {
                    TextField("Account number", text: $bankAccount)
                        .autocorrectionDisabled()
                        .focused($anyFocused)
                }
            } header: {
                SettingsSectionHeader(icon: "person.crop.square", title: "Business Profile")
            }

            SyncSettingsSection()

            // Data summary card
            Section {
                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(value: "\(quotations.count)",     label: "Quotes",    color: .blue)
                    StatCard(value: "\(purchaseOrders.count)", label: "POs",       color: .green)
                    StatCard(value: "\(invoices.count)",       label: "Invoices",  color: .indigo)
                    StatCard(value: "\(serviceReports.count)", label: "Reports",   color: .orange)
                    StatCard(value: "\(customers.count)",      label: "Customers", color: .purple)
                    StatCard(value: "\(products.count)",       label: "Products",  color: .teal)
                }
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
                .padding(.vertical, 4)

                // Storage / iCloud sync status (recorded at launch in CompQuoteApp)
                HStack {
                    Image(systemName: storageMode.hasPrefix("iCloud") ? "icloud.fill" : "icloud.slash")
                        .foregroundColor(storageMode.hasPrefix("iCloud") ? .blue : .orange)
                    Text("Storage")
                    Spacer()
                    Text(storageMode)
                        .font(.subheadline).foregroundColor(.secondary)
                }

                backupStatusRow

                Button {
                    // Generated on demand — serializing the whole database in
                    // the view body would run on every render.
                    if let url = exportBackup() {
                        lastBackupAt = Date().timeIntervalSince1970
                        backupToShare = IdentifiableURL(url: url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.doc.fill")
                            .foregroundColor(.blue)
                        Text("Export All Data (JSON)")
                            .foregroundColor(.blue)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                Button {
                    showImportView = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.down.fill").foregroundColor(.green)
                        Text("Import Products / Customers / Vendors").foregroundColor(.green)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }

                Button {
                    showRestorePicker = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise.circle.fill").foregroundColor(.orange)
                        Text("Restore from Backup (JSON)").foregroundColor(.orange)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }

                Button {
                    let plan = duplicatePlan()
                    if plan.total == 0 {
                        showNoDuplicates = true
                    } else {
                        duplicateSummary = plan.summary
                        pendingDangerAction = { showRemoveDuplicates = true }
                        showDangerPIN = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.stack.badge.minus").foregroundColor(.purple)
                        Text("Remove Duplicates").foregroundColor(.purple)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            } header: {
                SettingsSectionHeader(icon: "cylinder", title: "Data Management")
            }

            // Danger zone — bulk delete
            Section {
                Button(role: .destructive) {
                    pendingDangerAction = { showClearCustomers = true }
                    showDangerPIN = true
                } label: {
                    HStack {
                        Image(systemName: "person.2.slash").foregroundColor(.red)
                        Text("Delete All Customers (\(customers.count))")
                        Spacer()
                    }
                }
                .disabled(customers.isEmpty)

                Button(role: .destructive) {
                    pendingDangerAction = { showClearVendors = true }
                    showDangerPIN = true
                } label: {
                    HStack {
                        Image(systemName: "building.2").foregroundColor(.red)
                        Text("Delete All Vendors (\(vendors.count))")
                        Spacer()
                    }
                }
                .disabled(vendors.isEmpty)

                Button(role: .destructive) {
                    pendingDangerAction = { showClearProducts = true }
                    showDangerPIN = true
                } label: {
                    HStack {
                        Image(systemName: "shippingbox").foregroundColor(.red)
                        Text("Delete All Products (\(products.count))")
                        Spacer()
                    }
                }
                .disabled(products.isEmpty)

                // Change PIN option — verifies the current PIN first
                Button {
                    showChangePIN = true
                } label: {
                    HStack {
                        Image(systemName: "lock.rotation").foregroundColor(.orange)
                        Text("Change Admin PIN")
                        Spacer()
                    }
                }
            } header: {
                SettingsSectionHeader(icon: "trash", title: "Danger Zone")
            } footer: {
                Text("Use before reimporting to clear bad data. This cannot be undone.")
            }
        }
    }

    // MARK: - Tab 2: Documents
    var documentsTab: some View {
        Form {
            Section {
                TitledTextField(label: "Quotation", placeholder: "e.g. INVOICE", text: $quotationTitle, focused: $anyFocused)
                TitledTextField(label: "Purchase Order", placeholder: "e.g. PURCHASE ORDER", text: $poTitle, focused: $anyFocused)
                TitledTextField(label: "Service Report", placeholder: "e.g. SERVICE REPORT", text: $serviceReportTitle, focused: $anyFocused)
                TitledTextField(label: "Invoice", placeholder: "e.g. INVOICE", text: $invoiceTitle, focused: $anyFocused)
            } header: {
                SettingsSectionHeader(icon: "textformat", title: "PDF Title Labels")
            } footer: {
                Text("Appears at the top of each PDF. For the quotation, try \"PROFORMA INVOICE\" or \"DELIVERY ORDER\".")
            }

            Section {
                TitledTextField(label: "Quotation", placeholder: "e.g. QA", text: $quotationNumberPrefix, focused: $anyFocused)
                TitledTextField(label: "Purchase Order", placeholder: "e.g. POA-", text: $poNumberPrefix, focused: $anyFocused)
                TitledTextField(label: "Service Report", placeholder: "e.g. SRA-", text: $reportNumberPrefix, focused: $anyFocused)
                TitledTextField(label: "Invoice", placeholder: "e.g. IA", text: $invoiceNumberPrefix, focused: $anyFocused)
            } header: {
                SettingsSectionHeader(icon: "number", title: "Number Prefix (This Device)")
            } footer: {
                Text("Use a different prefix on each device, e.g. QA on iPhone and QB on iPad, so merged backups never have clashing numbers. New numbers continue from the highest existing number. Leave blank for normal numbering. This setting is not included in backups.")
            }

            CurrencyPickerSection()

            Section {
                // Quotation remarks
                VStack(alignment: .leading, spacing: 6) {
                    Label("Quotation Remarks", systemImage: "doc.text")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.blue)
                    TextField("e.g. Payment due within 30 days…", text: $defaultRemarks, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...5)
                        .focused($anyFocused)
                }
                .padding(.vertical, 4)

                // Default payment term
                Menu {
                    Button("None") { defaultPaymentTerm = "" }
                    Divider()
                    ForEach(["Bank Transfer", "Net 30 Days", "Net 60 Days",
                             "50% Deposit, Balance Net 30 Days",
                             "Cash on Delivery", "Cash Before Delivery"], id: \.self) { term in
                        Button {
                            defaultPaymentTerm = term
                        } label: {
                            HStack {
                                Text(term)
                                if defaultPaymentTerm == term {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Default Payment Terms", systemImage: "creditcard")
                            .font(.body).foregroundColor(.primary)
                        Spacer()
                        Text(defaultPaymentTerm.isEmpty ? "None" : defaultPaymentTerm)
                            .font(.body)
                            .foregroundColor(defaultPaymentTerm.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.trailing)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                SettingsSectionHeader(icon: "note.text", title: "Default Text")
            }

            Section {
                // PO remarks — separate rows, Form draws its own divider between them
                VStack(alignment: .leading, spacing: 4) {
                    Label("PO Remarks", systemImage: "cart")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.green)
                    TextField("e.g. Please confirm stock availability…", text: $defaultPORemarks, axis: .vertical)
                        .font(.body).lineLimit(1...4).focused($anyFocused)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("Delivery Instructions", systemImage: "shippingbox")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.orange)
                    TextField("e.g. Deliver to main warehouse loading dock…", text: $defaultPODeliveryInstructions, axis: .vertical)
                        .font(.body).lineLimit(1...4).focused($anyFocused)
                }
            } footer: {
                Text("Pre-filled when creating new documents. You can still edit per document.")
            }
        }
    }

    // MARK: - Tab 3: Branding
    var brandingTab: some View {
        Form {
            Section {
                Picker("Theme", selection: $selectedPDFLayout) {
                    ForEach(PDFLayoutTemplate.allCases) { t in
                        HStack {
                            Circle().fill(t.accentColor).frame(width: 10, height: 10)
                            Text(t.rawValue)
                        }
                        .tag(t.rawValue)
                    }
                }
                .pickerStyle(.menu)

                Toggle(isOn: $showCompanyLogo) {
                    Label("Show Logo on PDFs", systemImage: "photo")
                }

                if showCompanyLogo {
                    HStack(spacing: 16) {
                        // Logo thumbnail
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray5))
                                .frame(width: 64, height: 64)
                            if let img = displayImage {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                Image(systemName: "photo.badge.plus")
                                    .font(.title2).foregroundColor(.secondary)
                            }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 8) {
                            Button(uploadedLogoData == nil ? "Select Logo" : "Replace Logo") {
                                showPhotosPicker = true
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)

                            if uploadedLogoData != nil {
                                Button("Remove", role: .destructive) {
                                    uploadedLogoData = nil; displayImage = nil; pickedItem = nil
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            } header: {
                SettingsSectionHeader(icon: "paintbrush", title: "PDF Theme")
            }

            // Live preview
            Section {
                LivePDFPreview(
                    layout: PDFLayoutTemplate(rawValue: selectedPDFLayout) ?? .corporate,
                    companyName: companyName,
                    companyAddress: companyAddress,
                    companyContact: companyContact,
                    documentTitle: quotationTitle,
                    showLogo: showCompanyLogo,
                    logoData: uploadedLogoData
                )
                .listRowInsets(.init())
                .listRowBackground(Color.clear)
            } header: {
                SettingsSectionHeader(icon: "eye", title: "Live Preview")
            }
        }
    }

    // MARK: - Export
    // MARK: - Backup payload (shared between export and restore)
    struct BackupPayload: Codable {
        struct VendorDTO: Codable {
            var name, company, contactNumber, address, postcode, state, country, email, notes: String
        }
        struct CustomerDTO: Codable {
            var name, company, contactNumber, address, postcode, state, country: String
            var customerTypeRawValue: String? = nil
            var email: String? = nil
            var whatsappNumber: String? = nil
        }
        struct ProductDTO: Codable {
            var itemCode, itemDescription: String
            var defaultUnitPrice, defaultCost, defaultSP2, defaultCP2: Double
            var defaultRebate1, defaultRebate2, defaultDisc1, defaultDisc2: Double
            var isActive: Bool
            var categoryRawValue: String? = nil
        }
        struct LineItemDTO: Codable {
            var itemCode, itemDescription: String; var qty: Int; var unitPrice: Double
            // Fulfillment fields — optional for backward-compat with v2 backups.
            var sortOrder: Int? = nil
            var isDelivered: Bool? = nil
            var linkedPONumber: String? = nil
            var linkedPOId: String? = nil
            var deliveredDate: Date? = nil
            // v5 — the invoice that bills this quotation item (the invoice's id in the backup).
            var invoiceId: String? = nil
            // v6 — saved cost per unit for the internal margin reference (quotations).
            var unitCost: Double? = nil
        }
        struct SettingsDTO: Codable {
            var selectedPDFLayout: String?
            var companyName: String?
            var companyAddress: String?
            var companyContact: String?
            var companyTagline: String?
            var defaultBankAccount: String?
            var defaultRemarks: String?
            var showCompanyLogo: Bool?
            var uploadedLogoData: Data?
            var quotationTitle: String?
            var poTitle: String?
            var serviceReportTitle: String?
            var defaultPaymentTerm: String?
            var defaultPORemarks: String?
            var defaultPODeliveryInstructions: String?
            // v4 — picker lists, optional for backward-compat with older backups
            var savedTechnicians: [String]?
            var customDeviceModels: [String]?
            // v5
            var invoiceTitle: String?
        }
        struct QuotationDTO: Codable {
            var quoteNumber, customerName, remarks, bankAccountNumber, paymentTerm, statusRaw: String
            var discountPct, discountFixed, taxPct: Double; var taxLabel: String
            var date: Date; var items: [LineItemDTO]
            // Optional for backward-compat with older backups.
            var studentName: String? = nil
            var studentID: String? = nil
        }
        struct PODTO: Codable {
            var poNumber, vendorName, remarks, deliveryInstructions: String
            var discountPct, discountFixed, taxPct: Double; var taxLabel: String
            var date: Date; var items: [LineItemDTO]
        }
        struct InvoiceDTO: Codable {
            var id: String
            var invoiceNumber, customerName, customerAddress, customerPostcode: String
            var customerState, customerCountry, customerContactNumber: String
            var studentName, studentID, remarks, bankAccountNumber, paymentTerm: String
            var quotationNumber, statusRaw: String
            var paidDate: Date?
            var discountPct, discountFixed, taxPct: Double
            var taxLabel: String
            var date: Date
            var items: [LineItemDTO]
            // Payments received (JSON text). Optional so older backups still load.
            var paymentsJSON: String? = nil
        }
        struct ServiceReportDTO: Codable {
            var reportNumber, customerName, deviceModel, serialNumber: String
            var issueDescription, resolution, technicianName, status, notes: String
            var date: Date
            // Added later; optional so older backups still restore.
            var quotationNumber: String? = nil
            var warrantyStatus: String? = nil
            var extraItems: String? = nil
            var conditionCheck: String? = nil
            var termsText: String? = nil
        }
        var exportedAt: Date
        var schemaVersion: Int = 5
        var currencyCode: String
        var currencySymbol: String
        var vendors: [VendorDTO]
        var customers: [CustomerDTO]
        var products: [ProductDTO]
        var quotations: [QuotationDTO]
        var purchaseOrders: [PODTO]
        var serviceReports: [ServiceReportDTO]
        var settings: SettingsDTO? = nil
        var invoices: [InvoiceDTO]? = nil
    }

    // MARK: - Backup reminder
    private var daysSinceBackup: Int? {
        guard lastBackupAt > 0 else { return nil }
        let last = Date(timeIntervalSince1970: lastBackupAt)
        return Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
    }

    private var backupIsStale: Bool {
        guard let days = daysSinceBackup else { return true }
        return days >= 30
    }

    @ViewBuilder
    private var backupStatusRow: some View {
        let stale = backupIsStale
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: stale ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundColor(stale ? .orange : .green)
                Text("Last backup")
                Spacer()
                Text(backupStatusText)
                    .font(.subheadline)
                    .foregroundColor(stale ? .orange : .secondary)
            }
            if stale {
                Text("Export a backup and keep the file somewhere safe, such as iCloud Drive or email to yourself.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var backupStatusText: String {
        guard let days = daysSinceBackup else { return "Never" }
        switch days {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(days) days ago"
        }
    }

    private func exportBackup() -> URL? {
        let ud = UserDefaults.standard
        let settingsDTO = BackupPayload.SettingsDTO(
            selectedPDFLayout: ud.string(forKey: AppStorageKeys.selectedPDFLayout),
            companyName: ud.string(forKey: AppStorageKeys.companyName),
            companyAddress: ud.string(forKey: AppStorageKeys.companyAddress),
            companyContact: ud.string(forKey: AppStorageKeys.companyContact),
            companyTagline: ud.string(forKey: AppStorageKeys.companyTagline),
            defaultBankAccount: ud.string(forKey: AppStorageKeys.defaultBankAccount),
            defaultRemarks: ud.string(forKey: AppStorageKeys.defaultRemarks),
            showCompanyLogo: ud.object(forKey: AppStorageKeys.showCompanyLogo) as? Bool,
            uploadedLogoData: ud.data(forKey: AppStorageKeys.uploadedLogoData),
            quotationTitle: ud.string(forKey: AppStorageKeys.quotationTitle),
            poTitle: ud.string(forKey: AppStorageKeys.poTitle),
            serviceReportTitle: ud.string(forKey: AppStorageKeys.serviceReportTitle),
            defaultPaymentTerm: ud.string(forKey: AppStorageKeys.defaultPaymentTerm),
            defaultPORemarks: ud.string(forKey: AppStorageKeys.defaultPORemarks),
            defaultPODeliveryInstructions: ud.string(forKey: AppStorageKeys.defaultPODeliveryInstructions),
            savedTechnicians: ud.stringArray(forKey: AppStorageKeys.savedTechnicians),
            customDeviceModels: ud.stringArray(forKey: AppStorageKeys.customDeviceModels),
            invoiceTitle: ud.string(forKey: AppStorageKeys.invoiceTitle)
        )
        let invoiceDTOs: [BackupPayload.InvoiceDTO] = invoices.map { inv in
            BackupPayload.InvoiceDTO(
                id: inv.id.uuidString,
                invoiceNumber: inv.invoiceNumber, customerName: inv.customerName,
                customerAddress: inv.customerAddress, customerPostcode: inv.customerPostcode,
                customerState: inv.customerState, customerCountry: inv.customerCountry,
                customerContactNumber: inv.customerContactNumber,
                studentName: inv.studentName, studentID: inv.studentID, remarks: inv.remarks,
                bankAccountNumber: inv.bankAccountNumber, paymentTerm: inv.paymentTerm,
                quotationNumber: inv.quotationNumber, statusRaw: inv.statusRaw,
                paidDate: inv.paidDate,
                discountPct: inv.discountPct, discountFixed: inv.discountFixed, taxPct: inv.taxPct,
                taxLabel: inv.taxLabel, date: inv.date,
                items: inv.items.map {
                    BackupPayload.LineItemDTO(itemCode: $0.itemCode, itemDescription: $0.itemDescription,
                                              qty: $0.qty, unitPrice: $0.unitPrice, sortOrder: $0.sortOrder)
                },
                paymentsJSON: inv.paymentsJSON.isEmpty ? nil : inv.paymentsJSON
            )
        }
        let payload = BackupPayload(
            exportedAt: Date(),
            currencyCode: ud.string(forKey: AppStorageKeys.currencyCode) ?? "MYR",
            currencySymbol: ud.string(forKey: AppStorageKeys.currencySymbol) ?? "RM",
            vendors: vendors.map { .init(name: $0.name, company: $0.company, contactNumber: $0.contactNumber, address: $0.address, postcode: $0.postcode, state: $0.state, country: $0.country, email: $0.email, notes: $0.notes) },
            customers: customers.map { .init(name: $0.name, company: $0.company, contactNumber: $0.contactNumber, address: $0.address, postcode: $0.postcode, state: $0.state, country: $0.country, customerTypeRawValue: $0.customerTypeRawValue, email: $0.email, whatsappNumber: $0.whatsappNumber) },
            products: products.map { .init(itemCode: $0.itemCode, itemDescription: $0.itemDescription, defaultUnitPrice: $0.defaultUnitPrice, defaultCost: $0.defaultCost, defaultSP2: $0.defaultSP2, defaultCP2: $0.defaultCP2, defaultRebate1: $0.defaultRebate1, defaultRebate2: $0.defaultRebate2, defaultDisc1: $0.defaultDisc1, defaultDisc2: $0.defaultDisc2, isActive: $0.isActive, categoryRawValue: $0.categoryRawValue) },
            quotations: quotations.map { q in
                .init(quoteNumber: q.quoteNumber, customerName: q.customerName, remarks: q.remarks, bankAccountNumber: q.bankAccountNumber, paymentTerm: q.paymentTerm, statusRaw: q.statusRaw, discountPct: q.discountPct, discountFixed: q.discountFixed, taxPct: q.taxPct, taxLabel: q.taxLabel, date: q.date,
                      items: q.items.map { .init(itemCode: $0.itemCode, itemDescription: $0.itemDescription, qty: $0.qty, unitPrice: $0.unitPrice, sortOrder: $0.sortOrder, isDelivered: $0.isDelivered, linkedPONumber: $0.linkedPONumber, linkedPOId: $0.linkedPOId, invoiceId: $0.invoiceId, unitCost: $0.unitCost > 0 ? $0.unitCost : nil) },
                      studentName: q.studentName, studentID: q.studentID)
            },
            purchaseOrders: purchaseOrders.map { p in
                .init(poNumber: p.poNumber, vendorName: p.vendorName, remarks: p.remarks, deliveryInstructions: p.deliveryInstructions, discountPct: p.discountPct, discountFixed: p.discountFixed, taxPct: p.taxPct, taxLabel: p.taxLabel, date: p.date,
                      items: p.items.map { .init(itemCode: $0.itemCode, itemDescription: $0.itemDescription, qty: $0.qty, unitPrice: $0.unitPrice, sortOrder: $0.sortOrder, isDelivered: $0.isDelivered, linkedPONumber: $0.linkedPONumber, linkedPOId: $0.linkedPOId, deliveredDate: $0.deliveredDate) })
            },
            serviceReports: serviceReports.map { .init(reportNumber: $0.reportNumber, customerName: $0.customerName, deviceModel: $0.deviceModel, serialNumber: $0.serialNumber, issueDescription: $0.issueDescription, resolution: $0.resolution, technicianName: $0.technicianName, status: $0.status.rawValue, notes: $0.notes, date: $0.date, quotationNumber: $0.quotationNumber, warrantyStatus: $0.warrantyStatus, extraItems: $0.extraItems, conditionCheck: $0.conditionCheck, termsText: $0.termsText) },
            settings: settingsDTO,
            invoices: invoiceDTOs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompQuote-Backup-\(formatter.string(from: Date())).json")
        try? data.write(to: url)
        return url
    }

    private func restoreBackup(from url: URL, replace: Bool) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            restoreMessage = "Could not read the backup file."; return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data) else {
            restoreMessage = "Invalid backup file. Make sure it was exported from CompQuote."; return
        }

        // Replace mode — delete all existing data first
        if replace {
            customers.forEach     { modelContext.delete($0) }
            vendors.forEach       { modelContext.delete($0) }
            products.forEach      { modelContext.delete($0) }
            quotations.forEach    { modelContext.delete($0) }
            purchaseOrders.forEach { modelContext.delete($0) }
            serviceReports.forEach { modelContext.delete($0) }
            invoices.forEach      { modelContext.delete($0) }
            try? modelContext.save()
        }

        var counts = (vendors: 0, customers: 0, products: 0, quotations: 0, pos: 0, reports: 0, invoices: 0)
        var restoredQuotations: [Quotation] = []
        var restoredPOs: [PurchaseOrder] = []

        // Restore vendors
        let existingVendorKeys = Set(vendors.map { "\($0.name.lowercased())|\($0.company.lowercased())" })
        for v in payload.vendors {
            let key = "\(v.name.lowercased())|\(v.company.lowercased())"
            guard replace || !existingVendorKeys.contains(key) else { continue }
            modelContext.insert(Vendor(name: v.name, company: v.company, contactNumber: v.contactNumber, address: v.address, postcode: v.postcode, state: v.state, country: v.country, email: v.email, notes: v.notes))
            counts.vendors += 1
        }

        // Restore customers
        let existingCustomerKeys = Set(customers.map { "\($0.name.lowercased())|\($0.company.lowercased())" })
        for c in payload.customers {
            let key = "\(c.name.lowercased())|\(c.company.lowercased())"
            guard replace || !existingCustomerKeys.contains(key) else { continue }
            let newCustomer = Customer(name: c.name, company: c.company, contactNumber: c.contactNumber, address: c.address, postcode: c.postcode, state: c.state, country: c.country, customerTypeRawValue: c.customerTypeRawValue)
            newCustomer.email = c.email ?? ""
            newCustomer.whatsappNumber = c.whatsappNumber ?? ""
            modelContext.insert(newCustomer)
            counts.customers += 1
        }

        // Restore products
        let existingProductCodes = Set(products.map { $0.itemCode.lowercased() })
        for p in payload.products {
            guard replace || !existingProductCodes.contains(p.itemCode.lowercased()) else { continue }
            modelContext.insert(Product(itemCode: p.itemCode, itemDescription: p.itemDescription, defaultUnitPrice: p.defaultUnitPrice, defaultCost: p.defaultCost, defaultSP2: p.defaultSP2, defaultCP2: p.defaultCP2, defaultRebate1: p.defaultRebate1, defaultRebate2: p.defaultRebate2, defaultDisc1: p.defaultDisc1, defaultDisc2: p.defaultDisc2, isActive: p.isActive, categoryRawValue: p.categoryRawValue))
            counts.products += 1
        }

        // Restore invoices first, so the quotation items they bill can be re-linked below.
        // Restored invoices get new ids; invoiceIdMap translates the ids stored in the backup.
        var invoiceIdMap: [String: String] = [:]
        var restoredInvoices: [Invoice] = []
        var existingInvoiceIds: [String: String] = [:]
        if !replace {
            for inv in invoices { existingInvoiceIds[inv.invoiceNumber.lowercased()] = inv.id.uuidString }
        }
        for inv in payload.invoices ?? [] {
            if let existingId = existingInvoiceIds[inv.invoiceNumber.lowercased()] {
                invoiceIdMap[inv.id] = existingId     // already here: keep the existing one
                continue
            }
            let newInv = Invoice(invoiceNumber: inv.invoiceNumber, customerName: inv.customerName)
            newInv.date                  = inv.date
            newInv.customerAddress       = inv.customerAddress
            newInv.customerPostcode      = inv.customerPostcode
            newInv.customerState         = inv.customerState
            newInv.customerCountry       = inv.customerCountry
            newInv.customerContactNumber = inv.customerContactNumber
            newInv.studentName           = inv.studentName
            newInv.studentID             = inv.studentID
            newInv.remarks               = inv.remarks
            newInv.bankAccountNumber     = inv.bankAccountNumber
            newInv.paymentTerm           = inv.paymentTerm
            newInv.quotationNumber       = inv.quotationNumber
            newInv.statusRaw             = inv.statusRaw
            newInv.paidDate              = inv.paidDate
            newInv.paymentsJSON          = inv.paymentsJSON ?? ""
            newInv.discountPct           = inv.discountPct
            newInv.discountFixed         = inv.discountFixed
            newInv.taxPct                = inv.taxPct
            newInv.taxLabel              = inv.taxLabel
            for item in inv.items {
                newInv.items.append(LineItem(itemCode: item.itemCode, itemDescription: item.itemDescription, qty: item.qty, unitPrice: item.unitPrice, sortOrder: item.sortOrder ?? 0))
            }
            modelContext.insert(newInv)
            invoiceIdMap[inv.id] = newInv.id.uuidString
            existingInvoiceIds[inv.invoiceNumber.lowercased()] = newInv.id.uuidString
            restoredInvoices.append(newInv)
            counts.invoices += 1
        }

        // Restore quotations
        let existingQuoteNumbers = Set(quotations.map { $0.quoteNumber.lowercased() })
        for q in payload.quotations {
            guard replace || !existingQuoteNumbers.contains(q.quoteNumber.lowercased()) else { continue }
            let newQ = Quotation(quoteNumber: q.quoteNumber, customerName: q.customerName, remarks: q.remarks, bankAccountNumber: q.bankAccountNumber)
            newQ.date = q.date
            newQ.paymentTerm = q.paymentTerm
            newQ.statusRaw = q.statusRaw
            newQ.discountPct = q.discountPct
            newQ.discountFixed = q.discountFixed
            newQ.taxPct = q.taxPct
            newQ.taxLabel = q.taxLabel
            newQ.studentName = q.studentName ?? ""
            newQ.studentID = q.studentID ?? ""
            for item in q.items {
                let li = LineItem(itemCode: item.itemCode, itemDescription: item.itemDescription, qty: item.qty, unitPrice: item.unitPrice, sortOrder: item.sortOrder ?? 0)
                li.isDelivered = item.isDelivered ?? false
                li.linkedPONumber = item.linkedPONumber ?? ""
                li.linkedPOId = item.linkedPOId ?? ""
                li.invoiceId = item.invoiceId.flatMap { invoiceIdMap[$0] } ?? ""
                li.unitCost = item.unitCost ?? 0
                newQ.items.append(li)
            }
            modelContext.insert(newQ)
            restoredQuotations.append(newQ)
            counts.quotations += 1
        }

        // Restore POs
        let existingPONumbers = Set(purchaseOrders.map { $0.poNumber.lowercased() })
        for p in payload.purchaseOrders {
            guard replace || !existingPONumbers.contains(p.poNumber.lowercased()) else { continue }
            let newPO = PurchaseOrder(poNumber: p.poNumber, vendorName: p.vendorName, remarks: p.remarks, deliveryInstructions: p.deliveryInstructions)
            newPO.date = p.date
            newPO.discountPct = p.discountPct
            newPO.discountFixed = p.discountFixed
            newPO.taxPct = p.taxPct
            newPO.taxLabel = p.taxLabel
            for item in p.items {
                let li = LineItem(itemCode: item.itemCode, itemDescription: item.itemDescription, qty: item.qty, unitPrice: item.unitPrice, sortOrder: item.sortOrder ?? 0)
                li.isDelivered = item.isDelivered ?? false
                li.linkedPONumber = item.linkedPONumber ?? ""
                li.linkedPOId = item.linkedPOId ?? ""
                li.deliveredDate = item.deliveredDate
                newPO.items.append(li)
            }
            modelContext.insert(newPO)
            restoredPOs.append(newPO)
            counts.pos += 1
        }

        // Restore service reports
        let existingReportNumbers = Set(serviceReports.map { $0.reportNumber.lowercased() })
        for r in payload.serviceReports {
            guard replace || !existingReportNumbers.contains(r.reportNumber.lowercased()) else { continue }
            let newR = ServiceReport(reportNumber: r.reportNumber, customerName: r.customerName, deviceModel: r.deviceModel, serialNumber: r.serialNumber, issueDescription: r.issueDescription, resolution: r.resolution, technicianName: r.technicianName, status: ServiceStatus(rawValue: r.status) ?? .open)
            newR.date = r.date
            newR.notes = r.notes
            newR.quotationNumber = r.quotationNumber ?? ""
            newR.warrantyStatus = r.warrantyStatus ?? ""
            newR.extraItems = r.extraItems ?? ""
            newR.conditionCheck = r.conditionCheck ?? ""
            newR.termsText = r.termsText ?? ""
            modelContext.insert(newR)
            counts.reports += 1
        }

        // Re-link restored quotation items to their POs by PO number.
        // Restored POs get brand-new UUIDs, so the linkedPOId values stored
        // in the backup would point at IDs that no longer exist.
        var poIdByNumber: [String: String] = [:]
        if !replace {
            for po in purchaseOrders {
                poIdByNumber[po.poNumber.lowercased()] = po.id.uuidString
            }
        }
        for po in restoredPOs {
            poIdByNumber[po.poNumber.lowercased()] = po.id.uuidString
        }
        for q in restoredQuotations {
            for item in q.items where !item.linkedPONumber.isEmpty {
                if let freshId = poIdByNumber[item.linkedPONumber.lowercased()] {
                    item.linkedPOId = freshId
                }
            }
        }

        // Point each restored invoice at its quotation (new quotation ids, so match by number).
        var quoteIdByNumber: [String: String] = [:]
        if !replace {
            for q in quotations { quoteIdByNumber[q.quoteNumber.lowercased()] = q.id.uuidString }
        }
        for q in restoredQuotations { quoteIdByNumber[q.quoteNumber.lowercased()] = q.id.uuidString }
        for inv in restoredInvoices {
            inv.quotationId = quoteIdByNumber[inv.quotationNumber.lowercased()] ?? ""
        }

        try? modelContext.save()

        // Restore app settings (currency + AppStorage). Only apply on Replace
        // mode, or on Merge when the local key has no value yet — so a merge
        // doesn't overwrite the user's current configuration.
        let ud = UserDefaults.standard
        func apply<T>(_ value: T?, forKey key: String) {
            guard let value else { return }
            if replace || ud.object(forKey: key) == nil {
                ud.set(value, forKey: key)
            }
        }
        apply(payload.currencyCode, forKey: AppStorageKeys.currencyCode)
        apply(payload.currencySymbol, forKey: AppStorageKeys.currencySymbol)
        if let s = payload.settings {
            apply(s.selectedPDFLayout,             forKey: AppStorageKeys.selectedPDFLayout)
            apply(s.companyName,                   forKey: AppStorageKeys.companyName)
            apply(s.companyAddress,                forKey: AppStorageKeys.companyAddress)
            apply(s.companyContact,                forKey: AppStorageKeys.companyContact)
            apply(s.companyTagline,                forKey: AppStorageKeys.companyTagline)
            apply(s.defaultBankAccount,            forKey: AppStorageKeys.defaultBankAccount)
            apply(s.defaultRemarks,                forKey: AppStorageKeys.defaultRemarks)
            apply(s.showCompanyLogo,               forKey: AppStorageKeys.showCompanyLogo)
            apply(s.uploadedLogoData,              forKey: AppStorageKeys.uploadedLogoData)
            apply(s.quotationTitle,                forKey: AppStorageKeys.quotationTitle)
            apply(s.poTitle,                       forKey: AppStorageKeys.poTitle)
            apply(s.serviceReportTitle,            forKey: AppStorageKeys.serviceReportTitle)
            apply(s.defaultPaymentTerm,            forKey: AppStorageKeys.defaultPaymentTerm)
            apply(s.defaultPORemarks,              forKey: AppStorageKeys.defaultPORemarks)
            apply(s.defaultPODeliveryInstructions, forKey: AppStorageKeys.defaultPODeliveryInstructions)
            apply(s.savedTechnicians,              forKey: AppStorageKeys.savedTechnicians)
            apply(s.customDeviceModels,            forKey: AppStorageKeys.customDeviceModels)
            apply(s.invoiceTitle,                  forKey: AppStorageKeys.invoiceTitle)
        }

        restoreMessage = """
            Restore complete!
            Vendors: \(counts.vendors)
            Customers: \(counts.customers)
            Products: \(counts.products)
            Quotations: \(counts.quotations)
            Purchase Orders: \(counts.pos)
            Service Reports: \(counts.reports)
            Invoices: \(counts.invoices)
            """
    }
}

// MARK: - Reusable UI Components

struct SettingsSectionHeader: View {
    let icon: String
    let title: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundColor(.primary)
            .textCase(nil)
    }
}

struct LabeledField<Content: View>: View {
    let icon: String
    let color: Color
    let label: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.secondary)
                content()
            }
        }
    }
}

struct TitledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary).frame(width: 110, alignment: .leading)
            TextField(placeholder, text: $text)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .focused(focused)
        }
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Live PDF Preview
// Renders the actual QuotationPDFView scaled down — always matches real output exactly.
struct LivePDFPreview: View {
    let layout: PDFLayoutTemplate
    let companyName: String
    let companyAddress: String
    let companyContact: String
    let documentTitle: String
    let showLogo: Bool
    let logoData: Data?

    private let a4PageWidth: CGFloat  = 595
    private let a4PageHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Actual PDF layout, scaled down")
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 16).padding(.top, 4)

            GeometryReader { geo in
                let s = geo.size.width / a4PageWidth

                QuotationPDFView(quotation: sampleQuotation)
                    // Force light mode — PDFs are always light regardless of device theme
                    .environment(\.colorScheme, .light)
                    .frame(width: a4PageWidth, height: a4PageHeight, alignment: .topLeading)
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: geo.size.width, height: a4PageHeight * s, alignment: .topLeading)
                    .clipped()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
            }
            .frame(height: 225)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var sampleQuotation: Quotation {
        let q = Quotation(
            quoteNumber: "QT-2026-001",
            customerName: "Sample Customer Sdn Bhd",
            remarks: "Payment due within 30 days.",
            bankAccountNumber: ""
        )
        let item1 = LineItem(itemCode: "SKU-001", itemDescription: "Sample Product One", qty: 1, unitPrice: 2400)
        let item2 = LineItem(itemCode: "SKU-002", itemDescription: "Sample Product Two", qty: 2, unitPrice: 1200)
        q.items.append(item1)
        q.items.append(item2)
        return q
    }
}
