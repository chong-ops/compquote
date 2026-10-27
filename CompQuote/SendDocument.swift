import SwiftUI
import SwiftData
import MessageUI

// MARK: - What is being sent
// One PDF plus the details needed to word the message. Built from a document with the
// helpers below, then shown in SendDocumentSheet.
struct SendDocumentInfo: Identifiable {
    let id = UUID()
    let kind: String          // "Quotation", "Invoice"…
    let number: String
    let customerName: String
    let phone: String         // may be empty — the sheet looks it up
    let total: Double?
    let pdfURL: URL
}

extension SendDocumentInfo {
    @MainActor
    static func quotation(_ q: Quotation) -> SendDocumentInfo? {
        guard let url = PDFGenerator.generate(view: QuotationPDFView(quotation: q), filename: q.quoteNumber) else { return nil }
        return SendDocumentInfo(kind: "Quotation", number: q.quoteNumber, customerName: q.customerName,
                                phone: q.customerContactNumber, total: q.grandTotal, pdfURL: url)
    }

    @MainActor
    static func invoice(_ i: Invoice) -> SendDocumentInfo? {
        guard let url = PDFGenerator.generate(view: InvoicePDFView(invoice: i), filename: i.pdfFileName) else { return nil }
        return SendDocumentInfo(kind: "Invoice", number: i.invoiceNumber, customerName: i.customerName,
                                phone: i.customerContactNumber, total: i.balanceDue > 0.005 ? i.balanceDue : i.grandTotal, pdfURL: url)
    }

    @MainActor
    static func purchaseOrder(_ o: PurchaseOrder) -> SendDocumentInfo? {
        guard let url = PDFGenerator.generate(view: PurchaseOrderPDFView(order: o), filename: o.poNumber) else { return nil }
        return SendDocumentInfo(kind: "Purchase Order", number: o.poNumber, customerName: o.vendorName,
                                phone: "", total: o.grandTotal, pdfURL: url)
    }

    @MainActor
    static func serviceReport(_ r: ServiceReport) -> SendDocumentInfo? {
        guard let url = PDFGenerator.generate(view: ServiceReportPDFView(report: r), filename: r.reportNumber) else { return nil }
        return SendDocumentInfo(kind: "Service Report", number: r.reportNumber, customerName: r.customerName,
                                phone: "", total: nil, pdfURL: url)
    }
}

// MARK: - Phone numbers
enum WhatsAppNumber {
    /// Digits only, with the Malaysian country code: "012-345 6789" → "60123456789".
    /// Returns nil when the text does not look like a phone number.
    static func normalized(_ raw: String) -> String? {
        let digits = raw.filter { $0.isNumber }
        guard digits.count >= 8 else { return nil }
        if raw.trimmingCharacters(in: .whitespaces).hasPrefix("+") { return digits }
        if digits.hasPrefix("00") { return String(digits.dropFirst(2)) }
        if digits.hasPrefix("60") { return digits }
        if digits.hasPrefix("0") { return "60" + digits.dropFirst() }
        return "60" + digits
    }
}

// MARK: - Send sheet
struct SendDocumentSheet: View {
    let info: SendDocumentInfo

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var customers: [Customer]
    @Query private var vendors: [Vendor]
    @AppStorage(AppStorageKeys.companyName) private var companyName = ""
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"

    @State private var phone = ""
    @State private var email = ""
    @State private var message = ""
    @State private var mailData: MailData?
    @State private var shareItem: IdentifiableURL?
    @State private var note: String?
    @State private var prepared = false

    private var firstName: String {
        // "Wu Jing [UCSI International School]" → "Wu Jing"
        let base = info.customerName.split(separator: "[").first.map(String.init) ?? info.customerName
        return base.trimmingCharacters(in: .whitespaces)
    }

    private var subject: String { "\(info.kind) \(info.number)" }

    private func defaultMessage() -> String {
        var lines: [String] = []
        lines.append(firstName.isEmpty ? "Hello," : "Hi \(firstName),")
        lines.append("")
        var body = "Please find \(info.kind.lowercased()) \(info.number) attached."
        if let total = info.total {
            let number: String = total.formatted(.number.precision(.fractionLength(2)))
            body += info.kind == "Invoice" ? " Amount due: \(currencySymbol) \(number)." : " Total: \(currencySymbol) \(number)."
        }
        lines.append(body)
        lines.append("")
        lines.append("Thank you.")
        if !companyName.isEmpty { lines.append(companyName) }
        return lines.joined(separator: "\n")
    }

