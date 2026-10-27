import Foundation
import SwiftData
import SwiftUI

// MARK: - Centralized AppStorage Key Registry
enum AppStorageKeys {
    static let selectedPDFLayout   = "selectedPDFLayout"
    static let companyName         = "companyName"
    static let companyAddress      = "companyAddress"
    static let companyContact      = "companyContact"
    static let defaultBankAccount  = "defaultBankAccount"
    static let defaultRemarks      = "defaultRemarks"
    static let showCompanyLogo     = "showCompanyLogo"
    static let uploadedLogoData    = "uploadedLogoData"
    static let quotationTitle      = "quotationTitle"
    static let poTitle             = "poTitle"
    static let serviceReportTitle  = "serviceReportTitle"
    static let invoiceTitle        = "invoiceTitle"
    static let defaultPaymentTerm  = "defaultPaymentTerm"
    static let currencySymbol      = "currencySymbol"
    static let currencyCode        = "currencyCode"
    static let companyTagline      = "companyTagline"
    static let storageMode         = "storageMode"
    // Per-device document number prefixes (deliberately NOT part of backups)
    static let quotationNumberPrefix = "quotationNumberPrefix"
    static let poNumberPrefix        = "poNumberPrefix"
    static let reportNumberPrefix    = "reportNumberPrefix"
    static let invoiceNumberPrefix   = "invoiceNumberPrefix"
    // Keys shared with picker sheets and backup/restore
    static let savedTechnicians    = "savedTechnicians"
    static let customDeviceModels  = "customDeviceModels"
    static let defaultPORemarks    = "defaultPORemarks"
    static let defaultPODeliveryInstructions = "defaultPODeliveryInstructions"
}

// MARK: - Standard Payment Terms
// Shared by CreateQuotationView and EditQuotationView so the lists never drift.
let standardPaymentTerms = [
    "Bank Transfer", "Net 30 Days", "Net 60 Days",
    "50% Deposit, Balance Net 30 Days",
    "Cash on Delivery", "Cash Before Delivery"
]

// MARK: - Auto-Numbering Utility
enum DocumentNumberGenerator {
    static func next(after last: String?) -> String {
        guard let last else { return "" }
        let components = last.components(separatedBy: CharacterSet.decimalDigits.inverted)
        guard let lastNumStr = components.last(where: { !$0.isEmpty }),
              let currentVal = Int(lastNumStr) else { return last + "-1" }
        let padded = String(format: "%0\(lastNumStr.count)d", currentVal + 1)
        if let range = last.range(of: lastNumStr, options: .backwards) {
            return last.replacingCharacters(in: range, with: padded)
        }
        return last + "-1"
    }

    /// Returns the next number after the numerically-highest document number
    /// in the list. A plain string sort would rank "QT-2026-99" above
    /// "QT-2026-100"; this compares the trailing numeric part instead.
    /// "-COPY" suffixes are stripped first, so duplicating a duplicate never
    /// produces "-COPY-COPY".
    /// Same as `next(inAll:)`, but new numbers start with this device's prefix
    /// (e.g. "QA"). The digits continue from the highest number across ALL
    /// documents, whatever their prefix, so two devices with different
    /// prefixes can never produce the same number. Blank prefix = normal.
    static func next(inAll numbers: [String], prefix rawPrefix: String) -> String? {
        let prefix = rawPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return next(inAll: numbers) }
        var best: (value: Int, width: Int)? = nil
        for raw in numbers {
            let cleaned = raw.replacingOccurrences(of: "-COPY", with: "")
            let components = cleaned.components(separatedBy: CharacterSet.decimalDigits.inverted)
            guard let digits = components.last(where: { !$0.isEmpty }),
                  let value = Int(digits) else { continue }
            if best == nil || value > best!.value { best = (value, digits.count) }
        }
        guard let best else { return prefix + "001" }
        return prefix + String(format: "%0\(best.width)d", best.value + 1)
    }

    static func next(inAll numbers: [String]) -> String? {
        var best: (value: Int, number: String)? = nil
        for raw in numbers {
            let cleaned = raw.replacingOccurrences(of: "-COPY", with: "")
            let components = cleaned.components(separatedBy: CharacterSet.decimalDigits.inverted)
            guard let lastNumStr = components.last(where: { !$0.isEmpty }),
                  let value = Int(lastNumStr) else { continue }
            if best == nil || value > best!.value {
                best = (value, cleaned)
            }
        }
        guard let best else { return nil }
        return next(after: best.number)
    }
}

