import SwiftUI
import SwiftData

// MARK: - Invoice flow
// One sheet for the whole "Create Invoice" journey, so the caller only presents it:
//   locked  -> upgrade screen (swaps to the form the moment the purchase succeeds)
//   unlocked -> Create Invoice form
//   created -> the new invoice, ready to review and share
struct InvoiceFlowSheet: View {
    let quotation: Quotation
    @ObservedObject private var store = SyncStore.shared
    @State private var created: Invoice?

    var body: some View {
        if let invoice = created {
            EditInvoiceView(invoice: invoice)
        } else if store.isUnlocked {
            CreateInvoiceSheet(quotation: quotation) { created = $0 }
        } else {
            ProUpgradeSheet(dismissWhenUnlocked: false)
        }
    }
}

// MARK: - Amounts before the invoice exists
struct InvoiceAmounts {
    let subtotal: Double
    let discountPct: Double
    let discountFixed: Double
    let taxPct: Double

    var discount: Double { subtotal * discountPct / 100 + discountFixed }
    var taxable: Double { max(0, subtotal - discount) }
    var tax: Double { taxable * taxPct / 100 }
    var total: Double { taxable + tax }
}

extension Invoice {
    /// Safe to use as a PDF file name.
    var pdfFileName: String {
        invoiceNumber.replacingOccurrences(of: "/", with: "-")
    }

    /// Extra line under the customer name in lists.
    var listNote: String? {
        if status == .paid {
            guard let paid = paidDate else { return nil }
            return "Paid " + shortDocumentDate(paid)
        }
        if isOverdue {
            let d = daysOverdue
            return "Overdue \(d) day\(d == 1 ? "" : "s") · Balance \(formatCurrency(balanceDue))"
        }
        if isPartiallyPaid { return "Balance \(formatCurrency(balanceDue))" }
        if let due = dueDate { return "Due " + shortDocumentDate(due) }
        return nil
    }
}

// MARK: - Invoice row (Documents list + Fulfill detail)
struct InvoiceDocumentRow: View {
    let invoice: Invoice

    var body: some View {
        DocumentRow(
            primaryLabel: invoice.invoiceNumber,
            secondaryLabel: invoice.customerName,
            date: invoice.date,
            total: invoice.grandTotal,
            accentColor: .indigo,
            icon: invoice.displayIcon,
            statusLabel: invoice.displayStatus,
            statusColor: invoice.displayColor,
            note: invoice.listNote
        )
    }
}

// MARK: - Create Invoice
struct CreateInvoiceSheet: View {
    let quotation: Quotation
    let onCreated: (Invoice) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var invoices: [Invoice]

    @State private var invoiceNumber = ""
    @State private var date = Date()
    @State private var selected: Set<PersistentIdentifier> = []
    @State private var didLoad = false
    @FocusState private var numberFocused: Bool

