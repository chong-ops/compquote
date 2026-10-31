import SwiftUI
import SwiftData

struct EditPurchaseOrderView: View {
    @Bindable var order: PurchaseOrder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.itemCode) private var products: [Product]

    @State private var showAddItemSheet = false
    @State private var showLinkQuotes = false
    @State private var itemToEdit: LineItem?
    // #7 drag-and-drop
    @State private var orderedItems: [LineItem] = []
    @State private var showSaveErrorAlert = false
    @State private var pdfToShare: IdentifiableURL?
    @State private var pdfToPreview: IdentifiableURL?
    @State private var sendInfo: SendDocumentInfo?
    // Cancel support: values as they were when the editor opened.
    @State private var original: PurchaseOrderSnapshot?
    @State private var showDiscardConfirm = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Form {
                    // ── Summary Card (same style as the quotation) ──
                    Section {
                        PurchaseOrderSummaryCard(order: order)
                            .listRowInsets(.init(top: 8, leading: 12, bottom: 4, trailing: 12))
                            .listRowBackground(Color.clear)
                    }

                    // ── Delivery (tick each item as it arrives) ─────
                    if !order.items.isEmpty {
                        Section {
                            PODeliverySummary(order: order)
                            ForEach(order.sortedItems) { item in
                                PODeliveryItemRow(item: item)
                            }
                        } header: {
                            Text("Delivery")
                        } footer: {
                            Text("Delivery ticks save as soon as you change them.")
                        }
                    }

                    // ── Link to quotation items ─────────────────────
                    Section {
                        Button { showLinkQuotes = true } label: {
                            Label("Link Quotation Items…", systemImage: "link")
                        }
                    } footer: {
                        Text("Choose which quotation items this PO covers, so they show as PO raised in Fulfill.")
                    }

                    // ── Document Details (collapsed by default) ─────
                    Section {
                        DisclosureGroup {
                            // Two-column: PO Number + Date on one row.
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Number")
                                        .font(.caption).foregroundColor(.secondary)
                                    TextField("PO…", text: $order.poNumber)
                                        .autocorrectionDisabled()
                                        .textFieldStyle(.plain)
                                }
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Date")
                                        .font(.caption).foregroundColor(.secondary)
                                    DatePicker("", selection: $order.date,
                                               displayedComponents: .date)
                                        .labelsHidden()
                                }
                            }

                            TextField("Vendor Name", text: $order.vendorName, axis: .vertical)
                                .lineLimit(1...3)
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.secondary).font(.footnote)
                                Text("Document Details")
                            }
                        }
                    }

                    Section("Line Items") {
                        if orderedItems.isEmpty {
                            Label("No items yet. Tap Add Item.", systemImage: "tray")
                                .foregroundColor(.secondary).font(.subheadline)
                        }
                        ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, item in
                            LineItemEditRow(item: item, index: index, accent: .green, showIndexOnPhone: false) {
                                modelContext.delete(item)
                                orderedItems.removeAll { $0.id == item.id }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { itemToEdit = item }
                        }
                        .onMove { from, to in
                            orderedItems.move(fromOffsets: from, toOffset: to)
                            for (index, item) in orderedItems.enumerated() { item.sortOrder = index }
                        }

                        Button { showAddItemSheet = true } label: {
                            Label("Add Item", systemImage: "plus.circle")
                        }
                    }

                    DiscountTaxSection(
                        discountPct:   $order.discountPct,
                        discountFixed: $order.discountFixed,
                        taxPct:        $order.taxPct,
                        taxLabel:      $order.taxLabel,
                        itemsSubtotal:  order.itemsSubtotal,
                        discountAmount: order.discountAmount,
                        taxAmount:      order.taxAmount,
                        grandTotal:     order.grandTotal
                    )

                    Section("Terms & Conditions") {
                        TextField("Remarks / Payment Terms", text: $order.remarks, axis: .vertical).lineLimit(2...4)
                        TextField("Delivery Instructions", text: $order.deliveryInstructions, axis: .vertical).lineLimit(2...4)
                    }

                    DeleteRecordSection(title: "Delete Purchase Order", itemName: order.poNumber) {
                        let target = order
                        dismiss()
                        modelContext.deleteAfterSheetCloses(target)
                    }

                    Color.clear.frame(height: 80).listRowBackground(Color.clear)
                }

                TotalsSummaryBar(
                    itemsSubtotal:  order.itemsSubtotal,
                    discountAmount: order.discountAmount,
                    taxAmount:      order.taxAmount,
                    taxLabel:       order.taxLabel,
                    grandTotal:     order.grandTotal,
                    accentColor:    .green
                )
            }
            .navigationTitle("Edit Purchase Order")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .onAppear {
                syncOrderedItems()
                if original == nil { original = PurchaseOrderSnapshot(order) }
            }
            .onChange(of: order.items.count) { syncOrderedItems() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let original, PurchaseOrderSnapshot(order) != original {
                            showDiscardConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItem(id: "po-pdf-actions", placement: .topBarTrailing) {
                    Menu {
                        Button { previewPDF() } label: {
                            Label("Preview PDF", systemImage: "eye")
                        }
                        Button { sharePDF() } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        Button { sendInfo = SendDocumentInfo.purchaseOrder(order) } label: {
                            Label("Send to Customer…", systemImage: "paperplane")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(id: "ti_1", placement: .topBarTrailing) {
                    Button("Save") {
                        if saveContext(modelContext, action: "save purchase order edits") {
                            dismiss()
                        } else {
                            showSaveErrorAlert = true
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showLinkQuotes) {
                POLinkQuotationSheet(order: order)
            }
            .sheet(isPresented: $showAddItemSheet) {
                LineItemFormSheet(mode: .addToPO(order, modelContext: modelContext), products: products)
            }
            .sheet(item: $itemToEdit) { InlineEditItemSheet(item: $0, isPOMode: true) }
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
            .confirmationDialog("Discard your changes to this purchase order?",
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
        .presentationSizing(.page)
    }

    /// Puts the purchase order and its line items back to how they were when
    /// the editor opened (edits are applied live, so Cancel has to undo them).
    private func discardChanges() {
        guard let original else { return }
        original.restore(to: order, in: modelContext)
        _ = saveContext(modelContext, action: "discard purchase order edits")
    }

    private func syncOrderedItems() {
        // Repair: if sortOrder values are not unique (older docs where all defaulted to 0),
        // freeze the current order and assign sequential sortOrders so drag/reorder works.
        let orders = order.items.map(\.sortOrder)
        if Set(orders).count != orders.count {
            for (index, item) in order.items.enumerated() {
                item.sortOrder = index
            }
        }
        orderedItems = order.items.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func sharePDF() {
        guard let url = PDFGenerator.generate(
            view: PurchaseOrderPDFView(order: order),
            filename: order.poNumber
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func previewPDF() {
        guard let url = PDFGenerator.generate(
            view: PurchaseOrderPDFView(order: order),
            filename: order.poNumber
        ) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }
}


// MARK: - Snapshot (for Cancel)

private struct PurchaseOrderSnapshot: Equatable {
    var date: Date
    var poNumber: String
    var vendorName: String
    var remarks: String
    var deliveryInstructions: String
    var discountPct: Double
    var discountFixed: Double
    var taxPct: Double
    var taxLabel: String
    var items: [PersistentIdentifier: ItemSnapshot]

    init(_ o: PurchaseOrder) {
        date = o.date
        poNumber = o.poNumber
        vendorName = o.vendorName
        remarks = o.remarks
        deliveryInstructions = o.deliveryInstructions
        discountPct = o.discountPct
        discountFixed = o.discountFixed
        taxPct = o.taxPct
        taxLabel = o.taxLabel
        items = Dictionary(uniqueKeysWithValues: o.items.map {
            ($0.persistentModelID, ItemSnapshot($0))
        })
    }

    func restore(to o: PurchaseOrder, in context: ModelContext) {
        o.date = date
        o.poNumber = poNumber
        o.vendorName = vendorName
        o.remarks = remarks
        o.deliveryInstructions = deliveryInstructions
        o.discountPct = discountPct
        o.discountFixed = discountFixed
        o.taxPct = taxPct
        o.taxLabel = taxLabel

        // Items added during this edit: remove them.
        for item in Array(o.items) where items[item.persistentModelID] == nil {
            o.items.removeAll { $0.persistentModelID == item.persistentModelID }
            context.delete(item)
        }
        // Items that existed: put values back, or re-create if deleted.
        for snap in items.values {
            if let existing = o.items.first(where: { $0.persistentModelID == snap.id }) {
                snap.apply(to: existing)
            } else {
                let restored = LineItem(itemCode: snap.itemCode,
                                        itemDescription: snap.itemDescription,
                                        qty: snap.qty,
                                        unitPrice: snap.unitPrice,
                                        sortOrder: snap.sortOrder)
                snap.apply(to: restored)
                context.insert(restored)
                o.items.append(restored)
            }
        }
    }
}


// MARK: - Summary card (matches QuotationSummaryCard)

private struct PurchaseOrderSummaryCard: View {
    @Bindable var order: PurchaseOrder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.poNumber.isEmpty ? "—" : order.poNumber)
                        .font(.title2).fontWeight(.bold)
                    if !order.vendorName.isEmpty {
                        Text(order.vendorName)
                            .font(.subheadline).foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption)
                    Text(order.date, format: .dateTime.day().month(.abbreviated).year())
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
                Text(formatCurrency(order.grandTotal))
                    .font(.title3).fontWeight(.bold).foregroundColor(.green)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - PO Delivery
private struct PODeliverySummary: View {
    let order: PurchaseOrder
    @Environment(\.modelContext) private var modelContext

    private var total: Int { order.items.count }
    private var done: Int { order.deliveredCount }
    private var allDone: Bool { total > 0 && done == total }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(order.deliveryState.label, systemImage: order.deliveryState.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(order.deliveryState.color)
                Spacer()
                Text("\(done) of \(total) delivered")
                    .font(.footnote).foregroundColor(.secondary)
            }
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .tint(.green)
            Button {
                setAll(!allDone)
            } label: {
                Text(allDone ? "Clear all" : "Mark all delivered")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func setAll(_ delivered: Bool) {
        for item in order.items {
            if delivered {
                if !item.isDelivered { item.deliveredDate = Date() }
                item.isDelivered = true
            } else {
                item.isDelivered = false
                item.deliveredDate = nil
                item.deliveryReference = ""
            }
        }
        try? modelContext.save()
    }
}

private struct PODeliveryItemRow: View {
    @Bindable var item: LineItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                item.isDelivered.toggle()
                item.deliveredDate = item.isDelivered ? Date() : nil
                if !item.isDelivered { item.deliveryReference = "" }
                try? modelContext.save()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.isDelivered ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(item.isDelivered ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.itemCode).fontWeight(.semibold).foregroundColor(.primary)
                        Text(item.itemDescription)
                            .font(.caption).foregroundColor(.secondary)
                            .lineLimit(2)
                        if item.isDelivered {
                            Text(item.deliveredDate.map { "Received " + $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "Received")
                                .font(.caption2.weight(.medium)).foregroundColor(.green)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("× \(item.qty)")
                        .font(.footnote).foregroundColor(.secondary).monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(item.itemCode), \(item.isDelivered ? "delivered" : "not delivered")")

            if item.isDelivered {
                TextField("DO / Invoice / Tracking no.", text: $item.deliveryReference)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .padding(.leading, 36)
            }
        }
    }
}
