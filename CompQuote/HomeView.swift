import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \Quotation.date, order: .reverse)    private var quotations: [Quotation]
    @Query(sort: \PurchaseOrder.date, order: .reverse) private var purchaseOrders: [PurchaseOrder]
    @Query(sort: \ServiceReport.date, order: .reverse) private var reports: [ServiceReport]

    @AppStorage(AppStorageKeys.companyName) private var companyName = "Computech Solutions"

    @State private var searchText = ""
    @State private var showCreateQuote = false
    @State private var showCreatePO = false
    @State private var showCreateReport = false
    @State private var showCreateCustomer = false
    @State private var quotationToEdit: Quotation?
    @State private var poToEdit: PurchaseOrder?

    // MARK: - Stats
    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())
            ?? DateInterval(start: Date(), duration: 0)
    }
    private var quotesThisMonth: Int {
        quotations.filter { monthInterval.contains($0.date) }.count
    }
    private var revenueThisMonth: Double {
        quotations
            .filter { $0.status == .confirmed && monthInterval.contains($0.date) }
            .reduce(0) { $0 + $1.grandTotal }
    }
    private var openFulfillmentCount: Int {
        quotations.filter { q in
            q.status == .confirmed &&
            !q.items.isEmpty &&
            !q.items.allSatisfy { $0.isDelivered }
        }.count
    }

    // MARK: - Recent (merged & filtered)
    private var recentEntries: [DocumentEntry] {
        let quotes = quotations.map { DocumentEntry.quote($0) }
        let pos    = purchaseOrders.map { DocumentEntry.po($0) }
        let reps   = reports.map { DocumentEntry.report($0) }
        let all    = (quotes + pos + reps).sorted { $0.date > $1.date }
        let filtered: [DocumentEntry]
        if searchText.isEmpty {
            filtered = all
        } else {
            filtered = all.filter { $0.matches(searchText) }
        }
        return Array(filtered.prefix(searchText.isEmpty ? 8 : 30))
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        List {
            // While searching, results move to the top so the keyboard doesn't cover them.
            if isSearching {
                Section("Search Results") {
                    if recentEntries.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search term.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(recentEntries) { entry in
                            Button {
                                open(entry)
                            } label: {
                                RecentDocumentRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Section {
                    HomeHeader(companyName: companyName)
                        .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("Overview") {
                    HStack(spacing: 10) {
                        HomeStatCard(label: "Quotes\nThis Month",
                                 value: "\(quotesThisMonth)",
                                 icon: "doc.text.fill", color: .blue)
                        HomeStatCard(label: "Open\nFulfillment",
                                 value: "\(openFulfillmentCount)",
                                 icon: "shippingbox.fill", color: .orange)
                        HomeStatCard(label: "Confirmed\nRevenue",
                                 value: formatCurrency(revenueThisMonth),
                                 icon: "chart.line.uptrend.xyaxis", color: .green)
                    }
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        ReportsView()
                    } label: {
                        Label("Reports", systemImage: "chart.bar.xaxis")
                    }
                }

                Section("Quick Create") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        QuickTile(title: "Quotation",
                                  icon: "doc.badge.plus", color: .blue) {
                            showCreateQuote = true
                        }
                        QuickTile(title: "Purchase Order",
                                  icon: "cart.badge.plus", color: .green) {
                            showCreatePO = true
                        }
                        QuickTile(title: "Service Report",
                                  icon: "wrench.and.screwdriver.fill", color: .orange) {
                            showCreateReport = true
                        }
                        QuickTile(title: "Customer",
                                  icon: "person.crop.circle.badge.plus", color: .purple) {
                            showCreateCustomer = true
                        }
                    }
                    .listRowInsets(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }

                Section("Recent Activity") {
                    if recentEntries.isEmpty {
                        ContentUnavailableView(
                            "No Recent Activity",
                            systemImage: "clock",
                            description: Text("Create your first document to see it here.")
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(recentEntries) { entry in
                            Button {
                                open(entry)
                            } label: {
                                RecentDocumentRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(isSearching ? "Search" : "")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search quotes, POs, or reports…")
        .sheet(isPresented: $showCreateQuote)  { CreateQuotationView() }
        .sheet(isPresented: $showCreatePO)     { CreatePurchaseOrderView() }
        .sheet(isPresented: $showCreateReport) { CreateServiceReportView() }
        .sheet(isPresented: $showCreateCustomer) { FindOrAddCustomerSheet() }
        .sheet(item: $quotationToEdit) { EditQuotationView(quotation: $0) }
        .sheet(item: $poToEdit)        { EditPurchaseOrderView(order: $0) }
    }

    private func open(_ entry: DocumentEntry) {
        switch entry {
        case .quote(let q):  quotationToEdit = q
        case .po(let p):     poToEdit = p
        case .report:        break   // Reports open via their own tab; tapping is a no-op here.
        }
    }
}

// MARK: - Header (company name + date)
private struct HomeHeader: View {
    let companyName: String

    private var displayName: String {
        let t = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "CompQuote" : t
    }
    private var initial: String { String(displayName.prefix(1)).uppercased() }

    var body: some View {
        HStack(spacing: 12) {
            Text(initial)
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.footnote).foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stat Card
private struct HomeStatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        let big = hSize == .regular   // iPad: larger value, label and icon
        VStack(alignment: .leading, spacing: big ? 10 : 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(big ? .body : .footnote.weight(.semibold))
                .frame(width: big ? 34 : 28, height: big ? 34 : 28)
                .background(Color(.systemBackground).opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(value)
                .font(big ? .title : .title3).fontWeight(.bold)
                .lineLimit(1).minimumScaleFactor(0.55)
            Text(label)
                .font(big ? .subheadline : .caption2).foregroundColor(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(big ? 18 : 12)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Quick Create Tile
private struct QuickTile: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold)).foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New \(title)")
    }
}

// MARK: - Recent Document Row
private struct RecentDocumentRow: View {
    let entry: DocumentEntry

    private var shortDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(entry.date) { return "Today" }
        if cal.isDateInYesterday(entry.date) { return "Yesterday" }
        if cal.isDate(entry.date, equalTo: Date(), toGranularity: .year) {
            return entry.date.formatted(.dateTime.day().month(.abbreviated))
        }
        return entry.date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.icon)
                .foregroundColor(entry.color)
                .frame(width: 30)
            // Line 1: number + status, amount. Line 2: name, short date.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.number).fontWeight(.semibold)
                    if let tag = entry.statusText {
                        Text(tag)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .foregroundColor(entry.statusColor)
                            .background(entry.statusColor.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 8)
                    if let total = entry.total {
                        Text(formatCurrency(total))
                            .font(.footnote).fontWeight(.semibold)
                            .lineLimit(1).fixedSize()
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.name)
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortDate)
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1).fixedSize()
                }
            }
        }
    }
}

// MARK: - Unified Document Entry
enum DocumentEntry: Identifiable {
    case quote(Quotation)
    case po(PurchaseOrder)
    case report(ServiceReport)

    var id: String {
        switch self {
        case .quote(let q):  return "Q-\(q.id.uuidString)"
        case .po(let p):     return "P-\(p.id.uuidString)"
        case .report(let r): return "R-\(r.id.uuidString)"
        }
    }
    var date: Date {
        switch self {
        case .quote(let q):  return q.date
        case .po(let p):     return p.date
        case .report(let r): return r.date
        }
    }
    var number: String {
        switch self {
        case .quote(let q):  return q.quoteNumber
        case .po(let p):     return p.poNumber
        case .report(let r): return r.reportNumber
        }
    }
    var name: String {
        switch self {
        case .quote(let q):  return q.customerName
        case .po(let p):     return p.vendorName
        case .report(let r): return r.customerName
        }
    }
    var total: Double? {
        switch self {
        case .quote(let q):  return q.grandTotal
        case .po(let p):     return p.grandTotal
        case .report:        return nil
        }
    }
    var icon: String {
        switch self {
        case .quote:  return "doc.text.fill"
        case .po:     return "cart.fill"
        case .report: return "wrench.and.screwdriver.fill"
        }
    }
    var color: Color {
        switch self {
        case .quote:  return .blue
        case .po:     return .green
        case .report: return .orange
        }
    }

    /// Short status tag for Recent Activity rows (purchase orders have none).
    var statusText: String? {
        switch self {
        case .quote(let q):  return q.status.rawValue
        case .po:            return nil
        case .report(let r): return r.status.rawValue
        }
    }
    var statusColor: Color {
        switch self {
        case .quote(let q):  return q.status.color
        case .po:            return .secondary
        case .report(let r): return r.status.color
        }
    }

    func matches(_ query: String) -> Bool {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = searchableText
        // Tokens prefixed with "-" are exclusions; every other token must appear.
        for token in tokens {
            if token.hasPrefix("-") && token.count > 1 {
                let needle = String(token.dropFirst())
                if haystack.localizedCaseInsensitiveContains(needle) { return false }
            } else if !token.isEmpty {
                if !haystack.localizedCaseInsensitiveContains(token) { return false }
            }
        }
        return true
    }

    // Concatenated haystack of every free-text field on this document (plus its line items).
    // Numbers are compared with contains(), so partial matches like "26209" still work.
    private var searchableText: String {
        switch self {
        case .quote(let q):
            var parts: [String] = [
                q.quoteNumber, q.customerName, q.remarks, q.paymentTerm,
                q.studentName, q.studentID, q.customerReference, q.bankAccountNumber,
                q.status.rawValue, q.taxLabel
            ]
            for item in q.items {
                parts.append(item.itemCode)
                parts.append(item.itemDescription)
                parts.append(item.linkedPONumber)
            }
            return parts.joined(separator: " ")

        case .po(let p):
            var parts: [String] = [
                p.poNumber, p.vendorName, p.remarks,
                p.deliveryInstructions, p.taxLabel
            ]
            for item in p.items {
                parts.append(item.itemCode)
                parts.append(item.itemDescription)
            }
            return parts.joined(separator: " ")

        case .report(let r):
            return [
                r.reportNumber, r.customerName, r.deviceModel, r.serialNumber,
                r.issueDescription, r.resolution, r.technicianName, r.notes,
                r.status.rawValue
            ].joined(separator: " ")
        }
    }
}

// MARK: - Find or Add Customer Sheet
// Search first, then offer to create a new customer if no match is found.
struct FindOrAddCustomerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Customer.name) private var customers: [Customer]

    @State private var searchText = ""
    @State private var showAddCustomer = false
    @State private var customerToEdit: Customer?
    @State private var customerToDuplicate: Customer?
    @FocusState private var searchFocused: Bool

    private var filteredCustomers: [Customer] {
        let tokens = searchText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return customers }
        return customers.filter { c in
            let haystack = [c.name, c.company, c.contactNumber, c.email, c.whatsappNumber,
                            c.address, c.postcode, c.state, c.country]
                .joined(separator: " ")
            return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Search customer name or company…", text: $searchText)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                }

                if !filteredCustomers.isEmpty {
                    Section(searchText.isEmpty ? "All Customers" : "Matches") {
                        ForEach(filteredCustomers) { client in
                            HStack {
                                Button {
                                    customerToEdit = client
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(client.name).fontWeight(.medium).foregroundColor(.primary)
                                        Text(client.company).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.borderless)

                                Spacer()

                                Button {
                                    customerToDuplicate = client
                                } label: {
                                    Image(systemName: "person.badge.plus")
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Duplicate \(client.name)")
                            }
                            .swipeActions(edge: .trailing) {
                                Button {
                                    customerToDuplicate = client
                                } label: {
                                    Label("Duplicate", systemImage: "person.badge.plus")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }

                if !searchText.isEmpty && filteredCustomers.isEmpty {
                    Section {
                        Text("No customer found for \"\(searchText)\"")
                            .font(.caption).foregroundColor(.secondary)
                        Button {
                            showAddCustomer = true
                        } label: {
                            Label("Add \"\(searchText)\" as new customer",
                                  systemImage: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                // Always offer the "Add New" button as a fallback.
                Section {
                    Button {
                        showAddCustomer = true
                    } label: {
                        Label("New Customer", systemImage: "person.crop.circle.badge.plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .navigationTitle("Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { searchFocused = true }
            .sheet(isPresented: $showAddCustomer) {
                AddCustomerSheet(prefilledName: searchText) { _ in
                    dismiss()
                }
            }
            .sheet(item: $customerToEdit) { EditCustomerSheet(customer: $0) }
            .sheet(item: $customerToDuplicate) { original in
                DuplicateCustomerSheet(original: original) { _ in
                    dismiss()
                }
            }
        }
    }
}
