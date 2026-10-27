import SwiftUI
import SwiftData
import MessageUI

struct DocumentsView: View {
    @Query(sort: [SortDescriptor(\Quotation.date, order: .reverse),
                  SortDescriptor(\Quotation.quoteNumber, order: .reverse)]) private var quotations: [Quotation]
    @Query(sort: [SortDescriptor(\PurchaseOrder.date, order: .reverse),
                  SortDescriptor(\PurchaseOrder.poNumber, order: .reverse)]) private var purchaseOrders: [PurchaseOrder]
    @Query(sort: [SortDescriptor(\Invoice.date, order: .reverse),
                  SortDescriptor(\Invoice.invoiceNumber, order: .reverse)]) private var invoices: [Invoice]
    @Query(sort: \Product.itemCode) private var products: [Product]
    @StateObject private var adminAuth = AdminAuth.shared
    @AppStorage("showMarginBadge") private var showMarginBadge = true
    @Environment(\.modelContext) private var modelContext
    // Observing currency so list re-renders when it changes in Settings
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"

    @State private var selectedDocumentType = 0
    @State private var statFilter: String? = nil   // set by tapping a stat card
    @State private var searchText = ""
    @State private var showCreateQuote = false
    @State private var showCreatePO = false
    @State private var quotationToEdit: Quotation?
    @State private var poToEdit: PurchaseOrder?
    @State private var invoiceToEdit: Invoice?
    @State private var invoiceToPay: Invoice?
    @State private var quotationToInvoice: Quotation?
    @State private var showDeleteConfirm = false
    @State private var deleteTarget: DeleteTarget?
    @State private var pdfToShare: IdentifiableURL?
    @State private var mailData: MailData?
    @State private var sendInfo: SendDocumentInfo?
    @State private var pdfToPreview: IdentifiableURL?

    /// Margin chip for a quotation row. Only while the PIN is unlocked and the user left it on.
    private func marginBadge(for quote: Quotation) -> (text: String, color: Color)? {
        guard showMarginBadge, adminAuth.isUnlocked else { return nil }
        let m = QuotationMargin(quotation: quote, products: products)
        guard m.hasData, let mg = m.margin else { return nil }
        let text = String(format: "Margin %.1f%%", mg) + (m.missingCount > 0 ? " *" : "")
        return (text, mg < 0 ? .red : (mg < 10 ? .orange : .green))
    }

    private let documentTabs: [(label: String, icon: String, selection: Int)] = [
        ("Quotes", "doc.text", 0),
        ("POs", "doc.on.doc", 1),
        ("Fulfill", "shippingbox", 2),
        ("Invoices", "doc.text.fill", 4),
        ("Done", "checkmark.seal", 3)
    ]

    enum DeleteTarget {
        case quote(Quotation)
        case po(PurchaseOrder)
        case invoice(Invoice)

        var label: String {
            switch self {
            case .quote(let q):   return q.quoteNumber
            case .po(let p):      return p.poNumber
            case .invoice(let i): return i.invoiceNumber
            }
        }
    }

