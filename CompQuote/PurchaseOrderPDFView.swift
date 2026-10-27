import SwiftUI

struct PurchaseOrderPDFView: View {
    let order: PurchaseOrder

    // Sync storage pointers directly with AppStorageKeys collection
        @AppStorage(AppStorageKeys.selectedPDFLayout) private var selectedPDFLayout = "Corporate Blue (Standard)"
        @AppStorage(AppStorageKeys.poTitle) private var documentTitle = "PURCHASE ORDER"
        @AppStorage(AppStorageKeys.companyName) private var companyName = "Computech Solutions"
        @AppStorage(AppStorageKeys.companyAddress) private var companyAddress = "123 Tech St, Silicon Valley"
        @AppStorage(AppStorageKeys.companyContact) private var companyContact = "ops@computech.com"
        @AppStorage(AppStorageKeys.showCompanyLogo) private var showLogo = true
        @AppStorage(AppStorageKeys.uploadedLogoData) private var logoData: Data?
        @AppStorage(AppStorageKeys.companyTagline) private var companyTagline = "Apple Education Reseller • Your Mac environment expert"
    
    private let contentWidth:  CGFloat = 531
    private let contentHeight: CGFloat = 778

    var body: some View {
        let layout = PDFLayoutTemplate(rawValue: selectedPDFLayout) ?? .corporate

        VStack(alignment: .leading, spacing: 0) {
            headerBlock(layout: layout).padding(.bottom, 16)
            vendorBlock(layout: layout).padding(.bottom, 16)
            itemsTable(layout: layout).padding(.bottom, 12)
            footerBlock(layout: layout)

            // Push signature to the bottom of the page.
            Spacer(minLength: 24)

            // ── Signature Block ──────────────────────────────────────────
            signatureBlock(companyName: companyName, tagline: companyTagline)
        }
        .frame(width: contentWidth, alignment: .topLeading)
        .frame(minHeight: contentHeight, alignment: .topLeading)
        .padding(32)
        .background(Color.white)
        .font(.system(size: 10))
    }

    // MARK: - Header
    @ViewBuilder
    private func headerBlock(layout: PDFLayoutTemplate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(documentTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(layout.accentColor)
                Text("PO No: \(order.poNumber)").font(.system(size: 10))
                Text("Date: \(order.date.formatted(date: .long, time: .omitted))")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if showLogo, let data = logoData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 54)
                }
                Text(companyName).font(.system(size: 11, weight: .bold))
                Text(companyAddress).font(.system(size: 8)).foregroundColor(.secondary).multilineTextAlignment(.trailing)
                Text(companyContact).font(.system(size: 8)).foregroundColor(.secondary)
            }
        }

        Rectangle().fill(layout.accentColor).frame(height: 1.5).padding(.top, 6)
    }

    // MARK: - Vendor Block
    @ViewBuilder
    private func vendorBlock(layout: PDFLayoutTemplate) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SUPPLIER / VENDOR").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                Text(order.vendorName).font(.system(size: 10, weight: .semibold))
            }
            Spacer()
            if !order.deliveryInstructions.isEmpty {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("DELIVERY").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(order.deliveryInstructions).font(.system(size: 8)).foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 180)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }

    // MARK: - Items Table
    @ViewBuilder
    private func itemsTable(layout: PDFLayoutTemplate) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
                Text("QTY").frame(width: 36, alignment: .trailing)
                Text("UNIT PRICE").frame(width: 80, alignment: .trailing)
                Text("SUBTOTAL").frame(width: 80, alignment: .trailing)
            }
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(layout.accentColor)

            ForEach(Array(order.sortedItems.enumerated()), id: \.element.id) { index, item in
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
                .background(index.isMultiple(of: 2) ? Color(.systemGray6) : Color.clear)

                Divider()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.systemGray4), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Footer
    @ViewBuilder
    private func footerBlock(layout: PDFLayoutTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !order.remarks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("REMARKS / PAYMENT TERMS").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(order.remarks)
                        .font(.system(size: 8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(4)
            }

            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if order.discountAmount > 0 || order.taxAmount > 0 {
                        HStack(spacing: 16) {
                            Text("SUBTOTAL").font(.system(size: 8)).foregroundColor(.secondary)
                            Text(formatCurrency(order.itemsSubtotal))
                                .font(.system(size: 8)).foregroundColor(.secondary)
                        }
                    }
                    if order.discountAmount > 0 {
                        HStack(spacing: 16) {
                            Text("DISCOUNT").font(.system(size: 8)).foregroundColor(.orange)
                            Text("-" + formatCurrency(order.discountAmount))
                                .font(.system(size: 8)).foregroundColor(.orange)
                        }
                    }
                    if order.taxAmount > 0 {
                        HStack(spacing: 16) {
                            Text(order.taxLabel.isEmpty ? "TAX" : order.taxLabel.uppercased())
                                .font(.system(size: 8)).foregroundColor(.secondary)
                            Text("+" + formatCurrency(order.taxAmount))
                                .font(.system(size: 8)).foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("TOTAL ORDER VALUE").font(.system(size: 10, weight: .bold))
                        Text(formatCurrency(order.grandTotal))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(layout.accentColor)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(layout.accentColor, lineWidth: 1))
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
                    Text("Your order confirmation").font(.system(size: 9))
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