    private func matchedCustomer() -> Customer? {
        let name = info.customerName.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty else { return nil }
        return customers.first(where: { $0.name.lowercased() == name })
            ?? customers.first(where: { !$0.company.isEmpty && $0.company.lowercased() == name })
            ?? customers.first(where: { !firstName.isEmpty && $0.name.lowercased() == firstName.lowercased() })
    }

    private func lookupPhone() -> String {
        if let c = matchedCustomer() {
            if !c.whatsappNumber.isEmpty { return c.whatsappNumber }
            if !c.contactNumber.isEmpty { return c.contactNumber }
        }
        let name = firstName.lowercased()
        guard !name.isEmpty else { return "" }
        if let c = customers.first(where: { !$0.contactNumber.isEmpty && $0.name.lowercased() == name }) {
            return c.contactNumber
        }
        if let v = vendors.first(where: { !$0.contactNumber.isEmpty &&
            (info.customerName.localizedCaseInsensitiveContains($0.name) || $0.name.lowercased() == name) }) {
            return v.contactNumber
        }
        return ""
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "doc.richtext.fill").foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subject).fontWeight(.semibold)
                            Text(info.customerName).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("PDF").font(.caption2.weight(.bold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.12)).foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                }

                Section {
                    TextField("customer@example.com", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Email address")
                } footer: {
                    Text("Filled in from the customer record when there is one.")
                }

                Section {
                    TextField("e.g. 012-345 6789", text: $phone)
                        .keyboardType(.phonePad)
                } header: {
                    Text("WhatsApp number")
                } footer: {
                    Text("Filled in from the customer record when there is one. Numbers starting with 0 are treated as Malaysian (+60).")
                }

                Section("Message") {
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(4...10)
                }

                Section {
                    Button { sendEmail() } label: {
                        Label("Email with PDF", systemImage: "envelope.fill")
                    }
                    Button { openWhatsAppChat() } label: {
                        Label("Open WhatsApp chat", systemImage: "message.fill")
                    }
                    .tint(.green)
                    .disabled(WhatsAppNumber.normalized(phone) == nil)
                    Button { sharePDF() } label: {
                        Label("Share PDF (WhatsApp, Messages…)", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Send")
                } footer: {
                    Text("WhatsApp cannot receive a file and a typed message together. To send the PDF in WhatsApp, use Share PDF and pick WhatsApp. The message is copied for you to paste. Open WhatsApp chat sends the message only.")
                }

                if let note {
                    Section { Text(note).font(.footnote).foregroundColor(.secondary) }
                }
            }
            .navigationTitle("Send to Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "send-close", placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                guard !prepared else { return }
                prepared = true
                message = defaultMessage()
                let found = lookupPhone()
                phone = found.isEmpty ? info.phone : found
                email = matchedCustomer()?.email ?? ""
            }
            .sheet(item: $mailData) { MailComposerView(mailData: $0) }
            .sheet(item: $shareItem) { ActivityShareSheet(items: [message, $0.url]) }
        }
        .presentationDetents([.large])
    }

    // MARK: Actions
    private func sendEmail() {
        guard MFMailComposeViewController.canSendMail() else {
            note = "Mail isn't set up on this device. Use Share PDF and pick another mail app."
            return
        }
        note = nil
        let to = email.trimmingCharacters(in: .whitespaces)
        mailData = MailData(recipients: to.isEmpty ? [] : [to],
                            subject: subject,
                            body: message,
                            attachmentURL: info.pdfURL,
                            attachmentMIME: "application/pdf",
                            attachmentFilename: info.pdfURL.lastPathComponent)
    }

    private func openWhatsAppChat() {
        guard let number = WhatsAppNumber.normalized(phone) else { return }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/" + number
        components.queryItems = [URLQueryItem(name: "text", value: message)]
        if let url = components.url { openURL(url) }
    }

    private func sharePDF() {
        UIPasteboard.general.string = message
        note = "Message copied. If WhatsApp shows only the PDF, paste it into the chat."
        shareItem = IdentifiableURL(url: info.pdfURL)
    }
}