// MARK: - Vendor (for Purchase Orders)
@Model
class Vendor {
    var id: UUID = UUID()
    var name: String = ""
    var company: String = ""
    var contactNumber: String = ""
    var address: String = ""
    var postcode: String = ""
    var state: String = ""
    var country: String = ""
    var email: String = ""
    var notes: String = ""

    init(name: String, company: String, contactNumber: String = "",
         address: String = "", postcode: String = "", state: String = "",
         country: String = "", email: String = "", notes: String = "") {
        self.name = name
        self.company = company
        self.contactNumber = contactNumber
        self.address = address
        self.postcode = postcode
        self.state = state
        self.country = country
        self.email = email
        self.notes = notes
    }

    var fullAddress: String {
        var parts: [String] = []
        if !address.isEmpty  { parts.append(address) }
        var line2 = ""
        if !postcode.isEmpty { line2 += postcode + " " }
        if !state.isEmpty    { line2 += state }
        if !line2.isEmpty    { parts.append(line2.trimmingCharacters(in: .whitespaces)) }
        if !country.isEmpty  { parts.append(country) }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Customer Types
enum CustomerType: String, CaseIterable, Identifiable {
    case personal
    case school
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: return "Personal"
        case .school: return "School"
        case .business: return "Business"
        }
    }

    var symbol: String {
        switch self {
        case .personal: return "person.fill"
        case .school: return "graduationcap.fill"
        case .business: return "building.2.fill"
        }
    }
}

// MARK: - Customer
@Model
class Customer {
    var id: UUID = UUID()
    var name: String = ""
    var company: String = ""
    var contactNumber: String = ""
    var address: String = ""     // street line
    var postcode: String = ""
    var state: String = ""
    var country: String = ""
    var customerTypeRawValue: String? = nil // nil defaults to Personal for existing customers
    var email: String = ""
    var whatsappNumber: String = ""   // only when different from contactNumber

    init(name: String, company: String, contactNumber: String,
         address: String, postcode: String = "", state: String = "", country: String = "",
         customerTypeRawValue: String? = nil) {
        self.name = name
        self.company = company
        self.contactNumber = contactNumber
        self.address = address
        self.postcode = postcode
        self.state = state
        self.country = country
        self.customerTypeRawValue = customerTypeRawValue
    }

    /// Full formatted address for PDF display
    var fullAddress: String {
        var parts: [String] = []
        if !address.isEmpty  { parts.append(address) }
        var cityLine = ""
        if !postcode.isEmpty { cityLine += postcode + " " }
        if !state.isEmpty    { cityLine += state }
        if !cityLine.isEmpty { parts.append(cityLine.trimmingCharacters(in: .whitespaces)) }
        if !country.isEmpty  { parts.append(country) }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Product Categories
// Stored as an optional raw value so existing products migrate as General.
enum ProductCategory: String, CaseIterable, Identifiable {
    case general
    case computer
    case display
    case keyboard
    case mouse
    case printer
    case phoneTablet
    case networking
    case storage
    case cableAdapter
    case audio
    case camera
    case software
    case components
    case accessories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .computer: return "Computer / Laptop"
        case .display: return "Display / Monitor"
        case .keyboard: return "Keyboard"
        case .mouse: return "Mouse / Pointing Device"
        case .printer: return "Printer / Scanner"
        case .phoneTablet: return "Phone / Tablet"
        case .networking: return "Networking"
        case .storage: return "Storage"
        case .cableAdapter: return "Cable / Adapter"
        case .audio: return "Audio"
        case .camera: return "Camera"
        case .software: return "Software / License"
        case .components: return "Parts / Components"
        case .accessories: return "Accessories"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "shippingbox.fill"
        case .computer: return "laptopcomputer"
        case .display: return "display"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .printer: return "printer.fill"
        case .phoneTablet: return "iphone"
        case .networking: return "wifi"
        case .storage: return "externaldrive.fill"
        case .cableAdapter: return "cable.connector"
        case .audio: return "headphones"
        case .camera: return "camera.fill"
        case .software: return "key.fill"
        case .components: return "cpu.fill"
        case .accessories: return "puzzlepiece.extension.fill"
        }
    }
}

