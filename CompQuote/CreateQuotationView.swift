import SwiftUI
import SwiftData

struct CreateQuotationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Quotation.date, order: .reverse) private var existingQuotations: [Quotation]
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Product.itemCode) private var products: [Product]

    @AppStorage(AppStorageKeys.defaultRemarks)      private var storedRemarks = ""
    @AppStorage(AppStorageKeys.defaultBankAccount)  private var storedBankAccount = ""
    @AppStorage(AppStorageKeys.defaultPaymentTerm)  private var storedPaymentTerm = ""

    @State private var quoteNumber = ""
    @State private var date = Date()
    // Customer
    @State private var customerSearchText = ""
    @State private var selectedCustomer: Customer?
    @State private var customerToDuplicate: Customer?
    @State private var showAddCustomer = false
    // Items
    @State private var tempItems: [TempLineItem] = []
    @State private var showAddItemSheet = false
    // Discount & Tax
    @State private var discountPct: Double = 0
    @State private var discountFixed: Double = 0
    @State private var taxPct: Double = 0
    @State private var taxLabel: String = "SST"
    // Payment & Remarks
    @State private var paymentTerm = ""
    @State private var bankAccountNumber = ""
    @State private var remarks = ""
    // Student details (optional — shown on PDF only when filled)
    @State private var studentName = ""
    @State private var studentID = ""
    // Save validation
    @State private var showDuplicateNumberAlert = false
    @State private var showSaveErrorAlert = false

    // Computed totals for the temp items
    private var itemsSubtotal:  Double { tempItems.reduce(0) { $0 + $1.subTotal } }
    private var discountAmount: Double { (itemsSubtotal * discountPct / 100) + discountFixed }
    private var taxableAmount:  Double { max(0, itemsSubtotal - discountAmount) }
    private var taxAmount:      Double { taxableAmount * taxPct / 100 }
    private var grandTotal:     Double { taxableAmount + taxAmount }

    var filteredCustomers: [Customer] {
        let tokens = customerSearchText
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
            ZStack(alignment: .bottom) {
                Form {
                    // ── Document Details ──────────────────────────────────
                    Section("Document Details") {
                        TextField("Quotation Number", text: $quoteNumber).autocorrectionDisabled()
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }

                    // ── Customer ──────────────────────────────────────────
                    Section("Customer") {
                        if let selected = selectedCustomer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selected.name).fontWeight(.semibold)
                                    Text(selected.company).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Change") { selectedCustomer = nil; customerSearchText = "" }
                                    .font(.footnote).foregroundColor(.blue)
                            }
                        } else {
                            TextField("Search customer name or company…", text: $customerSearchText)
                                .autocorrectionDisabled()

                            if !customerSearchText.isEmpty {
                                ForEach(filteredCustomers) { client in
                                    HStack {
                                        Button {
                                            selectedCustomer = client
                                            customerSearchText = ""
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
                                    // Swipe alternative also available
                                    .swipeActions(edge: .trailing) {
                                        Button {
                                            customerToDuplicate = client
                                        } label: {
                                            Label("Duplicate", systemImage: "person.badge.plus")
                                        }
                                        .tint(.orange)
                                    }
                                }

                                // Not found — offer to add new or duplicate closest match
                                if filteredCustomers.isEmpty {
                                    Text("No customer found for \"\(customerSearchText)\"")
                                        .font(.caption).foregroundColor(.secondary)

                                    Button {
                                        showAddCustomer = true
                                    } label: {
                                        Label("Add \"\(customerSearchText)\" as new customer", systemImage: "person.crop.circle.badge.plus")
                                            .font(.footnote)
                                    }
                                    .buttonStyle(.borderless)

                                    if let closest = customers.first {
                                        Button {
                                            customerToDuplicate = closest
                                        } label: {
                                            Label("Duplicate an existing customer…", systemImage: "person.badge.plus")
                                                .font(.footnote)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                        }
                    }

                    // ── Student Details (optional) ─────────────────────────
                    Section {
                        TextField("Student Name", text: $studentName)
                        TextField("Student ID", text: $studentID)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Student Details (optional)")
                    } footer: {
                        Text("Shown on the quotation PDF below Bill To when filled.")
                            .font(.caption)
                    }

                    // ── Line Items ────────────────────────────────────────
                    Section("Line Items") {
                        if tempItems.isEmpty {
                            Label("No items added yet.", systemImage: "tray")
                                .foregroundColor(.secondary).font(.subheadline)
                        }
                        ForEach(tempItems) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.itemCode).font(.headline)
                                    Text(item.itemDescription).font(.caption).foregroundColor(.secondary)
                                    Text("Qty: \(item.qty) × \(formatCurrency(item.unitPrice))").font(.footnote)
                                }
                                Spacer()
                                Text(formatCurrency(item.subTotal)).fontWeight(.semibold)
                            }
                        }
                        .onDelete { tempItems.remove(atOffsets: $0) }
                        Button { showAddItemSheet = true } label: {
                            Label("Add Item", systemImage: "plus.circle")
                        }
                    }

                    // ── Discount & Tax ────────────────────────────────────
                    DiscountTaxSection(
                        discountPct:    $discountPct,
                        discountFixed:  $discountFixed,
                        taxPct:         $taxPct,
                        taxLabel:       $taxLabel,
                        itemsSubtotal:  itemsSubtotal,
                        discountAmount: discountAmount,
                        taxAmount:      taxAmount,
                        grandTotal:     grandTotal
                    )

                    // ── Payment & Remarks ─────────────────────────────────
                    Section("Payment & Remarks") {
                        TextField("Bank Account Number", text: $bankAccountNumber)

                        Menu {
                            Button("None") { paymentTerm = "" }
                            Divider()
                            ForEach(standardPaymentTerms, id: \.self) { term in
                                Button { paymentTerm = term } label: {
                                    HStack {
                                        Text(term)
                                        if paymentTerm == term { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Payment Terms").foregroundColor(.primary)
                                Spacer()
                                Text(paymentTerm.isEmpty ? "Select…" : paymentTerm)
                                    .foregroundColor(paymentTerm.isEmpty ? .secondary : .primary)
                                    .multilineTextAlignment(.trailing)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }

                        TextField("Remarks / Notes", text: $remarks, axis: .vertical).lineLimit(3...5)
                    }

                    Color.clear.frame(height: 80).listRowBackground(Color.clear)
                }

                // Sticky totals bar
                if !tempItems.isEmpty {
                    TotalsSummaryBar(
                        itemsSubtotal:  itemsSubtotal,
                        discountAmount: discountAmount,
                        taxAmount:      taxAmount,
                        taxLabel:       taxLabel,
                        grandTotal:     grandTotal
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tempItems.isEmpty)
            .navigationTitle("New Quotation")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Numeric-aware: picks the true highest existing number, not
                // the most recent by date or a string-sorted maximum.
                quoteNumber = DocumentNumberGenerator.next(
                    inAll: existingQuotations.map(\.quoteNumber),
                    prefix: UserDefaults.standard.string(forKey: AppStorageKeys.quotationNumberPrefix) ?? ""
                ) ?? "QT-2026-001"
                if remarks.isEmpty { remarks = storedRemarks }
                if bankAccountNumber.isEmpty { bankAccountNumber = storedBankAccount }
                if paymentTerm.isEmpty { paymentTerm = storedPaymentTerm }
            }
            .prefixPrompt(.quotation) {
                let p = UserDefaults.standard.string(forKey: AppStorageKeys.quotationNumberPrefix) ?? ""
                quoteNumber = DocumentNumberGenerator.next(
                    inAll: existingQuotations.map(\.quoteNumber), prefix: p) ?? "QT-2026-001"
            }
            .toolbar {
                ToolbarItem(id: "create-qt-cancel", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "create-qt-save", placement: .topBarTrailing) {
                    Button("Save") { saveQuotation() }
                        .disabled(quoteNumber.isEmpty || selectedCustomer == nil || tempItems.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                LineItemFormSheet(mode: .addToTemp(binding: $tempItems), products: products)
            }
            .sheet(item: $customerToDuplicate) { original in
                DuplicateCustomerSheet(original: original) { newCustomer in
                    selectedCustomer = newCustomer
                    customerSearchText = ""
                }
            }
            .sheet(isPresented: $showAddCustomer) {
                AddCustomerSheet(prefilledName: customerSearchText) { newCustomer in
                    selectedCustomer = newCustomer
                    customerSearchText = ""
                }
            }
            .alert("Duplicate Number", isPresented: $showDuplicateNumberAlert) {
                Button("OK") {}
            } message: {
                Text("A quotation with the number \"\(quoteNumber)\" already exists. Please use a different number.")
            }
            .alert("Save Failed", isPresented: $showSaveErrorAlert) {
                Button("OK") {}
            } message: {
                Text("The quotation could not be saved to the database. Please try again, and export a backup from Settings if the problem continues.")
            }
        }
        .presentationSizing(.page)
    }

    private func saveQuotation() {
        guard let customer = selectedCustomer else { return }
        // Prevent two documents from sharing the same number.
        guard !existingQuotations.contains(where: { $0.quoteNumber == quoteNumber }) else {
            showDuplicateNumberAlert = true
            return
        }
        let newQuote = Quotation(
            quoteNumber: quoteNumber,
            customerName: "\(customer.name) [\(customer.company)]",
            remarks: remarks,
            bankAccountNumber: bankAccountNumber
        )
        newQuote.date              = date
        newQuote.paymentTerm       = paymentTerm
        newQuote.discountPct       = discountPct
        newQuote.discountFixed     = discountFixed
        newQuote.taxPct            = taxPct
        newQuote.taxLabel          = taxLabel
        newQuote.studentName       = studentName
        newQuote.studentID         = studentID
        newQuote.customerAddress       = customer.address
        newQuote.customerPostcode      = customer.postcode
        newQuote.customerState         = customer.state
        newQuote.customerCountry       = customer.country
        newQuote.customerContactNumber = customer.contactNumber
        for (index, temp) in tempItems.enumerated() {
            let line = LineItem(
                itemCode: temp.itemCode,
                itemDescription: temp.itemDescription,
                qty: temp.qty,
                unitPrice: temp.unitPrice,
                sortOrder: index
            )
            line.unitCost = temp.unitCost
            newQuote.items.append(line)
        }
        QuotationMargin.freezeCosts(newQuote, products: products)
        modelContext.insert(newQuote)
        if saveContext(modelContext, action: "save quotation") {
            dismiss()
        } else {
            showSaveErrorAlert = true
        }
    }
}