    /// Delivered items that are not on an invoice yet.
    private var available: [LineItem] { quotation.uninvoicedDeliveredItems }
    private var chosen: [LineItem] { available.filter { selected.contains($0.persistentModelID) } }
    private var previousInvoices: [Invoice] {
        invoices.filter { $0.quotationId == quotation.id.uuidString }
    }
    private var trimmedNumber: String {
        invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var isDuplicate: Bool {
        invoices.contains { $0.invoiceNumber.lowercased() == trimmedNumber.lowercased() }
    }
    private var canCreate: Bool { !chosen.isEmpty && !trimmedNumber.isEmpty && !isDuplicate }

    private var amounts: InvoiceAmounts {
        InvoiceAmounts(
            subtotal: chosen.reduce(0) { $0 + $1.subTotal },
            discountPct: quotation.discountPct,
            discountFixed: quotation.fixedDiscountShare(for: chosen, previousInvoices: previousInvoices),
            taxPct: quotation.taxPct
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Quotation", value: quotation.quoteNumber)
                    LabeledContent("Customer", value: quotation.customerName)
                }

                Section {
                    if available.isEmpty {
                        Text("Every delivered item is already on an invoice.")
                            .font(.subheadline).foregroundColor(.secondary)
                    } else {
                        ForEach(available) { item in
                            Button { toggle(item) } label: {
                                itemRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Items to Invoice")
                } footer: {
                    Text("Only delivered items that are not on an invoice yet are listed. Untick an item to bill it on a later invoice.")
                }

                Section("Invoice") {
                    HStack {
                        Text("Number")
                        Spacer()
                        TextField("Invoice No.", text: $invoiceNumber)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .focused($numberFocused)
                    }
                    if isDuplicate {
                        Label("This invoice number is already used.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.red)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                InvoiceTotalsSection(subtotal: amounts.subtotal,
                                     discount: amounts.discount,
                                     tax: amounts.tax,
                                     taxLabel: quotation.taxLabel,
                                     total: amounts.total)
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "inv-create-cancel", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "inv-create-save", placement: .topBarTrailing) {
                    Button("Create") { create() }.disabled(!canCreate)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { numberFocused = false }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                invoiceNumber = nextNumber()
                selected = Set(available.map(\.persistentModelID))
            }
            .prefixPrompt(.invoice) { invoiceNumber = nextNumber() }
        }
    }

    // MARK: Pieces
    private func itemRow(_ item: LineItem) -> some View {
        let isOn = selected.contains(item.persistentModelID)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(isOn ? .indigo : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.itemCode).font(.headline).foregroundColor(.primary)
                Text(item.itemDescription)
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Qty \(item.qty) × \(formatCurrency(item.unitPrice))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Text(formatCurrency(item.subTotal))
                .fontWeight(.semibold).foregroundColor(.primary)
        }
        .contentShape(Rectangle())
    }

    private func toggle(_ item: LineItem) {
        let id = item.persistentModelID
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func nextNumber() -> String {
        let prefix = UserDefaults.standard.string(forKey: AppStorageKeys.invoiceNumberPrefix) ?? ""
        let year = Calendar.current.component(.year, from: Date())
        return DocumentNumberGenerator.next(inAll: invoices.map(\.invoiceNumber), prefix: prefix)
            ?? "INV-\(year)-001"
    }

    // MARK: Create
    private func create() {
        let items = chosen
        guard canCreate, !items.isEmpty else { return }

        let invoice = Invoice(invoiceNumber: trimmedNumber, customerName: quotation.customerName)
        invoice.date                  = date
        invoice.quotationId           = quotation.id.uuidString
        invoice.quotationNumber       = quotation.quoteNumber
        invoice.customerAddress       = quotation.customerAddress
        invoice.customerPostcode      = quotation.customerPostcode
        invoice.customerState         = quotation.customerState
        invoice.customerCountry       = quotation.customerCountry
        invoice.customerContactNumber = quotation.customerContactNumber
        invoice.studentName           = quotation.studentName
        invoice.studentID             = quotation.studentID
        invoice.remarks               = quotation.remarks
        invoice.bankAccountNumber     = quotation.bankAccountNumber
        invoice.paymentTerm           = quotation.paymentTerm
        invoice.discountPct           = quotation.discountPct
        invoice.discountFixed         = amounts.discountFixed
        invoice.taxPct                = quotation.taxPct
        invoice.taxLabel              = quotation.taxLabel

        // The invoice keeps its own copies of the items.
        for (index, source) in items.enumerated() {
            invoice.items.append(LineItem(itemCode: source.itemCode,
                                          itemDescription: source.itemDescription,
                                          qty: source.qty,
                                          unitPrice: source.unitPrice,
                                          sortOrder: index))
        }
        modelContext.insert(invoice)
        // Mark the quotation's items as billed, so they cannot be invoiced twice.
        for source in items { source.invoiceId = invoice.id.uuidString }
        saveContext(modelContext, action: "create invoice")
        onCreated(invoice)
    }
}

// MARK: - Totals section (Create + Edit)
struct InvoiceTotalsSection: View {
    let subtotal: Double
    let discount: Double
    let tax: Double
    let taxLabel: String
    let total: Double

    var body: some View {
        Section("Totals") {
            row("Subtotal", formatCurrency(subtotal), .secondary)
            if discount > 0 {
                row("Discount", "-" + formatCurrency(discount), .orange)
            }
            if tax > 0 {
                row(taxLabel.isEmpty ? "Tax" : taxLabel, "+" + formatCurrency(tax), .secondary)
            }
            HStack {
                Text("Total").fontWeight(.bold)
                Spacer()
                Text(formatCurrency(total))
                    .font(.title3.bold()).foregroundColor(.indigo)
            }
        }
    }

    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).foregroundColor(color)
            Spacer()
            Text(value).foregroundColor(color)
        }
    }
}

// MARK: - Edit / view an invoice
struct EditInvoiceView: View {
    @Bindable var invoice: Invoice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allInvoices: [Invoice]
    @State private var pdfToShare: IdentifiableURL?
    @State private var pdfToPreview: IdentifiableURL?
    @State private var showAddPayment = false
    @State private var sendInfo: SendDocumentInfo?
    @State private var showClearPayments = false
    @FocusState private var anyFocused: Bool