// MARK: - Product
@Model
class Product {
    var id: UUID = UUID()
    var itemCode: String = ""
    var itemDescription: String = ""
    var defaultUnitPrice: Double = 0  // SP1
    var defaultCost: Double = 0       // CP1 — actual cost
    // Saved calculator fields so Add Item sheet pre-fills completely
    var defaultSP2: Double = 0        // Selling Price 2
    var defaultCP2: Double = 0        // Cost Price 2 — independent direct input
    var defaultRebate1: Double = 0    // Rebate % for Scenario 1 (reduces CP1 effective cost)
    var defaultRebate2: Double = 0    // Rebate % for Scenario 2
    var defaultDisc1: Double = 0      // Discount % on SP1
    var defaultDisc2: Double = 0      // Discount % on SP2
    var isActive: Bool = true         // Active / Inactive
    var categoryRawValue: String? = nil // nil means General for existing products

    init(itemCode: String, itemDescription: String,
         defaultUnitPrice: Double, defaultCost: Double = 0,
         defaultSP2: Double = 0, defaultCP2: Double = 0,
         defaultRebate1: Double = 0, defaultRebate2: Double = 0,
         defaultDisc1: Double = 0, defaultDisc2: Double = 0,
         isActive: Bool = true, categoryRawValue: String? = nil) {
        self.itemCode = itemCode
        self.itemDescription = itemDescription
        self.defaultUnitPrice = defaultUnitPrice
        self.defaultCost = defaultCost
        self.defaultSP2 = defaultSP2
        self.defaultCP2 = defaultCP2
        self.defaultRebate1 = defaultRebate1
        self.defaultRebate2 = defaultRebate2
        self.defaultDisc1 = defaultDisc1
        self.defaultDisc2 = defaultDisc2
        self.isActive = isActive
        self.categoryRawValue = categoryRawValue
    }

    var margin: Double {
        guard defaultUnitPrice > 0 else { return 0 }
        return ((defaultUnitPrice - defaultCost) / defaultUnitPrice) * 100
    }
}

// MARK: - LineItem
@Model
class LineItem {
    var itemCode: String = ""
    var itemDescription: String = ""
    var qty: Int = 1
    var unitPrice: Double = 0
    var subTotal: Double = 0
    var sortOrder: Int = 0
    // Fulfillment tracking
    var linkedPONumber: String = ""   // PO number that covers this item
    var linkedPOId: String = ""       // PO UUID for navigation
    var isDelivered: Bool = false     // marked delivered by user
    var deliveredDate: Date? = nil    // when it was marked delivered (optional, for sync-safe migration)
    // Billing: the UUID of the invoice that bills this quotation item ("" = not invoiced yet).
    var invoiceId: String = ""
    // Internal profit reference (quotations only, never printed): cost per unit after rebate.
    // 0 = not saved yet, so the margin falls back to the Directory cost.
    var unitCost: Double = 0

    // Inverse links (CloudKit requires every relationship to have an inverse).
    // A line item belongs to either a quotation, a purchase order or an invoice.
    var quotation: Quotation?
    var purchaseOrder: PurchaseOrder?
    var invoice: Invoice?

    init(itemCode: String, itemDescription: String, qty: Int, unitPrice: Double, sortOrder: Int = 0) {
        self.itemCode = itemCode
        self.itemDescription = itemDescription
        self.qty = qty
        self.unitPrice = unitPrice
        self.subTotal = Double(qty) * unitPrice
        self.sortOrder = sortOrder
    }

    func recalculate() {
        subTotal = Double(qty) * unitPrice
    }

