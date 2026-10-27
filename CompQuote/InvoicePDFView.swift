import SwiftUI

// The invoice twin of QuotationPDFView: same page, themes and fonts, billed from an Invoice.
struct InvoicePDFView: View {
    let invoice: Invoice

    // Sync storage pointers directly with AppStorageKeys collection
        @AppStorage(AppStorageKeys.selectedPDFLayout) private var selectedPDFLayout = "Corporate Blue (Standard)"
        @AppStorage(AppStorageKeys.invoiceTitle) private var documentTitle = "INVOICE"
        @AppStorage(AppStorageKeys.companyName) private var companyName = "Computech Solutions"
        @AppStorage(AppStorageKeys.companyAddress) private var companyAddress = "123 Tech St, Silicon Valley"
        @AppStorage(AppStorageKeys.companyContact) private var companyContact = "ops@computech.com"
        @AppStorage(AppStorageKeys.defaultBankAccount) private var bankAccount = ""
        @AppStorage(AppStorageKeys.showCompanyLogo) private var showLogo = true
        @AppStorage(AppStorageKeys.uploadedLogoData) private var logoData: Data?
        @AppStorage(AppStorageKeys.companyTagline) private var companyTagline = "Apple Education Reseller • Your Mac environment expert"

    // A4 width: 595pt. Padding 32pt each side = 531pt content width.
    // A4 height 842pt - 64pt vertical padding = 778pt min inner height.
    private let contentWidth:  CGFloat = 531
    private let contentHeight: CGFloat = 778

    var body: some View {
        let layout = PDFLayoutTemplate(rawValue: selectedPDFLayout) ?? .corporate

        VStack(alignment: .leading, spacing: 0) {

            // ── Header ──────────────────────────────────────────────────
            headerBlock(layout: layout)
                .padding(.bottom, 16)

            // ── Client Info Row ──────────────────────────────────────────
            clientBlock(layout: layout)
                .padding(.bottom, 16)

            // ── Items Table ──────────────────────────────────────────────
            itemsTable(layout: layout)
                .padding(.bottom, 12)

            // ── Totals & Bank ────────────────────────────────────────────
            footerBlock(layout: layout)

            // Push signature to the bottom of the page.
            Spacer(minLength: 24)

            // ── Signature Block ──────────────────────────────────────────
            signatureBlock(companyName: companyName, tagline: companyTagline)
        }
        .frame(width: contentWidth, alignment: .topLeading)
        .frame(minHeight: contentHeight, alignment: .topLeading)
        .padding(32)
        .background(layout == .classic ? Color(red: 250/255, green: 248/255, blue: 245/255) : Color.white)
        .font(layout == .charcoal ? .custom("Courier", size: 10) : .system(size: 10))
    }