    /// Why the number cannot be kept, or nil when it is fine.
    private var numberProblem: String? {
        let number = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if number.isEmpty { return "Enter an invoice number." }
        let clash = allInvoices.contains {
            $0.persistentModelID != invoice.persistentModelID && $0.invoiceNumber.lowercased() == number
        }
        return clash ? "This invoice number is already used." : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(invoice.displayStatus, systemImage: invoice.displayIcon)
                                .font(.headline)
                                .foregroundColor(invoice.displayColor)
                            Spacer()
                            Text(formatCurrency(invoice.grandTotal)).font(.headline)
                        }
                        ProgressView(value: min(invoice.paidAmount, invoice.grandTotal),
                                     total: max(invoice.grandTotal, 0.01))
                            .tint(invoice.status == .paid ? .green : .blue)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Received").font(.caption).foregroundColor(.secondary)
                                Text(formatCurrency(invoice.paidAmount)).fontWeight(.semibold)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Balance due").font(.caption).foregroundColor(.secondary)
                                Text(formatCurrency(invoice.balanceDue))
                                    .fontWeight(.semibold)
                                    .foregroundColor(invoice.balanceDue > 0.005 ? .orange : .green)
                            }
                        }
                        if let due = invoice.dueDate, invoice.status != .paid {
                            Text(invoice.isOverdue
                                 ? "Due \(shortDocumentDate(due)) · \(invoice.daysOverdue) day\(invoice.daysOverdue == 1 ? "" : "s") overdue"
                                 : "Due \(shortDocumentDate(due))")
                                .font(.caption)
                                .foregroundColor(invoice.isOverdue ? .red : .secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if invoice.balanceDue > 0.005 {
                        Button { showAddPayment = true } label: {
                            Label("Record Payment", systemImage: "banknote")
                                .fontWeight(.semibold)
                        }
                        Button { invoice.markFullyPaid() } label: {
                            Label("Mark Fully Paid", systemImage: "checkmark.seal.fill")
                        }
                        .tint(.green)
                    }

                    ForEach(invoice.payments) { payment in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(formatCurrency(payment.amount)).fontWeight(.semibold)
                                Spacer()
                                Text(shortDocumentDate(payment.date)).foregroundColor(.secondary)
                            }
                            Text(([payment.method] + (payment.note.isEmpty ? [] : [payment.note])).joined(separator: " · "))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        let list = invoice.payments
                        for index in offsets { invoice.removePayment(id: list[index].id) }
                    }

                    if invoice.paidAmount > 0.005 {
                        Button(role: .destructive) { showClearPayments = true } label: {
                            Label("Clear All Payments", systemImage: "arrow.uturn.backward")
                        }
                    }
                } header: {
                    Text("Payment")
                } footer: {
                    Text("Tap Record Payment each time the customer pays, even part of the amount. The invoice becomes Paid once payments cover the total. Swipe a payment left to remove it.")
                }

                Section("Invoice") {
                    HStack {
                        Text("Number")
                        Spacer()
                        TextField("Invoice No.", text: $invoice.invoiceNumber)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .focused($anyFocused)
                    }
                    if let problem = numberProblem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.red)
                    }
                    DatePicker("Date", selection: $invoice.date, displayedComponents: .date)
                    if !invoice.quotationNumber.isEmpty {
                        LabeledContent("Quotation", value: invoice.quotationNumber)
                    }
                    if let due = invoice.dueDate, invoice.status != .paid {
                        LabeledContent("Due") {
                            Text(shortDocumentDate(due))
                                .foregroundColor(invoice.isOverdue ? .red : .secondary)
                        }
                    }
                }

                Section("Bill To") {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(invoice.customerName).fontWeight(.semibold)
                        if !invoice.customerFullAddress.isEmpty {
                            Text(invoice.customerFullAddress)
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        if !invoice.customerContactNumber.isEmpty {
                            Text(invoice.customerContactNumber)
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        if !invoice.studentName.isEmpty || !invoice.studentID.isEmpty {
                            Text([invoice.studentName, invoice.studentID.isEmpty ? "" : "ID: \(invoice.studentID)"]
                                .filter { !$0.isEmpty }.joined(separator: "  ·  "))
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    ForEach(invoice.sortedItems) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.itemCode).font(.headline)
                                Text(item.itemDescription)
                                    .font(.caption).foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Qty \(item.qty) × \(formatCurrency(item.unitPrice))")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 8)
                            Text(formatCurrency(item.subTotal)).fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Items")
                } footer: {
                    Text("To change the items, delete this invoice and create it again. Its items go back to the quotation.")
                }

                InvoiceTotalsSection(subtotal: invoice.itemsSubtotal,
                                     discount: invoice.discountAmount,
                                     tax: invoice.taxAmount,
                                     taxLabel: invoice.taxLabel,
                                     total: invoice.grandTotal)

                Section("Payment & Remarks") {
                    TextField("Payment terms", text: $invoice.paymentTerm)
                        .focused($anyFocused)
                    TextField("Bank account (blank = Settings default)", text: $invoice.bankAccountNumber)
                        .autocorrectionDisabled()
                        .focused($anyFocused)
                    TextField("Remarks", text: $invoice.remarks, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($anyFocused)
                }

                DeleteRecordSection(title: "Delete Invoice", itemName: invoice.invoiceNumber) {
                    deleteInvoice()
                }
            }
            .navigationTitle(invoice.invoiceNumber)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(numberProblem != nil)
            .toolbar {
                ToolbarItem(id: "inv-edit-share", placement: .topBarLeading) {
                    Menu {
                        Button { previewPDF() } label: {
                            Label("Preview PDF", systemImage: "eye")
                        }
                        Button { sharePDF() } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        Button { sendInfo = SendDocumentInfo.invoice(invoice) } label: {
                            Label("Send to Customer…", systemImage: "paperplane")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(id: "inv-edit-done", placement: .topBarTrailing) {
                    Button("Done") {
                        saveContext(modelContext, action: "save invoice")
                        dismiss()
                    }
                    .disabled(numberProblem != nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
            .sheet(item: $pdfToShare) { wrapped in
                ActivityShareSheet(items: [wrapped.url])
            }
            .confirmationDialog("Clear all payments?", isPresented: $showClearPayments, titleVisibility: .visible) {
                Button("Clear Payments", role: .destructive) { invoice.markUnpaid() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The invoice goes back to Unpaid.")
            }
            .sheet(isPresented: $showAddPayment) {
                AddPaymentSheet(balance: invoice.balanceDue) { invoice.addPayment($0) }
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
        }
    }

    private func sharePDF() {
        guard let url = PDFGenerator.generate(
            view: InvoicePDFView(invoice: invoice),
            filename: invoice.pdfFileName
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func previewPDF() {
        guard let url = PDFGenerator.generate(
            view: InvoicePDFView(invoice: invoice),
            filename: invoice.pdfFileName
        ) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }

    private func deleteInvoice() {
        // Give the billed items back to the quotation first.
        invoice.releaseItems(in: modelContext)
        modelContext.deleteAfterSheetCloses(invoice)
        dismiss()
    }
}

// MARK: - Payments
struct InvoicePayment: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double
    var method: String
    var note: String
}

let invoicePaymentMethods = ["Bank Transfer", "Cash", "Cheque", "Card", "Online Payment", "Other"]

extension Invoice {
    /// Payments received, oldest first. Stored as JSON text in `paymentsJSON`.
    var payments: [InvoicePayment] {
        get {
            guard !paymentsJSON.isEmpty,
                  let data = paymentsJSON.data(using: .utf8),
                  let list = try? JSONDecoder().decode([InvoicePayment].self, from: data) else { return [] }
            return list.sorted { $0.date < $1.date }
        }
        set {
            if newValue.isEmpty {
                paymentsJSON = ""
            } else if let data = try? JSONEncoder().encode(newValue),
                      let text = String(data: data, encoding: .utf8) {
                paymentsJSON = text
            }
        }
    }

    /// Amount received. Older invoices marked Paid before payments existed count as fully paid.
    var paidAmount: Double {
        let list = payments
        if list.isEmpty { return status == .paid ? grandTotal : 0 }
        return list.reduce(0) { $0 + $1.amount }
    }

    var balanceDue: Double {
        status == .paid ? 0 : max(0, grandTotal - paidAmount)
    }

    var isPartiallyPaid: Bool { status == .unpaid && paidAmount > 0.005 }

    /// Invoice date plus the number of days in the payment term ("Net 30 Days" → 30).
    /// Terms without a number of days (e.g. "Bank Transfer") have no due date.
    var dueDate: Date? {
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*days?", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(paymentTerm.startIndex..., in: paymentTerm)
        guard let match = regex.firstMatch(in: paymentTerm, range: range),
              let numRange = Range(match.range(at: 1), in: paymentTerm),
              let days = Int(paymentTerm[numRange]) else { return nil }
        return Calendar.current.date(byAdding: .day, value: days, to: date)
    }

    var daysOverdue: Int {
        guard let due = dueDate else { return 0 }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: due), to: cal.startOfDay(for: Date())).day ?? 0)
    }

    var isOverdue: Bool { status == .unpaid && balanceDue > 0.005 && daysOverdue > 0 }

    var displayStatus: String {
        if status == .paid { return "Paid" }
        if isOverdue { return "Overdue" }
        if isPartiallyPaid { return "Partial" }
        return "Unpaid"
    }

    var displayColor: Color {
        if status == .paid { return .green }
        if isOverdue { return .red }
        if isPartiallyPaid { return .blue }
        return .orange
    }

    var displayIcon: String {
        if status == .paid { return status.icon }
        if isOverdue { return "exclamationmark.triangle.fill" }
        if isPartiallyPaid { return "circle.lefthalf.filled" }
        return status.icon
    }

    func addPayment(_ payment: InvoicePayment) {
        var list = payments
        list.append(payment)
        payments = list
        syncPaymentStatus()
    }

    func removePayment(id: UUID) {
        let list = payments.filter { $0.id != id }
        if list.isEmpty { markUnpaid(); return }
        payments = list
        syncPaymentStatus()
    }

    /// Records the remaining balance as a payment and marks the invoice paid.
    func markFullyPaid(on day: Date = Date()) {
        let left = balanceDue
        if left > 0.005 {
            addPayment(InvoicePayment(date: day, amount: left, method: "Marked paid", note: ""))
        } else {
            status = .paid
            paidDate = paidDate ?? day
        }
    }

    func markUnpaid() {
        payments = []
        status = .unpaid
        paidDate = nil
    }

    /// Paid once the payments cover the total, otherwise unpaid.
    private func syncPaymentStatus() {
        let list = payments
        guard !list.isEmpty else { return }
        let received = list.reduce(0) { $0 + $1.amount }
        if grandTotal - received <= 0.005 {
            status = .paid
            paidDate = list.last?.date
        } else {
            status = .unpaid
            paidDate = nil
        }
    }
}

// MARK: - Add payment
struct AddPaymentSheet: View {
    let balance: Double
    let onSave: (InvoicePayment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: Double
    @State private var date = Date()
    @State private var method = invoicePaymentMethods[0]
    @State private var note = ""
    @FocusState private var amountFocused: Bool

    init(balance: Double, onSave: @escaping (InvoicePayment) -> Void) {
        self.balance = balance
        self.onSave = onSave
        _amount = State(initialValue: (balance * 100).rounded() / 100)
    }

    private var problem: String? {
        if amount <= 0 { return "Enter an amount." }
        if amount > balance + 0.005 { return "More than the balance due (\(formatCurrency(balance)))." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", value: $amount, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.red)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Method", selection: $method) {
                        ForEach(invoicePaymentMethods, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Balance due: \(formatCurrency(balance))")
                }
            }
            .navigationTitle("Add Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "pay-cancel", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "pay-save", placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(InvoicePayment(date: date, amount: amount, method: method, note: note))
                        dismiss()
                    }
                    .disabled(problem != nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