    /// True once an invoice bills this quotation item.
    var isInvoiced: Bool { !invoiceId.isEmpty }
}

// MARK: - Quotation Status
enum QuotationStatus: String, CaseIterable, Codable {
    case draft     = "Draft"
    case confirmed = "Confirmed"
    case cancelled = "Cancelled"

    var color: Color {
        switch self {
        case .draft:     return .secondary
        case .confirmed: return .green
        case .cancelled: return .red
        }
    }
    var icon: String {
        switch self {
        case .draft:     return "doc.badge.clock"
        case .confirmed: return "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }
}

// MARK: - Quotation
@Model
class Quotation {
    var id: UUID = UUID()
    var date: Date = Date()
    var quoteNumber: String = ""
    var customerName: String = ""
    // Snapshot of customer address at the time this quotation was created.
    var customerAddress: String = ""
    var customerPostcode: String = ""
    var customerState: String = ""
    var customerCountry: String = ""
    var customerContactNumber: String = ""
    var remarks: String = ""
    var bankAccountNumber: String = ""
    var paymentTerm: String = ""
    // Optional student details — shown on PDF only when non-empty.
    var studentName: String = ""
    var studentID: String = ""
    // Status — stored as String for CloudKit compatibility
    var statusRaw: String = QuotationStatus.draft.rawValue

    var status: QuotationStatus {
        get { QuotationStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }
    // Document-level discount (% and/or fixed $ — user picks)
    var discountPct: Double = 0      // e.g. 10 = 10%
    var discountFixed: Double = 0    // e.g. 50 = $50 off
    // Tax — percentage only
    var taxPct: Double = 0           // e.g. 8 = 8% SST
    var taxLabel: String = "SST"     // e.g. "SST", "GST", "VAT"
    // CloudKit requires relationships to be optional, so the stored list is optional
    // and `items` is a non-optional view of it. originalName keeps existing data attached.
    @Relationship(deleteRule: .cascade, originalName: "items", inverse: \LineItem.quotation) var itemsStorage: [LineItem]? = []
    var items: [LineItem] {
        get { itemsStorage ?? [] }
        set { itemsStorage = newValue }
    }

    init(quoteNumber: String, customerName: String, remarks: String, bankAccountNumber: String, paymentTerm: String = "") {
        self.quoteNumber = quoteNumber
        self.customerName = customerName
        self.remarks = remarks
        self.bankAccountNumber = bankAccountNumber
        self.paymentTerm = paymentTerm
    }

    var sortedItems: [LineItem] { items.sorted { $0.sortOrder < $1.sortOrder } }
    var itemsSubtotal: Double { items.reduce(0) { $0 + $1.subTotal } }
    var discountAmount: Double {
        (itemsSubtotal * discountPct / 100) + discountFixed
    }
    var taxableAmount: Double { max(0, itemsSubtotal - discountAmount) }
    var taxAmount: Double { taxableAmount * taxPct / 100 }
    var grandTotal: Double { taxableAmount + taxAmount }

    /// Multi-line formatted address for the Bill To block. Skips empty pieces.
    var customerFullAddress: String {
        let cityLine = [customerPostcode, customerState]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [customerAddress, cityLine, customerCountry]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

// MARK: - Quotation Margin (internal reference, never printed)
/// Estimates profit for a quotation. Each line uses its own saved cost (`LineItem.unitCost`),
/// which can be edited per quotation without touching the Directory. A line with no saved
/// cost falls back to the Directory product: Cost Price − (Sell Price × Rebate 1 %), the same
/// Eff. Cost the Pricing Calculator shows. Lines with no cost at all are left out of the
/// totals and counted in `missingCount`.
struct QuotationMargin {
    struct Line: Identifiable {
        let item: LineItem
        let revenue: Double      // line total after the document discount, before tax
        let unitCost: Double?    // cost per unit actually used; nil when unknown
        let isSaved: Bool        // true when it comes from the line itself, not the Directory
        let directoryCost: Double?
        let directoryCost1: Double?
        let directoryCost2: Double?
        var id: PersistentIdentifier { item.persistentModelID }
        var cost: Double? { unitCost.map { $0 * Double(item.qty) } }
        var profit: Double? { cost.map { revenue - $0 } }
        var margin: Double? {
            guard let p = profit, revenue > 0 else { return nil }
            return p / revenue * 100
        }
    }

    let lines: [Line]
    var costed: [Line] { lines.filter { $0.cost != nil } }
    var missingCount: Int { lines.count - costed.count }
    var hasData: Bool { !costed.isEmpty }
    var revenue: Double { costed.reduce(0) { $0 + $1.revenue } }
    var cost: Double { costed.reduce(0) { $0 + ($1.cost ?? 0) } }
    var profit: Double { revenue - cost }
    var margin: Double? { revenue > 0 ? profit / revenue * 100 : nil }

    static func normCode(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func lookup(_ products: [Product]) -> [String: Product] {
        var d: [String: Product] = [:]
        for p in products {
            let k = normCode(p.itemCode)
            if !k.isEmpty, d[k] == nil { d[k] = p }
        }
        return d
    }

    /// Scenario 1 cost per unit: CP1 − (SP1 × Rebate 1 %). nil when the product has no cost.
    static func cost1(_ p: Product) -> Double? {
        guard p.defaultCost > 0 else { return nil }
        return max(0, p.defaultCost - p.defaultUnitPrice * p.defaultRebate1 / 100)
    }

    /// Scenario 2 cost per unit: (CP2, or CP1 when blank) − (SP1 × Rebate 2 %).
    /// nil unless the product actually has a second cost or rebate set.
    static func cost2(_ p: Product) -> Double? {
        guard p.defaultCP2 > 0 || p.defaultRebate2 > 0 else { return nil }
        let base = p.defaultCP2 > 0 ? p.defaultCP2 : p.defaultCost
        guard base > 0 else { return nil }
        return max(0, base - p.defaultUnitPrice * p.defaultRebate2 / 100)
    }

    /// Scenario 2 net sell price: SP2 less Discount 2 %. nil when SP2 is not set.
    static func netPrice2(_ p: Product) -> Double? {
        guard p.defaultSP2 > 0 else { return nil }
        return max(0, p.defaultSP2 * (1 - p.defaultDisc2 / 100))
    }

    /// True when the product has a second scenario worth offering.
    static func hasScenario2(_ p: Product) -> Bool {
        p.defaultSP2 > 0 || cost2(p) != nil
    }

    /// Cost per unit for a quoted line: Cost 2 when the line was priced at the Scenario 2 net
    /// price, otherwise Cost 1.
    static func directoryCost(for code: String, unitPrice: Double = 0, lookup: [String: Product]) -> Double? {
        guard let p = lookup[normCode(code)] else { return nil }
        if let np2 = netPrice2(p), let c2 = cost2(p), abs(np2 - unitPrice) < 0.01 { return c2 }
        return cost1(p)
    }

    /// Saves the current Directory cost onto every line that has none yet, so later
    /// Directory changes do not alter this quotation's margin.
    static func freezeCosts(_ quotation: Quotation, products: [Product]) {
        let lk = lookup(products)
        for item in quotation.items where item.unitCost <= 0 {
            if let c = directoryCost(for: item.itemCode, unitPrice: item.unitPrice, lookup: lk), c > 0 {
                item.unitCost = c
            }
        }
    }

    init(quotation: Quotation, lookup: [String: Product]) {
        let sub = quotation.itemsSubtotal
        // Spread the document-level discount across lines in proportion to their value.
        let factor = sub > 0 ? quotation.taxableAmount / sub : 1
        lines = quotation.sortedItems.map { item in
            let dir = QuotationMargin.directoryCost(for: item.itemCode, unitPrice: item.unitPrice, lookup: lookup)
            let saved = item.unitCost > 0
            let p = lookup[QuotationMargin.normCode(item.itemCode)]
            return Line(item: item,
                        revenue: item.subTotal * factor,
                        unitCost: saved ? item.unitCost : dir,
                        isSaved: saved,
                        directoryCost: dir,
                        directoryCost1: p.flatMap { QuotationMargin.cost1($0) },
                        directoryCost2: p.flatMap { QuotationMargin.cost2($0) })
        }
    }

    init(quotation: Quotation, products: [Product]) {
        self.init(quotation: quotation, lookup: QuotationMargin.lookup(products))
    }
}

// MARK: - PurchaseOrder
@Model
class PurchaseOrder {
    var id: UUID = UUID()
    var date: Date = Date()
    var poNumber: String = ""
    var vendorName: String = ""
    var remarks: String = ""
    var deliveryInstructions: String = ""
    // Document-level discount (% and/or fixed $)
    var discountPct: Double = 0
    var discountFixed: Double = 0
    // Tax — percentage only
    var taxPct: Double = 0
    var taxLabel: String = "SST"
    // CloudKit requires relationships to be optional, so the stored list is optional
    // and `items` is a non-optional view of it. originalName keeps existing data attached.
    @Relationship(deleteRule: .cascade, originalName: "items", inverse: \LineItem.purchaseOrder) var itemsStorage: [LineItem]? = []
    var items: [LineItem] {
        get { itemsStorage ?? [] }
        set { itemsStorage = newValue }
    }

    init(poNumber: String, vendorName: String, remarks: String, deliveryInstructions: String) {
        self.poNumber = poNumber
        self.vendorName = vendorName
        self.remarks = remarks
        self.deliveryInstructions = deliveryInstructions
    }

    var sortedItems: [LineItem] { items.sorted { $0.sortOrder < $1.sortOrder } }
    var itemsSubtotal: Double { items.reduce(0) { $0 + $1.subTotal } }
    var discountAmount: Double {
        (itemsSubtotal * discountPct / 100) + discountFixed
    }
    var taxableAmount: Double { max(0, itemsSubtotal - discountAmount) }
    var taxAmount: Double { taxableAmount * taxPct / 100 }
    var grandTotal: Double { taxableAmount + taxAmount }
}

// MARK: - Invoice Status
nonisolated enum InvoiceStatus: String, CaseIterable {
    case unpaid = "Unpaid"
    case paid   = "Paid"

    var color: Color {
        switch self {
        case .unpaid: return .orange
        case .paid:   return .green
        }
    }
    var icon: String {
        switch self {
        case .unpaid: return "clock.fill"
        case .paid:   return "checkmark.seal.fill"
        }
    }
}

// MARK: - Invoice
// Billed from the delivered items of a quotation. The invoice keeps its own copy of the
// customer details and line items, so later edits to the quotation never change it.
@Model
class Invoice {
    var id: UUID = UUID()
    var date: Date = Date()
    var invoiceNumber: String = ""
    var customerName: String = ""
    var customerAddress: String = ""
    var customerPostcode: String = ""
    var customerState: String = ""
    var customerCountry: String = ""
    var customerContactNumber: String = ""
    var studentName: String = ""
    var studentID: String = ""
    var remarks: String = ""
    var bankAccountNumber: String = ""
    var paymentTerm: String = ""
    // The quotation it was billed from. Kept as text so the invoice survives if the quotation is deleted.
    var quotationNumber: String = ""
    var quotationId: String = ""
    // Stored as String for CloudKit compatibility — use the .status computed property.
    var statusRaw: String = InvoiceStatus.unpaid.rawValue
    var paidDate: Date? = nil
    // Payments received, stored as JSON text (CloudKit-friendly, no extra model). Use `payments`.
    var paymentsJSON: String = ""
    // Document-level discount and tax, same rules as a quotation.
    var discountPct: Double = 0
    var discountFixed: Double = 0
    var taxPct: Double = 0
    var taxLabel: String = "SST"
    // CloudKit requires relationships to be optional, so the stored list is optional
    // and `items` is a non-optional view of it.
    @Relationship(deleteRule: .cascade, inverse: \LineItem.invoice) var itemsStorage: [LineItem]? = []
    var items: [LineItem] {
        get { itemsStorage ?? [] }
        set { itemsStorage = newValue }
    }

    init(invoiceNumber: String, customerName: String) {
        self.invoiceNumber = invoiceNumber
        self.customerName = customerName
    }

    var status: InvoiceStatus {
        get { InvoiceStatus(rawValue: statusRaw) ?? .unpaid }
        set { statusRaw = newValue.rawValue }
    }

    var sortedItems: [LineItem] { items.sorted { $0.sortOrder < $1.sortOrder } }
    var itemsSubtotal: Double { items.reduce(0) { $0 + $1.subTotal } }
    var discountAmount: Double {
        (itemsSubtotal * discountPct / 100) + discountFixed
    }
    var taxableAmount: Double { max(0, itemsSubtotal - discountAmount) }
    var taxAmount: Double { taxableAmount * taxPct / 100 }
    var grandTotal: Double { taxableAmount + taxAmount }

    /// Multi-line formatted address for the Bill To block. Skips empty pieces.
    var customerFullAddress: String {
        let cityLine = [customerPostcode, customerState]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return [customerAddress, cityLine, customerCountry]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Gives the billed items back to their quotation, so they can be invoiced again.
    func releaseItems(in context: ModelContext) {
        let key = id.uuidString
        let descriptor = FetchDescriptor<LineItem>(predicate: #Predicate { $0.invoiceId == key })
        guard let billed = try? context.fetch(descriptor) else { return }
        for item in billed { item.invoiceId = "" }
    }
}

// MARK: - Quotation → Invoice helpers
extension Quotation {
    /// Delivered items that are not on an invoice yet.
    var uninvoicedDeliveredItems: [LineItem] {
        sortedItems.filter { $0.isDelivered && !$0.isInvoiced }
    }

    var invoicedItemCount: Int { items.filter { $0.isInvoiced }.count }

    /// "Invoiced" or "2 of 5 invoiced" for the Done list; nil when nothing is invoiced.
    var invoiceNote: String? {
        let done = invoicedItemCount
        guard done > 0 else { return nil }
        return done == items.count ? "Invoiced" : "\(done) of \(items.count) invoiced"
    }

    /// The part of the quotation's fixed-amount discount that belongs on an invoice for `chosen`.
    /// Spread by item value; the invoice that bills the last remaining items takes
    /// whatever is left, so all invoices together add up to the quotation's discount exactly.
    func fixedDiscountShare(for chosen: [LineItem], previousInvoices: [Invoice]) -> Double {
        guard discountFixed > 0, !chosen.isEmpty else { return 0 }
        let used = previousInvoices.reduce(0) { $0 + $1.discountFixed }
        let remaining = max(0, discountFixed - used)
        let stillUnbilled = items.filter { !$0.isInvoiced }.count
        if chosen.count >= stillUnbilled { return remaining }
        guard itemsSubtotal > 0 else { return 0 }
        let share = discountFixed * chosen.reduce(0) { $0 + $1.subTotal } / itemsSubtotal
        return min(remaining, (share * 100).rounded() / 100)
    }
}

// MARK: - ServiceReport
@Model
class ServiceReport {
    var id: UUID = UUID()
    var date: Date = Date()
    var reportNumber: String = ""
    var customerName: String = ""
    var deviceModel: String = ""
    var serialNumber: String = ""
    var issueDescription: String = ""
    var resolution: String = ""
    var technicianName: String = ""
    var notes: String = ""            // internal notes
    // Intake details (all optional text, so older reports and CloudKit stay valid)
    var quotationNumber: String = ""  // quotation raised for this service
    var warrantyStatus: String = ""   // "" = not specified
    var extraItems: String = ""       // accessories sent in with the device
    var conditionCheck: String = ""   // device condition on arrival
    var termsText: String = ""        // terms printed on the PDF (copied from defaultTerms on new reports)
    // Stored as String for CloudKit compatibility — use .status computed property
    var statusRaw: String = ServiceStatus.open.rawValue

    static let warrantyOptions = ["In Warranty", "AppleCare / Extended Warranty", "Out of Warranty"]
    static let defaultTerms = """
1. Diagnostic Fee: If the customer chooses not to proceed with the repair, a minimum diagnostic fee of RM150 will be charged.
2. Equipment Collection: The customer must collect the equipment within three (3) months from the date of notification that the repair has been completed. If the equipment is not collected within this period, Mac Direction Sdn Bhd reserves the right to dispose of the uncollected equipment, subject to applicable laws and regulations.
"""

    // Computed wrapper — use this everywhere in the UI
    var status: ServiceStatus {
        get { ServiceStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    init(reportNumber: String, customerName: String,
         deviceModel: String = "", serialNumber: String = "",
         issueDescription: String, resolution: String,
         technicianName: String, status: ServiceStatus = .open) {
        self.reportNumber = reportNumber
        self.customerName = customerName
        self.deviceModel = deviceModel
        self.serialNumber = serialNumber
        self.issueDescription = issueDescription
        self.resolution = resolution
        self.technicianName = technicianName
        self.notes = ""
        self.statusRaw = status.rawValue
    }
}

enum ServiceStatus: String, Codable, CaseIterable {
    case open       = "Open"
    case inProgress = "In Progress"
    case resolved   = "Resolved"
    case closed     = "Closed"

    var color: Color {
        switch self {
        case .open:       return .orange
        case .inProgress: return .blue
        case .resolved:   return .green
        case .closed:     return .secondary
        }
    }
    var icon: String {
        switch self {
        case .open:       return "exclamationmark.circle"
        case .inProgress: return "wrench.and.screwdriver"
        case .resolved:   return "checkmark.seal"
        case .closed:     return "archivebox"
        }
    }
}

// MARK: - PDF Layout Templates
enum PDFLayoutTemplate: String, CaseIterable, Identifiable {
    case corporate = "Corporate Blue (Standard)"
    case emerald   = "Emerald Modern"
    case charcoal  = "Charcoal Minimal"
    case classic   = "Classic Navy"

    var id: String { rawValue }

    var accentColor: Color {
        switch self {
        case .corporate: return .blue
        case .emerald:   return .green
        case .charcoal:  return .primary
        case .classic:   return Color(red: 15/255, green: 23/255, blue: 42/255)
        }
    }

    // ── ADD THIS AMBIENT COLOR EXTENSION HERE ──────────────────────────
    var ambientColor: Color {
        switch self {
        case .corporate:
            return Color.blue.opacity(0.06)
        case .emerald:
            return Color.green.opacity(0.06)
        case .charcoal:
            return Color(.systemGray6)
        case .classic:
            return Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.06)
        }
    }
}

// MARK: - Shared TempLineItem
struct TempLineItem: Identifiable {
    let id = UUID()
    var itemCode: String
    var itemDescription: String
    var qty: Int
    var unitPrice: Double
    var unitCost: Double = 0   // internal margin reference; 0 = not set
    var subTotal: Double { Double(qty) * unitPrice }
}

// MARK: - Purchase Order delivery state
// A PO tracks delivery item by item: each line item has its own delivered tick.
nonisolated enum DeliveryState: Equatable {
    case awaiting, partial, delivered

    var label: String {
        switch self {
        case .awaiting:  return "Awaiting delivery"
        case .partial:   return "Partly delivered"
        case .delivered: return "Delivered"
        }
    }
    var color: Color {
        switch self {
        case .awaiting:  return .blue
        case .partial:   return .orange
        case .delivered: return .green
        }
    }
    var icon: String {
        switch self {
        case .awaiting:  return "shippingbox.fill"
        case .partial:   return "circle.lefthalf.filled"
        case .delivered: return "checkmark.seal.fill"
        }
    }
}

extension PurchaseOrder {
    var deliveredCount: Int { items.filter { $0.isDelivered }.count }

    var deliveryState: DeliveryState {
        let total = items.count
        guard total > 0 else { return .awaiting }
        let done = deliveredCount
        if done == 0 { return .awaiting }
        return done == total ? .delivered : .partial
    }

    /// "2 of 5 delivered" for a partly delivered order, otherwise nil.
    var deliveryNote: String? {
        deliveryState == .partial ? "\(deliveredCount) of \(items.count) delivered" : nil
    }
}
