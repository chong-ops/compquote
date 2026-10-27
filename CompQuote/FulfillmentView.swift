import SwiftUI
import SwiftData

// MARK: - Fulfillment View
// Shows confirmed quotations and lets you track PO linkage and delivery per line item.
struct FulfillmentView: View {
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"
    @Query(sort: [SortDescriptor(\Quotation.date, order: .reverse),
                  SortDescriptor(\Quotation.quoteNumber, order: .reverse)]) private var quotations: [Quotation]
    @Query(sort: \PurchaseOrder.date, order: .reverse) private var purchaseOrders: [PurchaseOrder]
    @State private var searchText = ""
    @State private var selectedQuotation: Quotation?

    var confirmedQuotations: [Quotation] {
        let confirmed = quotations.filter { quote in
            guard quote.status == .confirmed else { return false }
            // Hide once every line item has been delivered — those live in the "Done" tab.
            guard !quote.items.isEmpty else { return true }
            return !quote.items.allSatisfy { $0.isDelivered }
        }
        guard !searchText.isEmpty else { return confirmed }
        return confirmed.filter {
            $0.quoteNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.customerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if confirmedQuotations.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Confirmed Quotations" : "No Results",
                    systemImage: "checkmark.seal",
                    description: Text(searchText.isEmpty
                        ? "Confirm a quotation in the Quotations tab to start tracking fulfillment."
                        : "Try a different search term.")
                )
            } else {
                List {
                    ForEach(monthGroups(confirmedQuotations, date: \.date, total: \.grandTotal)) { group in
                        Section {
                            ForEach(group.items) { quotation in
                                FulfillmentRow(quotation: quotation)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedQuotation = quotation }
                            }
                        } header: {
                            MonthHeader(date: group.id, count: group.items.count, total: group.total)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search by number or customer…")
            }
        }
        .sheet(item: $selectedQuotation) { q in
            FulfillmentDetailView(quotation: q, purchaseOrders: purchaseOrders)
        }
    }
}

// MARK: - Fulfillment Row
struct FulfillmentRow: View {
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"
    let quotation: Quotation

    private var deliveredCount: Int { quotation.items.filter { $0.isDelivered }.count }
    private var linkedCount: Int    { quotation.items.filter { !$0.linkedPONumber.isEmpty }.count }
    private var totalCount: Int     { quotation.items.count }
    /// Items still needing a PO: not linked and not already delivered (e.g. from stock).
    private var unlinkedCount: Int  { quotation.items.filter { $0.linkedPONumber.isEmpty && !$0.isDelivered }.count }
    private var progress: Double    { totalCount > 0 ? Double(deliveredCount) / Double(totalCount) : 0 }