    // MARK: - Filtered lists
    var filteredQuotations: [Quotation] {
        var list = quotations
        if statFilter == "draft"     { list = list.filter { $0.status == .draft } }
        if statFilter == "confirmed" { list = list.filter { $0.status == .confirmed } }
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.quoteNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.customerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredPOs: [PurchaseOrder] {
        var list = purchaseOrders
        if statFilter == "awaiting" { list = list.filter { $0.deliveryState == .awaiting } }
        if statFilter == "partial"  { list = list.filter { $0.deliveryState == .partial } }
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.poNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.vendorName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var filteredInvoices: [Invoice] {
        var list = invoices
        if statFilter == "unpaid" { list = list.filter { $0.status == .unpaid } }
        if statFilter == "overdue" { list = list.filter { $0.isOverdue } }
        guard !searchText.isEmpty else { return list }
        return list.filter {
            $0.invoiceNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.customerName.localizedCaseInsensitiveContains(searchText) ||
            $0.quotationNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    // Confirmed quotations whose line items are all delivered
    var completedQuotations: [Quotation] {
        let completed = quotations.filter { quote in
            quote.status == .confirmed &&
            !quote.items.isEmpty &&
            quote.items.allSatisfy { $0.isDelivered }
        }
        guard !searchText.isEmpty else { return completed }
        return completed.filter {
            $0.quoteNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.customerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(documentTabs, id: \.selection) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDocumentType = tab.selection
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 17, weight: selectedDocumentType == tab.selection ? .semibold : .regular))
                            Text(tab.label)
                                .font(.system(size: 10, weight: selectedDocumentType == tab.selection ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundColor(selectedDocumentType == tab.selection ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    let tabWidth = geo.size.width / CGFloat(documentTabs.count)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: tabWidth, height: 2)
                        .offset(x: tabWidth * CGFloat(documentTabs.firstIndex(where: { $0.selection == selectedDocumentType }) ?? 0))
                        .animation(.easeInOut(duration: 0.2), value: selectedDocumentType)
                }
            }

            Divider()

            statRow

            List {
                if selectedDocumentType == 0 {
                    ForEach(monthGroups(filteredQuotations, date: \.date, total: \.grandTotal)) { group in
                      Section {
                        ForEach(group.items) { quote in
                            DocumentRow(
                                primaryLabel: quote.quoteNumber,
                                secondaryLabel: quote.customerName,
                                date: quote.date,
                                total: quote.grandTotal,
                                accentColor: .blue,
                                icon: quote.status.icon,
                                statusLabel: quote.status.rawValue,
                                statusColor: quote.status.color,
                                margin: marginBadge(for: quote)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { quotationToEdit = quote }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = .quote(quote)
                                    showDeleteConfirm = true
                                } label: { Label("Delete", systemImage: "trash") }

                                Button {
                                    duplicateQuotation(quote)
                                } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    sharePDF(for: quote)
                                } label: {
                                    Label("Share PDF", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                                Button {
                                    sendInfo = SendDocumentInfo.quotation(quote)
                                } label: {
                                    Label("Send", systemImage: "paperplane")
                                }
                                .tint(.teal)
                            }
                            .contextMenu {
                                contextMenuItems(for: quote)
                            }
                        }
                      } header: {
                        MonthHeader(date: group.id, count: group.items.count, total: group.total)
                      }
                    }
                } else if selectedDocumentType == 3 {
                    ForEach(monthGroups(completedQuotations, date: \.date, total: \.grandTotal)) { group in
                      Section {
                        ForEach(group.items) { quote in
                            DocumentRow(
                                primaryLabel: quote.quoteNumber,
                                secondaryLabel: quote.customerName,
                                date: quote.date,
                                total: quote.grandTotal,
                                accentColor: .green,
                                icon: "checkmark.seal.fill",
                                statusLabel: "Completed",
                                statusColor: .green,
                                note: quote.invoiceNote,
                                margin: marginBadge(for: quote)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { quotationToEdit = quote }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !quote.uninvoicedDeliveredItems.isEmpty {
                                    Button {
                                        quotationToInvoice = quote
                                    } label: { Label("Invoice", systemImage: "doc.text.fill") }
                                    .tint(.indigo)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    sharePDF(for: quote)
                                } label: {
                                    Label("Share PDF", systemImage: "square.and.arrow.up")
                                }
                                .tint(.green)
                                Button {
                                    sendInfo = SendDocumentInfo.quotation(quote)
                                } label: {
                                    Label("Send", systemImage: "paperplane")
                                }
                                .tint(.teal)
                            }
                            .contextMenu {
                                if !quote.uninvoicedDeliveredItems.isEmpty {
                                    Button {
                                        quotationToInvoice = quote
                                    } label: { Label("Create Invoice", systemImage: "doc.text.fill") }
                                }
                                contextMenuItems(for: quote)
                            }
                        }
                      } header: {
                        MonthHeader(date: group.id, count: group.items.count, total: group.total)
                      }
                    }
                } else if selectedDocumentType == 1 {
                    ForEach(monthGroups(filteredPOs, date: \.date, total: \.grandTotal)) { group in
                      Section {
                        ForEach(group.items) { order in
                            DocumentRow(
                                primaryLabel: order.poNumber,
                                secondaryLabel: order.vendorName,
                                date: order.date,
                                total: order.grandTotal,
                                accentColor: .green,
                                icon: order.deliveryState.icon,
                                statusLabel: order.deliveryState.label,
                                statusColor: order.deliveryState.color,
                                note: order.deliveryNote
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { poToEdit = order }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    deleteTarget = .po(order)
                                    showDeleteConfirm = true
                                } label: { Label("Delete", systemImage: "trash") }

                                Button {
                                    duplicatePO(order)
                                } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    sharePDF(for: order)
                                } label: {
                                    Label("Share PDF", systemImage: "square.and.arrow.up")
                                }
                                .tint(.green)
                                Button {
                                    sendInfo = SendDocumentInfo.purchaseOrder(order)
                                } label: {
                                    Label("Send", systemImage: "paperplane")
                                }
                                .tint(.teal)
                            }
                            .contextMenu {
                                poContextMenuItems(for: order)
                            }
                        }
                      } header: {
                        MonthHeader(date: group.id, count: group.items.count, total: group.total)
                      }
                    }
                } else if selectedDocumentType == 4 {
                    ForEach(monthGroups(filteredInvoices, date: \.date, total: \.grandTotal)) { group in
                      Section {
                        ForEach(group.items) { invoice in
                            InvoiceDocumentRow(invoice: invoice)
                                .contentShape(Rectangle())
                                .onTapGesture { invoiceToEdit = invoice }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteTarget = .invoice(invoice)
                                        showDeleteConfirm = true
                                    } label: { Label("Delete", systemImage: "trash") }

                                    if invoice.balanceDue > 0.005 {
                                        Button {
                                            invoiceToPay = invoice
                                        } label: { Label("Payment", systemImage: "banknote") }
                                        .tint(.green)
                                    } else {
                                        Button {
                                            toggleInvoicePaid(invoice)
                                        } label: { Label("Mark Unpaid", systemImage: "arrow.uturn.backward") }
                                        .tint(.orange)
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        sharePDF(for: invoice)
                                    } label: {
                                        Label("Share PDF", systemImage: "square.and.arrow.up")
                                    }
                                    .tint(.indigo)
                                    Button {
                                        sendInfo = SendDocumentInfo.invoice(invoice)
                                    } label: {
                                        Label("Send", systemImage: "paperplane")
                                    }
                                    .tint(.teal)
                                }
                                .contextMenu {
                                    invoiceContextMenuItems(for: invoice)
                                }
                        }
                      } header: {
                        MonthHeader(date: group.id, count: group.items.count, total: group.total)
                      }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .searchable(text: $searchText, prompt: "Search by number or name…")
            .overlay {
                if selectedDocumentType == 2 {
                    FulfillmentView()
                } else if selectedDocumentType == 0 && filteredQuotations.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Quotations" : "No Results",
                        systemImage: "doc.text",
                        description: Text(searchText.isEmpty ? "Tap + to create your first quote." : "Try a different search term.")
                    )
                } else if selectedDocumentType == 1 && filteredPOs.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Purchase Orders" : "No Results",
                        systemImage: "doc.text.below.ecg",
                        description: Text(searchText.isEmpty ? "Tap + to create your first PO." : "Try a different search term.")
                    )
                } else if selectedDocumentType == 4 && filteredInvoices.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Invoices" : "No Results",
                        systemImage: "doc.text",
                        description: Text(searchText.isEmpty
                            ? "Open a confirmed quotation in the Fulfill tab and tap Create Invoice once its items are delivered."
                            : "Try a different search term.")
                    )
                } else if selectedDocumentType == 3 && completedQuotations.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Completed Quotations" : "No Results",
                        systemImage: "checkmark.seal",
                        description: Text(searchText.isEmpty
                            ? "Quotations appear here once all line items are marked delivered in the Fulfillment tab."
                            : "Try a different search term.")
                    )
                }
            }
        }
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedDocumentType) { _, _ in statFilter = nil }
        .onChange(of: searchText) { _, new in if !new.isEmpty { statFilter = nil } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if selectedDocumentType == 0 || selectedDocumentType == 1 {
                    Button {
                        if selectedDocumentType == 0 { showCreateQuote = true }
                        else { showCreatePO = true }
                    } label: { Image(systemName: "doc.badge.plus") }
                }
            }
        }
        .sheet(isPresented: $showCreateQuote) { CreateQuotationView() }
        .sheet(isPresented: $showCreatePO) { CreatePurchaseOrderView() }
        .sheet(item: $quotationToEdit) { EditQuotationView(quotation: $0) }
        .sheet(item: $poToEdit) { EditPurchaseOrderView(order: $0) }
        .sheet(item: $invoiceToEdit) { EditInvoiceView(invoice: $0) }
        .sheet(item: $invoiceToPay) { inv in
            AddPaymentSheet(balance: inv.balanceDue) { payment in
                inv.addPayment(payment)
                saveContext(modelContext, action: "invoice payment")
            }
        }
        .sheet(item: $quotationToInvoice) { InvoiceFlowSheet(quotation: $0) }
        .sheet(item: $sendInfo) { SendDocumentSheet(info: $0) }
        .sheet(item: $mailData) { data in
            MailComposerView(mailData: data)
        }
        .sheet(item: $pdfToShare) { wrapped in
            ActivityShareSheet(items: [wrapped.url])
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
                            Button { pdfToShare = wrapped } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("Share PDF")
                        }
                    }
            }
        }
        .deleteConfirmation(
            isPresented: $showDeleteConfirm,
            itemName: deleteTarget?.label ?? ""
        ) {
            switch deleteTarget {
            case .quote(let q): withAnimation { modelContext.delete(q) }
            case .po(let p):    withAnimation { modelContext.delete(p) }
            case .invoice(let i):
                // Give the billed items back to their quotation before the invoice goes.
                withAnimation {
                    i.releaseItems(in: modelContext)
                    modelContext.delete(i)
                }
            case nil:           break
            }
            deleteTarget = nil
        }
    }

    // MARK: - Stat cards
    // One row of three small cards under the tab picker. Cards with a filter can be tapped
    // to show only those documents; tap again to clear. Hidden while searching.
    @ViewBuilder
    private var statRow: some View {
        let stats = currentStats
        if searchText.isEmpty && !stats.isEmpty {
            HStack(spacing: 10) {
                ForEach(stats) { stat in
                    DocStatCard(value: stat.value, label: stat.label, color: stat.color,
                                isSelected: stat.filter != nil && stat.filter == statFilter)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard let f = stat.filter else { return }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                statFilter = (statFilter == f) ? nil : f
                            }
                        }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var currentStats: [DocStat] {
        switch selectedDocumentType {
        case 0: return quoteStats()
        case 1: return poStats()
        case 2: return fulfillStats()
        case 4: return invoiceStats()
        case 3: return doneStats()
        default: return []
        }
    }

    private func inThisMonth(_ date: Date) -> Bool {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month)
    }

    /// Whole-number amount with the currency symbol, e.g. "RM 12,345".
    private func money(_ value: Double) -> String {
        let number: String = value.formatted(.number.precision(.fractionLength(0)))
        return currencySymbol + " " + number
    }

    private func quoteStats() -> [DocStat] {
        var month = 0.0
        var drafts = 0
        var confirmed = 0
        for q in quotations {
            if inThisMonth(q.date) && q.status != .cancelled { month += q.grandTotal }
            if q.status == .draft { drafts += 1 }
            if q.status == .confirmed { confirmed += 1 }
        }
        return [
            DocStat(id: "q-month", value: money(month), label: "This month", color: .blue, filter: nil),
            DocStat(id: "q-draft", value: "\(drafts)", label: "Draft", color: .orange, filter: "draft"),
            DocStat(id: "q-confirmed", value: "\(confirmed)", label: "Confirmed", color: .green, filter: "confirmed")
        ]
    }

    private func poStats() -> [DocStat] {
        var month = 0.0
        var awaiting = 0
        var partial = 0
        for po in purchaseOrders {
            if inThisMonth(po.date) { month += po.grandTotal }
            if po.deliveryState == .awaiting { awaiting += 1 }
            if po.deliveryState == .partial { partial += 1 }
        }
        return [
            DocStat(id: "p-month", value: money(month), label: "This month", color: .green, filter: nil),
            DocStat(id: "p-awaiting", value: "\(awaiting)", label: "Awaiting", color: .blue, filter: "awaiting"),
            DocStat(id: "p-partial", value: "\(partial)", label: "Partly delivered", color: .orange, filter: "partial")
        ]
    }

    private func fulfillStats() -> [DocStat] {
        var needsPO = 0
        var awaiting = 0
        var toDeliver = 0.0
        for q in quotations where q.status == .confirmed {
            let undelivered = q.items.filter { !$0.isDelivered }
            // Same rule as the Fulfill list: fully delivered quotations are not shown there.
            if !q.items.isEmpty && undelivered.isEmpty { continue }
            var missingPO = false
            for item in undelivered {
                toDeliver += item.subTotal
                if item.linkedPONumber.isEmpty { missingPO = true }
            }
            if missingPO { needsPO += 1 } else { awaiting += 1 }
        }
        return [
            DocStat(id: "f-needs", value: "\(needsPO)", label: "Needs PO", color: .orange, filter: nil),
            DocStat(id: "f-await", value: "\(awaiting)", label: "Awaiting delivery", color: .blue, filter: nil),
            DocStat(id: "f-value", value: money(toDeliver), label: "To deliver", color: .green, filter: nil)
        ]
    }

    private func invoiceStats() -> [DocStat] {
        var outstanding = 0.0
        var overdue = 0.0
        var overdueCount = 0
        var receivedMonth = 0.0
        for inv in invoices {
            outstanding += inv.balanceDue
            if inv.isOverdue {
                overdue += inv.balanceDue
                overdueCount += 1
            }
            let list = inv.payments
            if list.isEmpty {
                if inv.status == .paid && inThisMonth(inv.paidDate ?? inv.date) { receivedMonth += inv.grandTotal }
            } else {
                for payment in list where inThisMonth(payment.date) { receivedMonth += payment.amount }
            }
        }
        return [
            DocStat(id: "i-out", value: money(outstanding), label: "Outstanding", color: .orange, filter: "unpaid"),
            DocStat(id: "i-over", value: overdueCount == 0 ? "0" : money(overdue), label: "Overdue", color: .red, filter: "overdue"),
            DocStat(id: "i-paid", value: money(receivedMonth), label: "Received this month", color: .green, filter: nil)
        ]
    }

    private func doneStats() -> [DocStat] {
        var count = 0
        var value = 0.0
        var toInvoice = 0
        for q in quotations where q.status == .confirmed && !q.items.isEmpty {
            guard q.items.allSatisfy({ $0.isDelivered }) else { continue }
            count += 1
            value += q.grandTotal
            if !q.uninvoicedDeliveredItems.isEmpty { toInvoice += 1 }
        }
        return [
            DocStat(id: "d-count", value: "\(count)", label: "Completed", color: .green, filter: nil),
            DocStat(id: "d-value", value: money(value), label: "Value", color: .blue, filter: nil),
            DocStat(id: "d-invoice", value: "\(toInvoice)", label: "To invoice", color: .indigo, filter: nil)
        ]
    }

    // MARK: - PDF Share (generated on demand — never during list rendering)
    private func sharePDF(for quote: Quotation) {
        guard let url = PDFGenerator.generate(
            view: QuotationPDFView(quotation: quote),
            filename: quote.quoteNumber
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func sharePDF(for order: PurchaseOrder) {
        guard let url = PDFGenerator.generate(
            view: PurchaseOrderPDFView(order: order),
            filename: order.poNumber
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func sharePDF(for invoice: Invoice) {
        guard let url = PDFGenerator.generate(
            view: InvoicePDFView(invoice: invoice),
            filename: invoice.pdfFileName
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func previewPDF(for quote: Quotation) {
        guard let url = PDFGenerator.generate(view: QuotationPDFView(quotation: quote), filename: quote.quoteNumber) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }

    private func previewPDF(for order: PurchaseOrder) {
        guard let url = PDFGenerator.generate(view: PurchaseOrderPDFView(order: order), filename: order.poNumber) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }

    private func previewPDF(for invoice: Invoice) {
        guard let url = PDFGenerator.generate(view: InvoicePDFView(invoice: invoice), filename: invoice.pdfFileName) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }

    private func toggleInvoicePaid(_ invoice: Invoice) {
        if invoice.status == .paid {
            invoice.markUnpaid()
        } else {
            invoice.markFullyPaid()
        }
        saveContext(modelContext, action: "invoice status")
    }

    // MARK: - Invoice Context Menu
    @ViewBuilder
    private func invoiceContextMenuItems(for invoice: Invoice) -> some View {
        Button {
            invoiceToEdit = invoice
        } label: { Label("Edit", systemImage: "pencil") }

        if invoice.balanceDue > 0.005 {
            Button {
                invoiceToPay = invoice
            } label: { Label("Record Payment", systemImage: "banknote") }
            Button {
                toggleInvoicePaid(invoice)
            } label: { Label("Mark Fully Paid", systemImage: "checkmark.seal") }
        } else {
            Button {
                toggleInvoicePaid(invoice)
            } label: { Label("Mark Unpaid", systemImage: "arrow.uturn.backward") }
        }

        Button { previewPDF(for: invoice) } label: {
            Label("Preview PDF", systemImage: "eye")
        }

        Button {
            sharePDF(for: invoice)
        } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }

        Button {
            sendInfo = SendDocumentInfo.invoice(invoice)
        } label: { Label("Send to Customer…", systemImage: "paperplane") }

        Divider()
        Button(role: .destructive) {
            deleteTarget = .invoice(invoice)
            showDeleteConfirm = true
        } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Context Menu
    @ViewBuilder
    private func contextMenuItems(for quote: Quotation) -> some View {
        Button {
            quotationToEdit = quote
        } label: { Label("Edit", systemImage: "pencil") }

        Button {
            duplicateQuotation(quote)
        } label: { Label("Duplicate", systemImage: "doc.on.doc") }

        Button { previewPDF(for: quote) } label: {
            Label("Preview PDF", systemImage: "eye")
        }

        Button {
            sharePDF(for: quote)
        } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }

        Button {
            sendInfo = SendDocumentInfo.quotation(quote)
        } label: { Label("Send to Customer…", systemImage: "paperplane") }

        Divider()
        Button(role: .destructive) {
            deleteTarget = .quote(quote)
            showDeleteConfirm = true
        } label: { Label("Delete", systemImage: "trash") }
    }

    @ViewBuilder
    private func poContextMenuItems(for order: PurchaseOrder) -> some View {
        Button { poToEdit = order } label: { Label("Edit", systemImage: "pencil") }
        Button { duplicatePO(order) } label: { Label("Duplicate", systemImage: "doc.on.doc") }
        Button { previewPDF(for: order) } label: { Label("Preview PDF", systemImage: "eye") }
        Button { sharePDF(for: order) } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
        Button {
            sendInfo = SendDocumentInfo.purchaseOrder(order)
        } label: { Label("Send to Customer…", systemImage: "paperplane") }
        Divider()
        Button(role: .destructive) {
            deleteTarget = .po(order)
            showDeleteConfirm = true
        } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: - Duplicate Logic
    private func duplicateQuotation(_ original: Quotation) {
        // Find next number
        let newNumber = (DocumentNumberGenerator.next(
            inAll: quotations.map(\.quoteNumber),
            prefix: UserDefaults.standard.string(forKey: AppStorageKeys.quotationNumberPrefix) ?? ""
        ) ?? "QT-2026-001") + "-COPY"
        let copy = Quotation(
            quoteNumber: newNumber,
            customerName: original.customerName,
            remarks: original.remarks,
            bankAccountNumber: original.bankAccountNumber
        )
        copy.date          = Date()
        copy.paymentTerm   = original.paymentTerm
        copy.discountPct   = original.discountPct
        copy.discountFixed = original.discountFixed
        copy.taxPct        = original.taxPct
        copy.taxLabel      = original.taxLabel
        copy.studentName   = original.studentName
        copy.studentID     = original.studentID
        // Duplicates always start as Draft with fresh fulfillment state.
        for item in original.sortedItems {
            let line = LineItem(itemCode: item.itemCode, itemDescription: item.itemDescription, qty: item.qty, unitPrice: item.unitPrice, sortOrder: item.sortOrder)
            line.unitCost = item.unitCost
            copy.items.append(line)
        }
        modelContext.insert(copy)
    }

    private func duplicatePO(_ original: PurchaseOrder) {
        let newNumber = (DocumentNumberGenerator.next(
            inAll: purchaseOrders.map(\.poNumber),
            prefix: UserDefaults.standard.string(forKey: AppStorageKeys.poNumberPrefix) ?? ""
        ) ?? "PO-2026-001") + "-COPY"
        let copy = PurchaseOrder(
            poNumber: newNumber,
            vendorName: original.vendorName,
            remarks: original.remarks,
            deliveryInstructions: original.deliveryInstructions
        )
        copy.date          = Date()
        copy.discountPct   = original.discountPct
        copy.discountFixed = original.discountFixed
        copy.taxPct        = original.taxPct
        copy.taxLabel      = original.taxLabel
        // Duplicates start with fresh fulfillment state.
        for item in original.sortedItems {
            copy.items.append(LineItem(itemCode: item.itemCode, itemDescription: item.itemDescription, qty: item.qty, unitPrice: item.unitPrice, sortOrder: item.sortOrder))
        }
        modelContext.insert(copy)
    }
}

// MARK: - Stat card
struct DocStat: Identifiable {
    let id: String
    let value: String
    let label: String
    let color: Color
    /// Set when tapping the card should filter the list.
    let filter: String?
}

// Tinted stat card: small label on top, large value below, fixed height so every card matches.
struct DocStatCard: View {
    let value: String
    let label: String
    let color: Color
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 62)
        .padding(.horizontal, 12)
        .background(color.opacity(isSelected ? 0.22 : 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 1.5 : 0.5)
        )
    }
}

// MARK: - Month grouping
struct MonthGroup<T>: Identifiable {
    let id: Date          // first day of the month
    let items: [T]
    let total: Double
}

/// Groups already-sorted items by calendar month, newest month first.
func monthGroups<T>(_ items: [T],
                    date: (T) -> Date,
                    total: (T) -> Double) -> [MonthGroup<T>] {
    let cal = Calendar.current
    var order: [Date] = []
    var buckets: [Date: [T]] = [:]
    for item in items {
        let d = date(item)
        let key = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
        if buckets[key] == nil { order.append(key) }
        buckets[key, default: []].append(item)
    }
    order.sort(by: >)
    return order.map { key in
        let group = buckets[key] ?? []
        return MonthGroup(id: key, items: group, total: group.reduce(0) { $0 + total($1) })
    }
}

struct MonthHeader: View {
    let date: Date
    let count: Int
    let total: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(date.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(count) · \(formatCurrency(total))")
                .font(.caption).foregroundColor(.secondary)
                .lineLimit(1)
        }
        .textCase(nil)
        .foregroundColor(.primary)
    }
}

func shortDocumentDate(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "Today" }
    if cal.isDateInYesterday(date) { return "Yesterday" }
    if cal.isDate(date, equalTo: Date(), toGranularity: .year) {
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
    return date.formatted(.dateTime.day().month(.abbreviated).year())
}

// MARK: - Document Row
struct DocumentRow: View {
    let primaryLabel: String
    let secondaryLabel: String
    let date: Date
    let total: Double
    let accentColor: Color
    /// Status icon shown in the leading chip. Rows without a status (purchase orders) leave this nil.
    var icon: String? = nil
    var statusLabel: String? = nil
    var statusColor: Color = .secondary
    /// Optional extra line under the name, e.g. "2 of 5 delivered".
    var note: String? = nil
    /// Optional internal margin chip (shown only while unlocked).
    var margin: (text: String, color: Color)? = nil
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel(statusLabel ?? "")
            }

            // Line 1: number on the left, total on the right.
            // Line 2: name on the left, short date on the right.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(primaryLabel).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Text(formatCurrency(total))
                        .fontWeight(.semibold)
                        .lineLimit(1).fixedSize()
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(secondaryLabel)
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortDocumentDate(date))
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1).fixedSize()
                }
                if let note {
                    Text(note)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(statusColor)
                }
                if let margin {
                    Text(margin.text)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(margin.color)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Mail Support
struct MailData: Identifiable {
    let id = UUID()
    var recipients: [String] = []
    let subject: String
    let body: String
    let attachmentURL: URL
    let attachmentMIME: String
    let attachmentFilename: String
}

struct MailComposerView: UIViewControllerRepresentable {
    let mailData: MailData
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        if !mailData.recipients.isEmpty { vc.setToRecipients(mailData.recipients) }
        vc.setSubject(mailData.subject)
        vc.setMessageBody(mailData.body, isHTML: false)
        if let data = try? Data(contentsOf: mailData.attachmentURL) {
            vc.addAttachmentData(data, mimeType: mailData.attachmentMIME, fileName: mailData.attachmentFilename)
        }
        return vc
    }

    func updateUIViewController(_ uvc: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}