    // MARK: - Header
    @ViewBuilder
    private func headerBlock(layout: PDFLayoutTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(documentTitle)
                    .font(.system(size: layout == .emerald ? 22 : 20,
                                  weight: layout == .emerald ? .light : .bold))
                    .foregroundColor(layout.accentColor)
                Text("No: \(invoice.invoiceNumber)").font(.system(size: 10))
                Text("Date: \(invoice.date.formatted(date: .long, time: .omitted))")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                if !invoice.quotationNumber.isEmpty {
                    Text("Ref: \(invoice.quotationNumber)")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
                if invoice.status == .paid {
                    Text(paidLine)
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                } else if invoice.isPartiallyPaid {
                    Text("Received \(formatCurrency(invoice.paidAmount))  ·  Balance due \(formatCurrency(invoice.balanceDue))")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.orange)
                }
                if invoice.status != .paid, let due = invoice.dueDate {
                    Text("Due: \(due.formatted(date: .long, time: .omitted))")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                // Logo
                if showLogo, let data = logoData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 54)
                }
                Text(companyName).font(.system(size: 11, weight: .bold))
                Text(companyAddress).font(.system(size: 8)).foregroundColor(.secondary).multilineTextAlignment(.trailing)
                Text(companyContact).font(.system(size: 8)).foregroundColor(.secondary)
            }
        }

        if layout == .charcoal || layout == .classic {
            Rectangle().fill(layout.accentColor).frame(height: 1.5).padding(.top, 6)
        }
    }

    private var paidLine: String {
        guard let paid = invoice.paidDate else { return "PAID" }
        return "PAID  ·  \(paid.formatted(date: .abbreviated, time: .omitted))"
    }

    /// The account printed under "Payment to": the one saved on the invoice, else the Settings default.
    private var payableAccount: String {
        invoice.bankAccountNumber.isEmpty ? bankAccount : invoice.bankAccountNumber
    }

    // MARK: - Client Block
    @ViewBuilder
    private func clientBlock(layout: PDFLayoutTemplate) -> some View {
        let hasStudent = !invoice.studentName.isEmpty || !invoice.studentID.isEmpty
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BILL TO").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                Text(invoice.customerName).font(.system(size: 10, weight: .semibold))
                if !invoice.customerFullAddress.isEmpty {
                    Text(invoice.customerFullAddress)
                        .font(.system(size: 9))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !invoice.customerContactNumber.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill").font(.system(size: 8))
                        Text(invoice.customerContactNumber).font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
                if hasStudent {
                    Text("STUDENT")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.top, 6)
                    Text(studentLine)
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }

    private var studentLine: String {
        switch (invoice.studentName.isEmpty, invoice.studentID.isEmpty) {
        case (false, false): return "\(invoice.studentName)  ·  ID: \(invoice.studentID)"
        case (false, true):  return invoice.studentName
        case (true, false):  return "ID: \(invoice.studentID)"
        case (true, true):   return ""
        }
    }

    // MARK: - Items Table
    @ViewBuilder
    private func itemsTable(layout: PDFLayoutTemplate) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
                Text("QTY").frame(width: 36, alignment: .trailing)
                Text("UNIT PRICE").frame(width: 80, alignment: .trailing)
                Text("SUBTOTAL").frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(layout == .charcoal ? .primary : .white)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(layout == .charcoal ? Color(.systemGray5) : layout.accentColor)

            // Item rows — alternating background for Corporate
            ForEach(Array(invoice.sortedItems.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.itemDescription)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !item.itemCode.isEmpty {
                            Text(item.itemCode)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                    .layoutPriority(1)
                    Text("\(item.qty)").frame(width: 36, alignment: .trailing).font(.system(size: 9))
                    Text(formatCurrency(item.unitPrice)).frame(width: 80, alignment: .trailing).font(.system(size: 9))
                    Text(formatCurrency(item.subTotal)).frame(width: 80, alignment: .trailing)
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(layout == .corporate && index.isMultiple(of: 2) ? Color(.systemGray6) : Color.clear)

                Divider()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.systemGray4), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Footer
    @ViewBuilder
    private func footerBlock(layout: PDFLayoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // ── Totals row ────────────────────────────────────────────────
            HStack(alignment: .bottom) {
                // Payment info (left)
                if !payableAccount.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PAYMENT TO").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                        Text("Account No: \(payableAccount)").font(.system(size: 8))
                        if !invoice.paymentTerm.isEmpty {
                            Text(invoice.paymentTerm).font(.system(size: 8)).foregroundColor(.secondary)
                        }
                    }
                } else if !invoice.paymentTerm.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PAYMENT TERMS").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                        Text(invoice.paymentTerm).font(.system(size: 8))
                    }
                }
                Spacer()
                // Subtotal / discount / tax / grand total (right)
                VStack(alignment: .trailing, spacing: 4) {
                    if invoice.discountAmount > 0 || invoice.taxAmount > 0 {
                        HStack(spacing: 16) {
                            Text("SUBTOTAL").font(.system(size: 8)).foregroundColor(.secondary)
                            Text(formatCurrency(invoice.itemsSubtotal))
                                .font(.system(size: 8)).foregroundColor(.secondary)
                        }
                    }
                    if invoice.discountAmount > 0 {
                        HStack(spacing: 16) {
                            Text("DISCOUNT").font(.system(size: 8)).foregroundColor(.orange)
                            Text("-" + formatCurrency(invoice.discountAmount))
                                .font(.system(size: 8)).foregroundColor(.orange)
                        }
                    }
                    if invoice.taxAmount > 0 {
                        HStack(spacing: 16) {
                            Text(invoice.taxLabel.isEmpty ? "TAX" : invoice.taxLabel.uppercased())
                                .font(.system(size: 8)).foregroundColor(.secondary)
                            Text("+" + formatCurrency(invoice.taxAmount))
                                .font(.system(size: 8)).foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("GRAND TOTAL").font(.system(size: 10, weight: .bold))
                        Text(formatCurrency(invoice.grandTotal))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(layout.accentColor)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(layout == .emerald ? layout.accentColor.opacity(0.1) : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(layout.accentColor, lineWidth: 1))
                    .cornerRadius(4)
                }
            }

            // ── Remarks below payment info ────────────────────────────────
            if !invoice.remarks.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("REMARKS").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(invoice.remarks)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Signature Block
    @ViewBuilder
    private func signatureBlock(companyName: String, tagline: String) -> some View {
        VStack(spacing: 24) {
            HStack(alignment: .bottom, spacing: 40) {
                VStack(spacing: 3) {
                    VStack(spacing: 1) {
                        Text("This is computer generated document")
                            .font(.system(size: 8)).foregroundColor(.secondary)
                        Text("No signature required")
                            .font(.system(size: 8)).foregroundColor(.secondary)
                    }
                    Rectangle().fill(Color.black).frame(width: 180, height: 0.5)
                    Text("For \(companyName)").font(.system(size: 9))
                }
                Spacer()
                VStack(spacing: 3) {
                    Text("Co. Chop and Authorised Sign")
                        .font(.system(size: 8)).foregroundColor(.secondary)
                    Rectangle().fill(Color.black).frame(width: 180, height: 0.5)
                    Text("Received in good order").font(.system(size: 9))
                }
            }
            if !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 9))
                    .tracking(2)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.top, 24)
    }
}