    /// Orange while any item still needs a PO, blue once every item has one.
    private var needsPO: Bool { unlinkedCount > 0 }
    private var chipColor: Color { needsPO ? .orange : .blue }
    private var chipIcon: String { needsPO ? "clock.badge.exclamationmark" : "shippingbox.fill" }
    private var chipLabel: String { needsPO ? "Needs PO" : "Awaiting delivery" }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: chipIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(chipColor)
                .frame(width: 36, height: 36)
                .background(chipColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(chipLabel)

            VStack(alignment: .leading, spacing: 3) {
                // Line 1: number + total. Line 2: customer + short date.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(quotation.quoteNumber).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Text(formatCurrency(quotation.grandTotal))
                        .fontWeight(.semibold)
                        .lineLimit(1).fixedSize()
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(quotation.customerName)
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortDocumentDate(quotation.date))
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1).fixedSize()
                }

                // Progress bar
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color(.systemGray5)).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(Color.green)
                                .frame(width: geo.size.width * progress, height: 6)
                                .animation(.easeInOut, value: progress)
                        }
                    }
                    .frame(height: 6)

                    Text("\(deliveredCount)/\(totalCount) delivered")
                        .font(.caption2).foregroundColor(.secondary)
                        .fixedSize()
                }
                .padding(.top, 4)

                // Count chips
                HStack(spacing: 6) {
                    if unlinkedCount > 0 {
                        StatusChip(label: "\(unlinkedCount) unlinked", color: .orange)
                    }
                    if linkedCount > 0 {
                        StatusChip(label: "\(linkedCount) PO'd", color: .blue)
                    }
                    if deliveredCount > 0 {
                        StatusChip(label: "\(deliveredCount) delivered", color: .green)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusChip: View {
    let label: String
    let color: Color
    var body: some View {
        Text(label)
            .font(.caption2).fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Fulfillment Detail View
struct FulfillmentDetailView: View {
    @Bindable var quotation: Quotation
    let purchaseOrders: [PurchaseOrder]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var poToView: PurchaseOrder?
    @State private var showQuotationDetails = false
    // Cancel support: delivery / PO-link state as it was when this screen opened.
    @State private var originalState: [PersistentIdentifier: FulfillState]?
    @State private var showDiscardConfirm = false
    // Invoicing (CompQuote Pro)
    @ObservedObject private var store = SyncStore.shared
    @Query(sort: \Invoice.date, order: .reverse) private var allInvoices: [Invoice]
    @State private var showInvoiceFlow = false
    @State private var invoiceToView: Invoice?
    @State private var pdfToShare: IdentifiableURL?
    @State private var pdfToPreview: IdentifiableURL?
    @State private var sendInfo: SendDocumentInfo?

    private var sortedItems: [LineItem] { quotation.items.sorted { $0.sortOrder < $1.sortOrder } }

    private struct FulfillState: Equatable {
        var poNumber: String
        var poId: String
        var delivered: Bool
        var deliveredDate: Date?
    }

    private func currentState() -> [PersistentIdentifier: FulfillState] {
        Dictionary(uniqueKeysWithValues: quotation.items.map {
            ($0.persistentModelID,
             FulfillState(poNumber: $0.linkedPONumber, poId: $0.linkedPOId,
                          delivered: $0.isDelivered, deliveredDate: $0.deliveredDate))
        })
    }

    /// Puts PO links and delivered ticks back. Invoices already created are left alone.
    private func restoreState() {
        guard let original = originalState else { return }
        for item in quotation.items {
            guard let st = original[item.persistentModelID] else { continue }
            item.linkedPONumber = st.poNumber
            item.linkedPOId = st.poId
            item.isDelivered = st.delivered
            item.deliveredDate = st.deliveredDate
        }
    }

    /// Invoices already raised from this quotation.
    private var quotationInvoices: [Invoice] {
        allInvoices.filter { $0.quotationId == quotation.id.uuidString }
    }
    private var billableItems: [LineItem] { quotation.uninvoicedDeliveredItems }

    // Group items
    private var unlinkedItems:  [LineItem] { sortedItems.filter {  $0.linkedPONumber.isEmpty && !$0.isDelivered } }
    private var linkedItems:    [LineItem] { sortedItems.filter { !$0.linkedPONumber.isEmpty && !$0.isDelivered } }
    private var deliveredItems: [LineItem] { sortedItems.filter {  $0.isDelivered } }

    var body: some View {
        NavigationStack {
            List {
                // ── Header summary (tap anywhere to open the quotation) ───
                Section {
                    Button { showQuotationDetails = true } label: {
                        VStack(spacing: 10) {
                            HStack {
                                Label(quotation.customerName, systemImage: "person.fill")
                                    .font(.subheadline).foregroundColor(.primary)
                                Spacer()
                                Text(quotation.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption).foregroundColor(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold)).foregroundColor(.secondary)
                            }
                            HStack {
                                Label("Total", systemImage: "dollarsign.circle")
                                    .font(.subheadline).foregroundColor(.secondary)
                                Spacer()
                                Text(formatCurrency(quotation.grandTotal))
                                    .fontWeight(.semibold).foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Quotation Details")
                }

                // ── Invoicing ─────────────────────────────────────────────
                if !billableItems.isEmpty || !quotationInvoices.isEmpty {
                    Section {
                        if !billableItems.isEmpty {
                            Button { showInvoiceFlow = true } label: {
                                HStack {
                                    Label("Create Invoice", systemImage: "doc.text.fill")
                                        .foregroundColor(.indigo)
                                    Spacer()
                                    Text("\(billableItems.count) \(billableItems.count == 1 ? "item" : "items") · \(formatCurrency(billableItems.reduce(0) { $0 + $1.subTotal }))")
                                        .font(.caption).foregroundColor(.secondary)
                                    if !store.isUnlocked {
                                        Image(systemName: "lock.fill")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        ForEach(quotationInvoices) { invoice in
                            InvoiceDocumentRow(invoice: invoice)
                                .contentShape(Rectangle())
                                .onTapGesture { invoiceToView = invoice }
                        }
                    } header: {
                        Label("Invoicing", systemImage: "doc.text")
                            .foregroundColor(.indigo)
                    } footer: {
                        if !billableItems.isEmpty {
                            Text("Bills delivered items that are not on an invoice yet. You choose which items on the next screen.")
                        }
                    }
                }

                // ── Unlinked items ────────────────────────────────────────
                if !unlinkedItems.isEmpty {
                    Section {
                        ForEach(unlinkedItems) { item in
                            FulfillmentItemRow(
                                item: item,
                                purchaseOrders: purchaseOrders,
                                onPOTap: { poToView = $0 }
                            )
                        }
                    } header: {
                        Label("Pending — Link to PO", systemImage: "clock.badge.exclamationmark")
                            .foregroundColor(.orange)
                    }
                }

                // ── Linked / In progress ──────────────────────────────────
                if !linkedItems.isEmpty {
                    Section {
                        ForEach(linkedItems) { item in
                            FulfillmentItemRow(
                                item: item,
                                purchaseOrders: purchaseOrders,
                                onPOTap: { poToView = $0 }
                            )
                        }
                    } header: {
                        Label("PO Raised — Awaiting Delivery", systemImage: "shippingbox")
                            .foregroundColor(.blue)
                    }
                }

                // ── Delivered ─────────────────────────────────────────────
                if !deliveredItems.isEmpty {
                    Section {
                        ForEach(deliveredItems) { item in
                            FulfillmentItemRow(
                                item: item,
                                purchaseOrders: purchaseOrders,
                                onPOTap: { poToView = $0 }
                            )
                        }
                    } header: {
                        Label("Delivered", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle(quotation.quoteNumber)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if originalState == nil { originalState = currentState() } }
            .confirmationDialog("Discard changes?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    restoreState()
                    try? modelContext.save()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("PO links and delivered ticks go back to how they were when you opened this screen.")
            }
            .toolbar {
                ToolbarItem(id: "fulfill-cancel", placement: .cancellationAction) {
                    Button("Cancel") {
                        if let originalState, currentState() != originalState {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(id: "fulfill-quote-pdf-actions", placement: .topBarTrailing) {
                    Menu {
                        Button { previewQuotationPDF() } label: {
                            Label("Preview PDF", systemImage: "eye")
                        }
                        Button { shareQuotationPDF() } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        Button { sendInfo = SendDocumentInfo.quotation(quotation) } label: {
                            Label("Send to Customer…", systemImage: "paperplane")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(id: "fulfill-done", placement: .topBarTrailing) {
                    Button("Done") { try? modelContext.save(); dismiss() }
                }
            }
            .sheet(item: $pdfToShare) { wrapped in
                ActivityShareSheet(items: [wrapped.url])
            }
            .sheet(item: $sendInfo) { SendDocumentSheet(info: $0) }
            .sheet(item: $pdfToPreview) { wrapped in
                NavigationStack {
                    PDFViewer(url: wrapped.url)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("PDF Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { pdfToPreview = nil }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { pdfToShare = wrapped } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .accessibilityLabel("Share PDF")
                            }
                        }
                }
            }
            .sheet(isPresented: $showQuotationDetails) {
                EditQuotationView(quotation: quotation)
            }
            .sheet(item: $poToView) { po in
                NavigationStack {
                    EditPurchaseOrderView(order: po)
                }
            }
            .sheet(isPresented: $showInvoiceFlow) {
                InvoiceFlowSheet(quotation: quotation)
            }
            .sheet(item: $invoiceToView) { invoice in
                EditInvoiceView(invoice: invoice)
            }
        }
    }

    private func shareQuotationPDF() {
        guard let url = PDFGenerator.generate(
            view: QuotationPDFView(quotation: quotation),
            filename: quotation.quoteNumber
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func previewQuotationPDF() {
        guard let url = PDFGenerator.generate(
            view: QuotationPDFView(quotation: quotation),
            filename: quotation.quoteNumber
        ) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }
}

// MARK: - Fulfillment Item Row
struct FulfillmentItemRow: View {
    @Bindable var item: LineItem
    let purchaseOrders: [PurchaseOrder]
    let onPOTap: (PurchaseOrder) -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var showPicker = false

    // Find PO object by stored ID
    private var linkedPO: PurchaseOrder? {
        guard !item.linkedPOId.isEmpty else { return nil }
        return purchaseOrders.first { $0.id.uuidString == item.linkedPOId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Item info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.itemCode).font(.headline)
                    Text(item.itemDescription).font(.caption).foregroundColor(.secondary)
                    Text("Qty: \(item.qty)  ·  \(formatCurrency(item.subTotal))")
                        .font(.caption2).foregroundColor(.secondary)
                    if item.isInvoiced {
                        Text("On an invoice")
                            .font(.caption2.weight(.semibold)).foregroundColor(.indigo)
                    }
                }
                Spacer()
                if item.isInvoiced {
                    // Billed items stay delivered. Delete the invoice to change them.
                    Image(systemName: "doc.text.fill")
                        .font(.title3)
                        .foregroundColor(.indigo)
                        .accessibilityLabel("Invoiced")
                } else {
                    // Delivered toggle
                    Button {
                        item.isDelivered.toggle()
                        try? modelContext.save()
                    } label: {
                        Image(systemName: item.isDelivered ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(item.isDelivered ? .green : .secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // PO link
            if item.isDelivered, let po = linkedPO {
                // Delivered — show PO as tappable reference
                Button { onPOTap(po) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green).font(.caption)
                        Text("Delivered via \(po.poNumber)").font(.caption).foregroundColor(.green)
                        Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.borderless)
            } else {
                // PO picker
                HStack(spacing: 8) {
                    Image(systemName: "cart").font(.caption).foregroundColor(.secondary)

                    Button { showPicker = true } label: {
                        HStack(spacing: 4) {
                            Text(item.linkedPONumber.isEmpty ? "Link to PO…" : item.linkedPONumber)
                                .font(.caption)
                                .foregroundColor(item.linkedPONumber.isEmpty ? .secondary : .blue)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.borderless)

                    // Tap to open PO
                    if let po = linkedPO {
                        Button { onPOTap(po) } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption).foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(item.isDelivered ? 0.6 : 1.0)
        .sheet(isPresented: $showPicker) {
            POLinkPickerSheet(item: item, purchaseOrders: purchaseOrders)
        }
    }
}

// MARK: - PO picker (Fulfillment → choose the PO that covers a quotation item)
private func normCode(_ s: String) -> String {
    s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

struct POLinkPickerSheet: View {
    @Bindable var item: LineItem
    let purchaseOrders: [PurchaseOrder]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private enum POFilter: String, CaseIterable, Identifiable {
        case matching = "Matching", open = "Open", all = "All"
        var id: String { rawValue }
    }
    @State private var chosenFilter: POFilter?
    @State private var search = ""

    private var anyMatch: Bool { purchaseOrders.contains { matchQty($0) != nil } }
    /// Starts on Matching when some PO has this item, otherwise on Open.
    private var filter: POFilter { chosenFilter ?? (anyMatch ? .matching : .open) }

    /// Quantity of this item on the PO, or nil when the PO does not contain it.
    private func matchQty(_ po: PurchaseOrder) -> Int? {
        let code = normCode(item.itemCode)
        let hits = po.items.filter { normCode($0.itemCode) == code }
        return hits.isEmpty ? nil : hits.reduce(0) { $0 + $1.qty }
    }
    /// A PO is open while at least one of its items has not been received.
    private func isOpen(_ po: PurchaseOrder) -> Bool {
        po.items.isEmpty || po.items.contains { !$0.isDelivered }
    }

    private var list: [PurchaseOrder] {
        var r = purchaseOrders
        switch filter {
        case .matching: r = r.filter { matchQty($0) != nil || $0.id.uuidString == item.linkedPOId }
        case .open:     r = r.filter { isOpen($0) || $0.id.uuidString == item.linkedPOId }
        case .all:      break
        }
        if !search.isEmpty {
            r = r.filter { $0.poNumber.localizedCaseInsensitiveContains(search) ||
                           $0.vendorName.localizedCaseInsensitiveContains(search) }
        }
        return r.sorted { a, b in
            let ma = matchQty(a) != nil, mb = matchQty(b) != nil
            if ma != mb { return ma }
            return a.date > b.date
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.itemCode).font(.headline)
                        Text(item.itemDescription).font(.caption).foregroundColor(.secondary)
                        Text("Qty \(item.qty)").font(.caption2).foregroundColor(.secondary)
                    }
                    Picker("Show", selection: Binding(get: { filter }, set: { chosenFilter = $0 })) {
                        ForEach(POFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Item to link")
                } footer: {
                    switch filter {
                    case .matching: Text("Only POs that contain this item code. Use Open or All to see other POs.")
                    case .open:     Text("POs that still have items not received. POs that contain this item are listed first.")
                    case .all:      Text("Every purchase order.")
                    }
                }

                Section("Purchase Orders") {
                    if list.isEmpty {
                        Text(filter == .matching ? "No PO contains this item yet. Switch to Open or All." :
                             filter == .open ? "No open POs. Switch to All." : "No purchase orders found.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    ForEach(list) { po in
                        Button {
                            item.linkedPONumber = po.poNumber
                            item.linkedPOId = po.id.uuidString
                            try? modelContext.save()
                            dismiss()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(po.poNumber).font(.headline).foregroundColor(.primary)
                                    Text(po.vendorName).font(.subheadline).foregroundColor(.secondary)
                                    HStack(spacing: 6) {
                                        Text(shortDocumentDate(po.date))
                                        Text("· \(po.items.filter { $0.isDelivered }.count)/\(po.items.count) received")
                                    }
                                    .font(.caption2).foregroundColor(.secondary)
                                    if let q = matchQty(po) {
                                        Label("Contains this item ×\(q)", systemImage: "checkmark.circle.fill")
                                            .font(.caption2.weight(.semibold)).foregroundColor(.green)
                                    }
                                }
                                Spacer()
                                if item.linkedPOId == po.id.uuidString {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }

                if !item.linkedPONumber.isEmpty {
                    Section {
                        Button("Remove PO link", role: .destructive) {
                            item.linkedPONumber = ""
                            item.linkedPOId = ""
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search PO number or vendor")
            .navigationTitle("Link to PO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "po-link-cancel", placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Quotation picker (PO → choose which quotation items it covers)
struct POLinkQuotationSheet: View {
    @Bindable var order: PurchaseOrder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Quotation.date, order: .reverse) private var quotations: [Quotation]
    @State private var showAll = false

    private var poCodes: Set<String> { Set(order.items.map { normCode($0.itemCode) }) }

    private func isLinkedHere(_ i: LineItem) -> Bool { i.linkedPOId == order.id.uuidString }

    private struct Group: Identifiable {
        let quotation: Quotation
        let lines: [LineItem]
        var id: UUID { quotation.id }
    }

    private var groups: [Group] {
        quotations.compactMap { q in
            guard q.status == .confirmed else { return nil }
            let lines = q.items.sorted { $0.sortOrder < $1.sortOrder }.filter { line in
                guard !line.isDelivered else { return false }
                return showAll || poCodes.contains(normCode(line.itemCode)) || isLinkedHere(line)
            }
            return lines.isEmpty ? nil : Group(quotation: q, lines: lines)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show", selection: $showAll) {
                        Text("Matching items").tag(false)
                        Text("All pending items").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Tick the quotation items this PO covers. Matching = same item code as a line on this PO.")
                }

                if groups.isEmpty {
                    Section {
                        Text(showAll ? "No pending quotation items." : "No quotation items match this PO. Switch to All pending items.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
                ForEach(groups) { g in
                    Section {
                        ForEach(g.lines) { line in
                            Button { toggle(line) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: isLinkedHere(line) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(isLinkedHere(line) ? .blue : .secondary)
                                        .font(.title3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.itemCode).font(.headline).foregroundColor(.primary)
                                        Text(line.itemDescription).font(.caption).foregroundColor(.secondary)
                                        Text("Qty \(line.qty)").font(.caption2).foregroundColor(.secondary)
                                        if !line.linkedPONumber.isEmpty && !isLinkedHere(line) {
                                            Text("Currently linked to \(line.linkedPONumber)")
                                                .font(.caption2.weight(.semibold)).foregroundColor(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("\(g.quotation.quoteNumber) — \(g.quotation.customerName)")
                    }
                }
            }
            .navigationTitle("Link Quotation Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "po-link-quote-done", placement: .confirmationAction) {
                    Button("Done") { try? modelContext.save(); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func toggle(_ line: LineItem) {
        if isLinkedHere(line) {
            line.linkedPONumber = ""
            line.linkedPOId = ""
        } else {
            line.linkedPONumber = order.poNumber
            line.linkedPOId = order.id.uuidString
        }
        try? modelContext.save()
    }
}

// MARK: - Previews
#Preview {
    FulfillmentView()
        .modelContainer(for: [Quotation.self, PurchaseOrder.self, LineItem.self, Invoice.self])
}
