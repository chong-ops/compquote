import SwiftUI
import SwiftData

struct EditQuotationView: View {
    @Bindable var quotation: Quotation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.itemCode) private var products: [Product]

    @State private var showAddItemSheet = false
    @State private var itemToEdit: LineItem?
    @State private var orderedItems: [LineItem] = []
    @State private var selectedStatus: QuotationStatus = .draft
    @State private var showSaveErrorAlert = false
    @State private var pdfToShare: IdentifiableURL?
    @State private var pdfToPreview: IdentifiableURL?
    @State private var sendInfo: SendDocumentInfo?
    @State private var showCustomerPicker = false
    // Cancel support: values as they were when the editor opened.
    @State private var original: QuotationSnapshot?
    @State private var showDiscardConfirm = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Form {
                    // ── Summary Card ─────────────────────────────────
                    Section {
                        QuotationSummaryCard(
                            quotation: quotation,
                            selectedStatus: $selectedStatus
                        )
                        .listRowInsets(.init(top: 8, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                    }

                    // ── Document Details (collapsed by default) ─────
                    Section {
                        DisclosureGroup {
                            // Two-column: Quotation Number + Date on one row.
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Number")
                                        .font(.caption).foregroundColor(.secondary)
                                    TextField("Q…", text: $quotation.quoteNumber)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.plain)
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Date")
                                        .font(.caption).foregroundColor(.secondary)
                                    DatePicker("", selection: $quotation.date,
                                               displayedComponents: .date)
                                        .labelsHidden()
                                }
                            }

                            TextField("Customer", text: $quotation.customerName, axis: .vertical)
                                .lineLimit(1...3)

                            Button {
                                showCustomerPicker = true
                            } label: {
                                Label("Change Customer", systemImage: "person.crop.circle.badge.arrow.right")
                                    .font(.footnote)
                            }
                            .buttonStyle(.borderless)

                            // Nested disclosure for the customer address snapshot.
                            DisclosureGroup {
                                TextField("Phone Number", text: $quotation.customerContactNumber)
                                    .keyboardType(.phonePad)
                                TextField("Street Address", text: $quotation.customerAddress, axis: .vertical)
                                    .lineLimit(1...3)
                                    .autocorrectionDisabled()
                                TextField("Postcode", text: $quotation.customerPostcode)
                                    .keyboardType(.numbersAndPunctuation)
                                TextField("State / City", text: $quotation.customerState)
                                TextField("Country", text: $quotation.customerCountry)
                            } label: {
                                HStack {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.secondary).font(.footnote)
                                    Text("Customer Contact & Address")
                                }
                            }

                            // Nested disclosure for student fields.
                            DisclosureGroup {
                                TextField("Student Name", text: $quotation.studentName)
                                TextField("Student ID", text: $quotation.studentID)
                                    .autocorrectionDisabled()
                            } label: {
                                HStack {
                                    Image(systemName: "graduationcap")
                                        .foregroundColor(.secondary).font(.footnote)
                                    Text("Student Details (optional)")
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.secondary).font(.footnote)
                                Text("Document Details")
                            }
                        }
                    }

                    Section("Line Items") {
                        ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                            LineItemEditRow(item: item, index: index, accent: .blue, showIndexOnPhone: false) { deleteItem(item) }
                            .contentShape(Rectangle())
                            .onTapGesture { itemToEdit = item }
                        }
                        // #7 drag to reorder
                        .onMove { from, to in
                            orderedItems.move(fromOffsets: from, toOffset: to)
                            // Write back sort order to the model
                            for (index, item) in orderedItems.enumerated() {
                                item.sortOrder = index
                            }
                        }

                        Button { showAddItemSheet = true } label: {
                            Label("Add Item", systemImage: "plus.circle")
                        }
                    }

                    DiscountTaxSection(
                        discountPct:   $quotation.discountPct,
                        discountFixed: $quotation.discountFixed,
                        taxPct:        $quotation.taxPct,
                        taxLabel:      $quotation.taxLabel,
                        itemsSubtotal:  quotation.itemsSubtotal,
                        discountAmount: quotation.discountAmount,
                        taxAmount:      quotation.taxAmount,
                        grandTotal:     quotation.grandTotal
                    )

                    QuotationMarginSection(quotation: quotation, products: products)

                    Section("Payment & Remarks") {
                        TextField("Bank Account Number", text: $quotation.bankAccountNumber)

                        // Payment term dropdown
                        Menu {
                            Button("None") { quotation.paymentTerm = "" }
                            Divider()
                            ForEach(standardPaymentTerms, id: \.self) { term in
                                Button {
                                    quotation.paymentTerm = term
                                } label: {
                                    HStack {
                                        Text(term)
                                        if quotation.paymentTerm == term {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Payment Terms").foregroundColor(.primary)
                                Spacer()
                                Text(quotation.paymentTerm.isEmpty ? "Select…" : quotation.paymentTerm)
                                    .foregroundColor(quotation.paymentTerm.isEmpty ? .secondary : .primary)
                                    .multilineTextAlignment(.trailing)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }

                        TextField("Remarks / Notes", text: $quotation.remarks, axis: .vertical).lineLimit(3...5)
                    }

                    DeleteRecordSection(title: "Delete Quotation", itemName: quotation.quoteNumber) {
                        let target = quotation
                        dismiss()
                        modelContext.deleteAfterSheetCloses(target)
                    }

                    Color.clear.frame(height: 80).listRowBackground(Color.clear)
                }

                TotalsSummaryBar(
                    itemsSubtotal:  quotation.itemsSubtotal,
                    discountAmount: quotation.discountAmount,
                    taxAmount:      quotation.taxAmount,
                    taxLabel:       quotation.taxLabel,
                    grandTotal:     quotation.grandTotal
                )
            }
            .navigationTitle("Edit Quotation")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))  // always allow drag
            .onChange(of: quotation.items.count) { _, _ in
                QuotationMargin.freezeCosts(quotation, products: products)
            }
            .onAppear {
                syncOrderedItems()
                selectedStatus = quotation.status
                if original == nil { original = QuotationSnapshot(quotation) }
            }
            .onChange(of: quotation.items.count) { syncOrderedItems() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let original, QuotationSnapshot(quotation) != original {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(id: "ti_19_menu", placement: .topBarTrailing) {
                    Menu {
                        Button {
                            previewPDF()
                        } label: {
                            Label("Preview PDF", systemImage: "eye")
                        }
                        Button {
                            sharePDF()
                        } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            sendInfo = SendDocumentInfo.quotation(quotation)
                        } label: {
                            Label("Send to Customer…", systemImage: "paperplane")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(id: "ti_19", placement: .topBarTrailing) {
                    Button("Save") {
                        if saveContext(modelContext, action: "save quotation edits") {
                            dismiss()
                        } else {
                            showSaveErrorAlert = true
                        }
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                LineItemFormSheet(mode: .addToQuotation(quotation, modelContext: modelContext), products: products)
            }
            .sheet(item: $itemToEdit) { InlineEditItemSheet(item: $0) }
            .sheet(item: $sendInfo) { SendDocumentSheet(info: $0) }
            .sheet(item: $pdfToShare) { wrapped in
                ActivityShareSheet(items: [wrapped.url])
            }
            .sheet(isPresented: $showCustomerPicker) {
                ChangeCustomerSheet { newCustomer in
                    quotation.customerName          = "\(newCustomer.name) [\(newCustomer.company)]"
                    quotation.customerAddress       = newCustomer.address
                    quotation.customerPostcode      = newCustomer.postcode
                    quotation.customerState         = newCustomer.state
                    quotation.customerCountry       = newCustomer.country
                    quotation.customerContactNumber = newCustomer.contactNumber
                }
            }
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
                                Button {
                                    pdfToShare = wrapped
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                }
            }
            .confirmationDialog("Discard your changes to this quotation?",
                                isPresented: $showDiscardConfirm,
                                titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    discardChanges()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) { }
            }
            .alert("Save Failed", isPresented: $showSaveErrorAlert) {
                Button("OK") {}
            } message: {
                Text("Your changes could not be saved to the database. Please try again.")
            }
        }
        // iPad: open as a larger page-size sheet instead of a small form sheet.
        .presentationSizing(.page)
    }

    private func deleteItem(_ item: LineItem) {
        modelContext.delete(item)
        orderedItems.removeAll { $0.id == item.id }
    }

    /// Puts the quotation and its line items back to how they were when the
    /// editor opened (edits are applied live, so Cancel has to undo them).
    private func discardChanges() {
        guard let original else { return }
        original.restore(to: quotation, in: modelContext)
        _ = saveContext(modelContext, action: "discard quotation edits")
    }

    private func syncOrderedItems() {
        // Repair: if sortOrder values are not unique (older docs where all defaulted to 0),
        // freeze the current order and assign sequential sortOrders so drag/reorder works.
        let orders = quotation.items.map(\.sortOrder)
        if Set(orders).count != orders.count {
            for (index, item) in quotation.items.enumerated() {
                item.sortOrder = index
            }
        }
        orderedItems = quotation.items.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func sharePDF() {
        guard let url = PDFGenerator.generate(
            view: QuotationPDFView(quotation: quotation),
            filename: quotation.quoteNumber
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func previewPDF() {
        guard let url = PDFGenerator.generate(
            view: QuotationPDFView(quotation: quotation),
            filename: quotation.quoteNumber
        ) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }
}

// MARK: - Summary Card
// MARK: - Internal profit margin (PIN protected, never printed)
private struct QuotationMarginSection: View {
    let quotation: Quotation
    let products: [Product]

    @StateObject private var auth = AdminAuth.shared
    @AppStorage("showMarginBadge") private var showBadge = true
    @State private var showUnlock = false

    var body: some View {
        Section {
            if auth.isUnlocked {
                unlockedContent
            } else {
                Button { showUnlock = true } label: {
                    Label(auth.isPINSet ? "Unlock to view margin" : "Create PIN to view margin",
                          systemImage: "lock.fill")
                }
                .sheet(isPresented: $showUnlock) {
                    PINEntryView(
                        title: auth.isPINSet ? "Enter PIN" : "Create PIN",
                        subtitle: auth.isPINSet
                            ? "Enter your admin PIN to view profit margin."
                            : "Create a 6-digit PIN to protect profit margin and Settings.",
                        onSuccess: { auth.unlock(); showUnlock = false },
                        onCancel: { showUnlock = false },
                        isSetup: !auth.isPINSet,
                        allowReset: auth.isPINSet
                    )
                }
            }
        } header: {
            Text("Profit Margin (internal)")
        } footer: {
            Text("For your reference only. Not printed on the PDF.")
        }
        .onAppear {
            auth.checkTimeout()
            if auth.isUnlocked { QuotationMargin.freezeCosts(quotation, products: products) }
        }
        .onChange(of: auth.isUnlocked) { _, unlocked in
            if unlocked { QuotationMargin.freezeCosts(quotation, products: products) }
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        let m = QuotationMargin(quotation: quotation, products: products)
        if !m.hasData {
            Text("No cost yet. Open \"Cost & margin per item\" below and type a cost, or add a Cost Price in Directory.")
                .font(.footnote).foregroundColor(.secondary)
        } else {
            marginRow("Sell (after discount, before tax)", formatCurrency(m.revenue), .primary)
            marginRow("Cost", formatCurrency(m.cost), .primary)
            marginRow("Profit", formatCurrency(m.profit), m.profit >= 0 ? .green : .red)
            marginRow("Margin", m.margin.map { String(format: "%.1f%%", $0) } ?? "—",
                      (m.margin ?? 0) >= 0 ? .green : .red, bold: true)
        }
        if m.missingCount > 0 {
            Label("\(m.missingCount) of \(m.lines.count) items have no cost and are not counted.",
                  systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundColor(.orange)
        }
        DisclosureGroup("Cost & margin per item") {
            ForEach(m.lines) { line in
                MarginCostRow(line: line)
            }
            Text("Costs are saved on this quotation. Editing one does not change the product in Directory. Clear a cost to reload it from Directory.")
                .font(.caption).foregroundColor(.secondary)
        }
        Toggle("Show margin on quotation list", isOn: $showBadge)
        Button(role: .destructive) { auth.lock() } label: {
            Label("Lock", systemImage: "lock")
        }
    }

    private func marginRow(_ label: String, _ value: String, _ color: Color, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(bold ? .bold : .semibold).foregroundColor(color)
        }
    }
}

// One line's saved cost (per unit, after rebate) and its margin.
private struct MarginCostRow: View {
    let line: QuotationMargin.Line
    @State private var text = ""
    @FocusState private var focused: Bool

    private func syncText() {
        text = line.item.unitCost > 0 ? String(format: "%.2f", line.item.unitCost) : ""
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.item.itemCode).font(.subheadline)
                Text("Qty \(line.item.qty) · sell \(formatCurrency(line.item.unitPrice))")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            if line.directoryCost1 != nil || line.directoryCost2 != nil {
                Menu {
                    if let c1 = line.directoryCost1 {
                        Button("Use Cost 1  (\(formatCurrency(c1)))") { line.item.unitCost = c1 }
                    }
                    if let c2 = line.directoryCost2 {
                        Button("Use Cost 2  (\(formatCurrency(c2)))") { line.item.unitCost = c2 }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.footnote)
                }
                .buttonStyle(.borderless)
            }
            VStack(alignment: .trailing, spacing: 2) {
                TextField(line.directoryCost.map { String(format: "%.2f", $0) } ?? "Cost", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .frame(width: 90, height: 36)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: text) { _, new in
                        let v = Double(new.replacingOccurrences(of: ",", with: "")) ?? 0
                        if abs(line.item.unitCost - v) > 0.0001 { line.item.unitCost = max(0, v) }
                    }
                if let mg = line.margin {
                    Text(String(format: "%.1f%%", mg))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(mg < 0 ? .red : (mg < 10 ? .orange : .green))
                } else {
                    Text("no cost").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { syncText() }
        .onChange(of: line.item.unitCost) { _, _ in
            if !focused { syncText() }
        }
    }
}

private struct QuotationSummaryCard: View {
    @Bindable var quotation: Quotation
    @Binding var selectedStatus: QuotationStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quotation.quoteNumber.isEmpty ? "—" : quotation.quoteNumber)
                        .font(.title2).fontWeight(.bold)
                    if !quotation.customerName.isEmpty {
                        Text(quotation.customerName)
                            .font(.subheadline).foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption)
                    Text(quotation.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption).fontWeight(.medium)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.secondary.opacity(0.15))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
            }
            Divider()
            HStack {
                Text("Grand Total")
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text(formatCurrency(quotation.grandTotal))
                    .font(.title3).fontWeight(.bold).foregroundColor(.blue)
            }
            Picker("Status", selection: $selectedStatus) {
                ForEach(QuotationStatus.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedStatus) { _, s in quotation.status = s }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Change Customer Sheet
// Search-first flow that returns the selected customer via a callback.
private struct ChangeCustomerSheet: View {
    let onSelect: (Customer) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Customer.name) private var customers: [Customer]
    @State private var searchText = ""
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
                if filteredCustomers.isEmpty {
                    Section {
                        Text("No customers match \"\(searchText)\"")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    Section(searchText.isEmpty ? "All Customers" : "Matches") {
                        ForEach(filteredCustomers) { client in
                            Button {
                                onSelect(client)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name).fontWeight(.medium).foregroundColor(.primary)
                                    Text(client.company).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Change Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { searchFocused = true }
        }
    }
}


// MARK: - Snapshot (for Cancel)

private struct QuotationSnapshot: Equatable {
    var date: Date
    var quoteNumber: String
    var customerName: String
    var customerAddress: String
    var customerPostcode: String
    var customerState: String
    var customerCountry: String
    var customerContactNumber: String
    var remarks: String
    var bankAccountNumber: String
    var paymentTerm: String
    var studentName: String
    var studentID: String
    var statusRaw: String
    var discountPct: Double
    var discountFixed: Double
    var taxPct: Double
    var taxLabel: String
    var items: [PersistentIdentifier: ItemSnapshot]

    init(_ q: Quotation) {
        date = q.date
        quoteNumber = q.quoteNumber
        customerName = q.customerName
        customerAddress = q.customerAddress
        customerPostcode = q.customerPostcode
        customerState = q.customerState
        customerCountry = q.customerCountry
        customerContactNumber = q.customerContactNumber
        remarks = q.remarks
        bankAccountNumber = q.bankAccountNumber
        paymentTerm = q.paymentTerm
        studentName = q.studentName
        studentID = q.studentID
        statusRaw = q.statusRaw
        discountPct = q.discountPct
        discountFixed = q.discountFixed
        taxPct = q.taxPct
        taxLabel = q.taxLabel
        items = Dictionary(uniqueKeysWithValues: q.items.map {
            ($0.persistentModelID, ItemSnapshot($0))
        })
    }

    func restore(to q: Quotation, in context: ModelContext) {
        q.date = date
        q.quoteNumber = quoteNumber
        q.customerName = customerName
        q.customerAddress = customerAddress
        q.customerPostcode = customerPostcode
        q.customerState = customerState
        q.customerCountry = customerCountry
        q.customerContactNumber = customerContactNumber
        q.remarks = remarks
        q.bankAccountNumber = bankAccountNumber
        q.paymentTerm = paymentTerm
        q.studentName = studentName
        q.studentID = studentID
        q.statusRaw = statusRaw
        q.discountPct = discountPct
        q.discountFixed = discountFixed
        q.taxPct = taxPct
        q.taxLabel = taxLabel

        // Items added during this edit: remove them.
        for item in Array(q.items) where items[item.persistentModelID] == nil {
            q.items.removeAll { $0.persistentModelID == item.persistentModelID }
            context.delete(item)
        }
        // Items that existed: put values back, or re-create if deleted.
        for snap in items.values {
            if let existing = q.items.first(where: { $0.persistentModelID == snap.id }) {
                snap.apply(to: existing)
            } else {
                let restored = LineItem(itemCode: snap.itemCode,
                                        itemDescription: snap.itemDescription,
                                        qty: snap.qty,
                                        unitPrice: snap.unitPrice,
                                        sortOrder: snap.sortOrder)
                snap.apply(to: restored)
                context.insert(restored)
                q.items.append(restored)
            }
        }
    }
}
