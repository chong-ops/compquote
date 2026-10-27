import SwiftUI
import SwiftData

struct CreatePurchaseOrderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PurchaseOrder.date, order: .reverse) private var existingPOs: [PurchaseOrder]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \Product.itemCode) private var products: [Product]

    @State private var poNumber = ""
    @State private var date = Date()
    @State private var vendorSearchText = ""
    @State private var selectedVendor: Vendor?
    @State private var tempItems: [TempLineItem] = []
    @State private var showAddItemSheet = false
    // Discount & Tax
    @State private var discountPct: Double = 0
    @State private var discountFixed: Double = 0
    @State private var taxPct: Double = 0
    @State private var taxLabel: String = "SST"
    // Terms
    @State private var remarks = ""
    @State private var deliveryInstructions = ""
    // Save validation
    @State private var showDuplicateNumberAlert = false
    @State private var showSaveErrorAlert = false

    // Computed totals
    private var itemsSubtotal:  Double { tempItems.reduce(0) { $0 + $1.subTotal } }
    private var discountAmount: Double { (itemsSubtotal * discountPct / 100) + discountFixed }
    private var taxableAmount:  Double { max(0, itemsSubtotal - discountAmount) }
    private var taxAmount:      Double { taxableAmount * taxPct / 100 }
    private var grandTotal:     Double { taxableAmount + taxAmount }

    var filteredVendors: [Vendor] {
        guard !vendorSearchText.isEmpty else { return vendors }
        return vendors.filter {
            $0.name.localizedCaseInsensitiveContains(vendorSearchText) ||
            $0.company.localizedCaseInsensitiveContains(vendorSearchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Form {
                    // ── PO Details ────────────────────────────────────────
                    Section("PO Details") {
                        TextField("PO Number", text: $poNumber).autocorrectionDisabled()
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }

                    // ── Vendor ────────────────────────────────────────────
                    Section("Supplier / Vendor") {
                        if let vendor = selectedVendor {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(vendor.name).fontWeight(.semibold)
                                    Text(vendor.company).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Change") { selectedVendor = nil; vendorSearchText = "" }
                                    .font(.footnote).foregroundColor(.blue)
                            }
                        } else {
                            TextField("Search vendor name or company…", text: $vendorSearchText)
                                .autocorrectionDisabled()
                            if !vendorSearchText.isEmpty {
                                ForEach(filteredVendors) { vendor in
                                    Button {
                                        selectedVendor = vendor
                                        vendorSearchText = ""
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(vendor.name).fontWeight(.medium).foregroundColor(.primary)
                                            Text(vendor.company).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
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

                    // ── Terms ─────────────────────────────────────────────
                    Section("Terms & Conditions") {
                        TextField("Remarks / Payment Terms", text: $remarks, axis: .vertical).lineLimit(2...4)
                        TextField("Delivery Instructions", text: $deliveryInstructions, axis: .vertical).lineLimit(2...4)
                    }

                    Color.clear.frame(height: 80).listRowBackground(Color.clear)
                }

                if !tempItems.isEmpty {
                    TotalsSummaryBar(
                        itemsSubtotal:  itemsSubtotal,
                        discountAmount: discountAmount,
                        taxAmount:      taxAmount,
                        taxLabel:       taxLabel,
                        grandTotal:     grandTotal,
                        accentColor:    .green
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tempItems.isEmpty)
            .navigationTitle("New Purchase Order")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Numeric-aware: picks the true highest existing number.
                poNumber = DocumentNumberGenerator.next(
                    inAll: existingPOs.map(\.poNumber),
                    prefix: UserDefaults.standard.string(forKey: AppStorageKeys.poNumberPrefix) ?? ""
                ) ?? "PO-2026-001"
                if remarks.isEmpty {
                    remarks = UserDefaults.standard.string(forKey: AppStorageKeys.defaultPORemarks) ?? ""
                }
                if deliveryInstructions.isEmpty {
                    deliveryInstructions = UserDefaults.standard.string(forKey: AppStorageKeys.defaultPODeliveryInstructions) ?? ""
                }
            }
            .prefixPrompt(.purchaseOrder) {
                let p = UserDefaults.standard.string(forKey: AppStorageKeys.poNumberPrefix) ?? ""
                poNumber = DocumentNumberGenerator.next(
                    inAll: existingPOs.map(\.poNumber), prefix: p) ?? "PO-2026-001"
            }
            .toolbar {
                ToolbarItem(id: "create-po-cancel", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "create-po-save", placement: .topBarTrailing) {
                    Button("Save PO") { savePO() }
                        .disabled(poNumber.isEmpty || selectedVendor == nil || tempItems.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                LineItemFormSheet(mode: .addToTemp(binding: $tempItems, isPO: true), products: products)
            }
            .alert("Duplicate Number", isPresented: $showDuplicateNumberAlert) {
                Button("OK") {}
            } message: {
                Text("A purchase order with the number \"\(poNumber)\" already exists. Please use a different number.")
            }
            .alert("Save Failed", isPresented: $showSaveErrorAlert) {
                Button("OK") {}
            } message: {
                Text("The purchase order could not be saved to the database. Please try again, and export a backup from Settings if the problem continues.")
            }
        }
        .presentationSizing(.page)
    }

    private func savePO() {
        guard let vendor = selectedVendor else { return }
        // Prevent two documents from sharing the same number.
        guard !existingPOs.contains(where: { $0.poNumber == poNumber }) else {
            showDuplicateNumberAlert = true
            return
        }
        let newPO = PurchaseOrder(
            poNumber: poNumber,
            vendorName: "\(vendor.name) [\(vendor.company)]",
            remarks: remarks,
            deliveryInstructions: deliveryInstructions
        )
        newPO.date         = date
        newPO.discountPct  = discountPct
        newPO.discountFixed = discountFixed
        newPO.taxPct       = taxPct
        newPO.taxLabel     = taxLabel
        for (index, temp) in tempItems.enumerated() {
            newPO.items.append(LineItem(
                itemCode: temp.itemCode,
                itemDescription: temp.itemDescription,
                qty: temp.qty,
                unitPrice: temp.unitPrice,
                sortOrder: index
            ))
        }
        modelContext.insert(newPO)
        if saveContext(modelContext, action: "save purchase order") {
            dismiss()
        } else {
            showSaveErrorAlert = true
        }
    }
}
