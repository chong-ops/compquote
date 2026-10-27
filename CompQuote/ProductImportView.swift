import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Import Hub
// Three-tab importer: Products, Customers, Vendors
// All use the same CSV conventions:
//   • First row = header (case-insensitive, any order)
//   • Blank optional cells → keep existing value on update
//   • Match key: itemCode (products), name+company (customers/vendors)

struct ProductImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0

    private let tabs: [(label: String, icon: String)] = [
        ("Products",  "shippingbox"),
        ("Customers", "person.2"),
        ("Vendors",   "building.2")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = i }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tabs[i].icon)
                                    .font(.system(size: 16, weight: selectedTab == i ? .semibold : .regular))
                                Text(tabs[i].label)
                                    .font(.system(size: 11, weight: selectedTab == i ? .semibold : .regular))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(selectedTab == i ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color(.systemGroupedBackground))
                .overlay(
                    GeometryReader { geo in
                        let w = geo.size.width / CGFloat(tabs.count)
                        Rectangle().fill(Color.blue).frame(width: w, height: 2)
                            .offset(x: w * CGFloat(selectedTab))
                            .animation(.easeInOut(duration: 0.18), value: selectedTab)
                    },
                    alignment: .bottom
                )
                Divider()

                TabView(selection: $selectedTab) {
                    ProductImportTab().tag(0)
                    CustomerImportTab().tag(1)
                    VendorImportTab().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Import Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "done-import", placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Shared Import Result
struct ImportResult {
    var created = 0
    var updated = 0
    var skipped = 0
    var skippedRows: [String] = []
}

// MARK: - Shared CSV parser
func parseCSVRow(_ row: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var inQuotes = false
    for char in row {
        if char == "\"" { inQuotes.toggle() }
        else if char == "," && !inQuotes {
            fields.append(current.trimmingCharacters(in: .whitespaces))
            current = ""
        } else { current.append(char) }
    }
    fields.append(current.trimmingCharacters(in: .whitespaces))
    return fields
}

func readCSV(url: URL) -> String? {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    guard let data = try? Data(contentsOf: url) else { return nil }
    var text: String?
    if let s = String(data: data, encoding: .utf8) { text = s }
    // Excel for Mac "CSV" is Mac Roman: its non-breaking space is byte 0xCA (shows as "Ê" if misread).
    else if data.contains(0xCA), let s = String(data: data, encoding: .macOSRoman) { text = s }
    else if let s = String(data: data, encoding: .windowsCP1252) { text = s }
    else if let s = String(data: data, encoding: .isoLatin1) { text = s }
    // Turn non-breaking spaces / hyphens into plain ones so search and PDFs behave.
    return text?
        .replacingOccurrences(of: "\u{00A0}", with: " ")
        .replacingOccurrences(of: "\u{202F}", with: " ")
        .replacingOccurrences(of: "\u{2011}", with: "-")
}

// MARK: - Shared Import Form Shell
struct ImportFormShell<Content: View>: View {
    let title: String
    let templateURL: URL?
    let templateSubject: String
    let showPicker: Binding<Bool>
    let isProcessing: Bool
    let errorMessage: String?
    let importResult: ImportResult?
    let resultLabel: String          // e.g. "products"
    let columnGuide: Content

    init(title: String, templateURL: URL?, templateSubject: String,
         showPicker: Binding<Bool>, isProcessing: Bool,
         errorMessage: String?, importResult: ImportResult?,
         resultLabel: String,
         @ViewBuilder columnGuide: () -> Content) {
        self.title = title
        self.templateURL = templateURL
        self.templateSubject = templateSubject
        self.showPicker = showPicker
        self.isProcessing = isProcessing
        self.errorMessage = errorMessage
        self.importResult = importResult
        self.resultLabel = resultLabel
        self.columnGuide = columnGuide()
    }

    var body: some View {
        Form {
            Section {
                if let url = templateURL {
                    ShareLink(item: url, subject: Text(templateSubject),
                              message: Text("Fill this in and import back into CompQuote")) {
                        Label("Download CSV Template", systemImage: "arrow.down.doc.fill")
                    }
                }
            } header: {
                SettingsSectionHeader(icon: "doc.text", title: "Step 1 — Get Template")
            } footer: {
                Text("Fill in the template using Numbers, Excel, or Google Sheets. Save as CSV before importing.")
            }

            Section {
                Button { showPicker.wrappedValue = true } label: {
                    Label("Choose CSV File", systemImage: "square.and.arrow.down")
                }
                .disabled(isProcessing)

                if isProcessing {
                    HStack {
                        ProgressView().padding(.trailing, 4)
                        Text("Processing…").foregroundColor(.secondary)
                    }
                }
                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red).font(.caption)
                }
            } header: {
                SettingsSectionHeader(icon: "square.and.arrow.down", title: "Step 2 — Import")
            }

            if let r = importResult {
                Section {
                    ImportResultRow(icon: "plus.circle.fill",           color: .green,
                                   label: "New \(resultLabel) created", count: r.created)
                    ImportResultRow(icon: "arrow.triangle.2.circlepath", color: .blue,
                                   label: "Existing \(resultLabel) updated", count: r.updated)
                    ImportResultRow(icon: "xmark.circle.fill",          color: .red,
                                   label: "Rows skipped",               count: r.skipped)
                    if !r.skippedRows.isEmpty {
                        Text(r.skippedRows.joined(separator: ", "))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                } header: {
                    SettingsSectionHeader(icon: "checkmark.seal", title: "Import Results")
                }
            }

            Section {
                columnGuide
            } header: {
                SettingsSectionHeader(icon: "table", title: "Column Reference")
            } footer: {
                Text("Headers are case-insensitive and can be in any order. Blank optional cells preserve existing values on update.")
            }
        }
    }
}

// MARK: - Products Tab
struct ProductImportTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Product.itemCode) private var products: [Product]

    @State private var showPicker = false
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var importResult: ImportResult? = nil
    @State private var pendingCSV: ParsedCSV? = nil      // file waiting for column matching

    var body: some View {
        ImportFormShell(
            title: "Products",
            templateURL: makeTemplate(),
            templateSubject: "Product Import Template",
            showPicker: $showPicker,
            isProcessing: isProcessing,
            errorMessage: errorMessage,
            importResult: importResult,
            resultLabel: "products"
        ) {
            ColRow("itemCode",        req: true,  "Unique SKU / product code")
            ColRow("itemDescription", req: true,  "Product name or description")
            ColRow("sellPrice",       req: false, "Selling Price 1 (SP1)")
            ColRow("costPrice",       req: false, "Cost Price 1 (CP1)")
            ColRow("sellPrice2",      req: false, "Selling Price 2 (SP2)")
            ColRow("costPrice2",      req: false, "Cost Price 2 (CP2)")
            ColRow("rebate1",         req: false, "Rebate % — Scenario 1 (reduces CP1)")
            ColRow("rebate2",         req: false, "Rebate % — Scenario 2 (used to set CP2 if needed)")
            ColRow("discount1",       req: false, "Discount % on SP1")
            ColRow("discount2",       req: false, "Discount % on SP2")
            ColRow("isActive",        req: false, "TRUE or FALSE (default TRUE)")
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let url = urls.first { process(url: url) }
        }
        .sheet(item: $pendingCSV) { csv in
            ProductMappingSheet(source: csv) { chosen, mapping in
                runImport(csv: chosen, mapping: mapping)
            }
        }
    }

    // Step 1: read the file and show the column-matching sheet.
    private func process(url: URL) {
        isProcessing = true; errorMessage = nil; importResult = nil
        guard var raw = readCSV(url: url) else {
            errorMessage = "Could not read file. Save as CSV (UTF-8)."; isProcessing = false; return
        }
        // Strip UTF-8 BOM (byte order mark) added by Excel/Numbers
        if raw.hasPrefix("﻿") { raw = String(raw.dropFirst()) }

        let lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { errorMessage = "No data rows found."; isProcessing = false; return }

        // The header row may sit below title lines (e.g. "Price Book", "Effective: ...").
        // Use the first line that has an item-code column plus at least one more known column;
        // otherwise fall back to the first line.
        var headerIdx = 0
        for (i, l) in lines.prefix(50).enumerated() {
            let m = ProductField.autoMapping(for: parseCSVRow(l))
            if m[.itemCode] != nil && m.count >= 2 { headerIdx = i; break }
        }
        isProcessing = false
        pendingCSV = ParsedCSV(allRows: lines.map { parseCSVRow($0) }, headerRow: headerIdx)
    }

    // Step 2: import using the column mapping the user confirmed.
    private func runImport(csv: ParsedCSV, mapping: [ProductField: Int]) {
        guard let codeIdx = mapping[.itemCode] else {
            errorMessage = "Choose which column holds the item code."; return
        }
        isProcessing = true; errorMessage = nil; importResult = nil

        var map: [String: Product] = [:]
        for p in products { map[p.itemCode.lowercased()] = p }
        var result = ImportResult()

        for (n, cols) in csv.rows.enumerated() {
            let rowNo = n + 2                       // row 1 is the header
            let code = codeIdx < cols.count ? cols[codeIdx].trimmingCharacters(in: .whitespaces) : ""
            guard !code.isEmpty else {
                result.skipped += 1; result.skippedRows.append("row \(rowNo)"); continue
            }

            func dbl(_ f: ProductField) -> Double? {
                guard let i = mapping[f], i < cols.count else { return nil }
                let raw = cols[i].replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                if raw.isEmpty { return nil }          // blank cell → nil (skip update)
                return Double(raw) ?? nil              // "3.5" → 3.5, "0" → 0.0
            }
            func str(_ f: ProductField) -> String? {
                guard let i = mapping[f], i < cols.count else { return nil }
                let s = cols[i].trimmingCharacters(in: .whitespaces); return s.isEmpty ? nil : s
            }

            // Only import real product rows: item code, description and a sell price must all have data.
            // This also skips title lines, section headings and the header row itself.
            guard str(.itemDescription) != nil, (dbl(.sellPrice) ?? 0) > 0 else {
                result.skipped += 1; result.skippedRows.append("row \(rowNo)"); continue
            }

            let active = (str(.isActive)?.lowercased() ?? "true") != "false"

            if let existing = map[code.lowercased()] {
                if let v = str(.itemDescription) { existing.itemDescription = v }
                // Prices: only update if value > 0 (blank cell = keep existing)
                if let v = dbl(.sellPrice),  v > 0 { existing.defaultUnitPrice = v }
                if let v = dbl(.costPrice),  v > 0 { existing.defaultCost      = v }
                if let v = dbl(.sellPrice2), v > 0 { existing.defaultSP2       = v }
                if let v = dbl(.costPrice2), v > 0 { existing.defaultCP2       = v }
                // Rebates & discounts: update if cell is non-blank (0 is valid — means "clear")
                if let v = dbl(.rebate1)   { existing.defaultRebate1 = v }
                if let v = dbl(.rebate2)   { existing.defaultRebate2 = v }
                if let v = dbl(.discount1) { existing.defaultDisc1   = v }
                if let v = dbl(.discount2) { existing.defaultDisc2   = v }
                if mapping[.isActive] != nil { existing.isActive = active }
                result.updated += 1
            } else {
                let p = Product(
                    itemCode: code,
                    itemDescription: str(.itemDescription) ?? code,
                    defaultUnitPrice: dbl(.sellPrice)  ?? 0,
                    defaultCost:      dbl(.costPrice)  ?? 0,
                    defaultSP2:       dbl(.sellPrice2) ?? 0,
                    defaultCP2:       dbl(.costPrice2) ?? 0,
                    defaultRebate1:   dbl(.rebate1)    ?? 0,
                    defaultRebate2:   dbl(.rebate2)    ?? 0,
                    defaultDisc1:     dbl(.discount1)  ?? 0,
                    defaultDisc2:     dbl(.discount2)  ?? 0,
                    isActive: active
                )
                modelContext.insert(p)
                map[code.lowercased()] = p             // a repeated code later in the file updates this one
                result.created += 1
            }
        }
        try? modelContext.save()
        importResult = result
        isProcessing = false
    }

    private func makeTemplate() -> URL? {
        let rows = [
            "itemCode,itemDescription,sellPrice,costPrice,sellPrice2,costPrice2,rebate1,rebate2,discount1,discount2,isActive",
            "SKU-001,Sample Product One,299.00,180.00,,,,,,,TRUE",
            "SKU-002,Sample Product Two,499.00,310.00,260.00,250.00,5,3,10,8,TRUE"
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CompQuote_Products_Template.csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Product column matching
struct ParsedCSV: Identifiable {
    let id = UUID()
    let allRows: [[String]]      // every non-blank line of the file
    let headerRow: Int           // 0-based index of the header line
    var headers: [String] { allRows.indices.contains(headerRow) ? allRows[headerRow] : [] }
    var rows: [[String]] { allRows.indices.contains(headerRow) ? Array(allRows.suffix(from: headerRow + 1)) : [] }
    func withHeader(_ i: Int) -> ParsedCSV { ParsedCSV(allRows: allRows, headerRow: i) }
}

enum ProductField: String, CaseIterable, Identifiable {
    case itemCode, itemDescription, sellPrice, costPrice, sellPrice2, costPrice2
    case rebate1, rebate2, discount1, discount2, isActive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .itemCode:        return "Item Code"
        case .itemDescription: return "Description"
        case .sellPrice:       return "Sell Price (SP1)"
        case .costPrice:       return "Cost Price (CP1)"
        case .sellPrice2:      return "Sell Price 2 (SP2)"
        case .costPrice2:      return "Cost Price 2 (CP2)"
        case .rebate1:         return "Rebate 1 %"
        case .rebate2:         return "Rebate 2 %"
        case .discount1:       return "Discount 1 %"
        case .discount2:       return "Discount 2 %"
        case .isActive:        return "Active (TRUE/FALSE)"
        }
    }
    var isRequired: Bool { self == .itemCode }

    // Header names recognised automatically (lower-case)
    var aliases: [String] {
        switch self {
        case .itemCode:        return ["itemcode","item code","item no","item no.","item number","code","sku","part no","part no.","part number","product code","model"]
        case .itemDescription: return ["itemdescription","item description","description","desc","product description","product name","item name","name","details"]
        case .sellPrice:       return ["sellprice","sell price","unitprice","price","sp1"]
        case .costPrice:       return ["costprice","cost price","cost","cp1"]
        case .sellPrice2:      return ["sellprice2","sell price 2","sp2"]
        case .costPrice2:      return ["costprice2","cost price 2","cp2"]
        case .rebate1:         return ["rebate1","rebate 1","rebate1%"]
        case .rebate2:         return ["rebate2","rebate 2","rebate2%"]
        case .discount1:       return ["discount1","discount 1","disc1","disc1%"]
        case .discount2:       return ["discount2","discount 2","disc2","disc2%"]
        case .isActive:        return ["isactive","is active","active"]
        }
    }

    // Guess the matching column from the file's headers.
    static func autoMapping(for headers: [String]) -> [ProductField: Int] {
        let lower = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        var result: [ProductField: Int] = [:]
        for f in ProductField.allCases {
            if let i = f.aliases.compactMap({ lower.firstIndex(of: $0) }).first { result[f] = i }
        }
        return result
    }
}

struct ProductMappingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: ParsedCSV
    let onImport: (ParsedCSV, [ProductField: Int]) -> Void
    @State private var headerRow: Int
    @State private var mapping: [ProductField: Int]

    private var csv: ParsedCSV { source.withHeader(headerRow) }

    init(source: ParsedCSV, onImport: @escaping (ParsedCSV, [ProductField: Int]) -> Void) {
        self.source = source
        self.onImport = onImport
        _headerRow = State(initialValue: source.headerRow)
        _mapping = State(initialValue: ProductField.autoMapping(for: source.headers))
    }

    private func headerTitle(_ i: Int) -> String {
        let h = csv.headers[i].trimmingCharacters(in: .whitespaces)
        return h.isEmpty ? "Column \(i + 1)" : h
    }

    private func sample(_ f: ProductField) -> String? {
        guard let i = mapping[f] else { return nil }
        for row in csv.rows where i < row.count && !row[i].isEmpty { return row[i] }
        return nil
    }

    // Up to 3 different sample values from the chosen column.
    private func samples(_ f: ProductField) -> [String] {
        guard let i = mapping[f] else { return [] }
        var out: [String] = []
        for row in csv.rows where i < row.count && !row[i].isEmpty && !out.contains(row[i]) {
            out.append(row[i]); if out.count == 3 { break }
        }
        return out
    }

    // True when every non-blank cell in the chosen column is identical (likely the wrong column).
    private func isSameEverywhere(_ f: ProductField) -> Bool {
        guard let i = mapping[f] else { return false }
        let vals = csv.rows.compactMap { i < $0.count && !$0[i].isEmpty ? $0[i] : nil }
        return vals.count > 1 && Set(vals).count == 1
    }

    private func binding(_ f: ProductField) -> Binding<Int> {
        Binding(get: { mapping[f] ?? -1 },
                set: { mapping[f] = $0 < 0 ? nil : $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $headerRow, in: 0...max(0, min(source.allRows.count - 2, 60))) {
                        Text("Header row: line \(headerRow + 1)")
                    }
                    .onChange(of: headerRow) { _, _ in
                        mapping = ProductField.autoMapping(for: csv.headers)
                    }
                    Text(csv.headers.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundColor(.secondary).lineLimit(2)
                } header: {
                    Text("Header Row")
                } footer: {
                    Text("Use this if the file has title lines above the column names. Everything above this line is ignored.")
                }
                Section {
                    Text("\(csv.rows.count) rows found. Choose which column in your file goes into each CompQuote field. Matches were filled in automatically where the header was recognised.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                Section {
                    ForEach(ProductField.allCases) { f in
                        VStack(alignment: .leading, spacing: 4) {
                            Picker(selection: binding(f)) {
                                Text("Don't import").tag(-1)
                                ForEach(csv.headers.indices, id: \.self) { i in
                                    Text(headerTitle(i)).tag(i)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(f.title)
                                    if f.isRequired { Text("*").foregroundColor(.red) }
                                }
                            }
                            ForEach(samples(f), id: \.self) { s in
                                Text("e.g. \(s)")
                                    .font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                            if isSameEverywhere(f) {
                                Text("Every row has the same value in this column. Check it is the right one.")
                                    .font(.caption).foregroundColor(.red)
                            }
                            if let i = mapping[f], ProductField.allCases.contains(where: { $0 != f && mapping[$0] == i }) {
                                Text("Same column is also used by another field")
                                    .font(.caption).foregroundColor(.orange)
                            }
                        }
                    }
                } header: {
                    Text("Match Columns")
                } footer: {
                    Text("Only rows with an item code, a description and a sell price are imported. All other rows (titles, headings, blanks) are skipped. Blank cells keep the existing value when a product is updated.")
                }
            }
            .navigationTitle("Match Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "map-cancel", placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "map-import", placement: .confirmationAction) {
                    Button("Import") { onImport(csv, mapping); dismiss() }
                        .disabled(mapping[.itemCode] == nil || mapping[.itemDescription] == nil || mapping[.sellPrice] == nil)
                }
            }
        }
    }
}

// MARK: - Customers Tab
struct CustomerImportTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Customer.name) private var customers: [Customer]

    @State private var showPicker = false
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var importResult: ImportResult? = nil

    var body: some View {
        ImportFormShell(
            title: "Customers",
            templateURL: makeTemplate(),
            templateSubject: "Customer Import Template",
            showPicker: $showPicker,
            isProcessing: isProcessing,
            errorMessage: errorMessage,
            importResult: importResult,
            resultLabel: "customers"
        ) {
            ColRow("name",          req: true,  "Full contact name — used as match key")
            ColRow("company",       req: true,  "Company name — used as match key")
            ColRow("contactNumber", req: false, "Phone number")
            ColRow("address",       req: false, "Street address")
            ColRow("postcode",      req: false, "Postcode")
            ColRow("state",         req: false, "State or city")
            ColRow("country",       req: false, "Country")
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let url = urls.first { process(url: url) }
        }
    }

    private func process(url: URL) {
        isProcessing = true; errorMessage = nil; importResult = nil
        guard var raw = readCSV(url: url) else {
            errorMessage = "Could not read file."; isProcessing = false; return
        }
                // Strip UTF-8 BOM (byte order mark) added by Excel/Numbers
        if raw.hasPrefix("﻿") { raw = String(raw.dropFirst()) }

        var lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { errorMessage = "No data rows found."; isProcessing = false; return }

        var headerLine = lines.removeFirst()
        if headerLine.hasPrefix("﻿") { headerLine = String(headerLine.dropFirst()) }
        let headers = parseCSVRow(headerLine).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ names: String...) -> Int? { names.compactMap { headers.firstIndex(of: $0) }.first }

        let nameIdx    = col("name","full name","contact name","contact")
        guard let companyIdx = col("company","company name","organisation","organization") else {
            errorMessage = "Missing column 'company'. Found: \(headers.joined(separator: ", "))"; isProcessing = false; return
        }
        let phoneIdx    = col("contactnumber","contact number","phone","mobile","tel")
        let emailIdx    = col("email","e-mail")
        let waIdx       = col("whatsappnumber","whatsapp number","whatsapp","wa")
        let addrIdx     = col("address","street","street address")
        let postcodeIdx = col("postcode","postal code","zip")
        let stateIdx    = col("state","city","state/city")
        let countryIdx  = col("country")

        // Match key: name + company — supports multiple contacts per company
        var map: [String: Customer] = [:]
        for c in customers { map["\(c.name.lowercased())|\(c.company.lowercased())"] = c }
        var result = ImportResult()

        for line in lines {
            let cols = parseCSVRow(line)
            func str(_ i: Int?) -> String? {
                guard let i, i < cols.count else { return nil }
                let s = cols[i].trimmingCharacters(in: .whitespaces); return s.isEmpty ? nil : s
            }

            guard let company = str(companyIdx) else {
                result.skipped += 1; result.skippedRows.append("(missing company)"); continue
            }
            let name = str(nameIdx) ?? company
            let key = "\(name.lowercased())|\(company.lowercased())"

            if let existing = map[key] {
                if let v = str(phoneIdx)    { existing.contactNumber = v }
                if let v = str(emailIdx)    { existing.email         = v }
                if let v = str(waIdx)       { existing.whatsappNumber = v }
                if let v = str(addrIdx)     { existing.address       = v }
                if let v = str(postcodeIdx) { existing.postcode      = v }
                if let v = str(stateIdx)    { existing.state         = v }
                if let v = str(countryIdx)  { existing.country       = v }
                result.updated += 1
            } else {
                let c = Customer(
                    name: name, company: company,
                    contactNumber: str(phoneIdx)    ?? "",
                    address:       str(addrIdx)     ?? "",
                    postcode:      str(postcodeIdx) ?? "",
                    state:         str(stateIdx)    ?? "",
                    country:       str(countryIdx)  ?? ""
                )
                c.email = str(emailIdx) ?? ""
                c.whatsappNumber = str(waIdx) ?? ""
                modelContext.insert(c)
                result.created += 1
            }
        }
        try? modelContext.save()
        importResult = result
        isProcessing = false
    }

    private func makeTemplate() -> URL? {
        let rows = [
            "name,company,contactNumber,email,whatsappNumber,address,postcode,state,country",
            "Ahmad bin Ali,Syarikat Maju Sdn Bhd,+60123456789,ahmad@example.com,,No 12 Jalan Utama,47500,Subang Jaya,Malaysia",
            "Lee Wei Ming,Tech Solutions Sdn Bhd,+60198765432,lee@example.com,+60111222333,Unit 5 Menara Biz,50450,Kuala Lumpur,Malaysia"
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CompQuote_Customers_Template.csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Vendors Tab
struct VendorImportTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vendor.name) private var vendors: [Vendor]

    @State private var showPicker = false
    @State private var isProcessing = false
    @State private var errorMessage: String? = nil
    @State private var importResult: ImportResult? = nil

    var body: some View {
        ImportFormShell(
            title: "Vendors",
            templateURL: makeTemplate(),
            templateSubject: "Vendor Import Template",
            showPicker: $showPicker,
            isProcessing: isProcessing,
            errorMessage: errorMessage,
            importResult: importResult,
            resultLabel: "vendors"
        ) {
            ColRow("name",          req: true,  "Contact name — used as match key")
            ColRow("company",       req: true,  "Company name — used as match key")
            ColRow("contactNumber", req: false, "Phone number")
            ColRow("email",         req: false, "Email address")
            ColRow("address",       req: false, "Street address")
            ColRow("postcode",      req: false, "Postcode")
            ColRow("state",         req: false, "State or city")
            ColRow("country",       req: false, "Country")
            ColRow("notes",         req: false, "Internal notes about this vendor")
        }
        .fileImporter(isPresented: $showPicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: false) { res in
            if case .success(let urls) = res, let url = urls.first { process(url: url) }
        }
    }

    private func process(url: URL) {
        isProcessing = true; errorMessage = nil; importResult = nil
        guard var raw = readCSV(url: url) else {
            errorMessage = "Could not read file."; isProcessing = false; return
        }
                // Strip UTF-8 BOM (byte order mark) added by Excel/Numbers
        if raw.hasPrefix("﻿") { raw = String(raw.dropFirst()) }

        var lines = raw.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count >= 2 else { errorMessage = "No data rows found."; isProcessing = false; return }

        var headerLine = lines.removeFirst()
        if headerLine.hasPrefix("﻿") { headerLine = String(headerLine.dropFirst()) }
        let headers = parseCSVRow(headerLine).map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func col(_ names: String...) -> Int? { names.compactMap { headers.firstIndex(of: $0) }.first }

        let nameIdx     = col("name","contact name","contact")
        guard let companyIdx = col("company","company name","supplier") else {
            errorMessage = "Missing column 'company'. Found: \(headers.joined(separator: ", "))"; isProcessing = false; return
        }
        let phoneIdx    = col("contactnumber","contact number","phone","mobile","tel")
        let emailIdx    = col("email","e-mail")
        let addrIdx     = col("address","street","street address")
        let postcodeIdx = col("postcode","postal code","zip")
        let stateIdx    = col("state","city","state/city")
        let countryIdx  = col("country")
        let notesIdx    = col("notes","remarks","internal notes")

        // Match key: name + company — supports multiple contacts per company
        var map: [String: Vendor] = [:]
        for v in vendors { map["\(v.name.lowercased())|\(v.company.lowercased())"] = v }
        var result = ImportResult()

        for line in lines {
            let cols = parseCSVRow(line)
            func str(_ i: Int?) -> String? {
                guard let i, i < cols.count else { return nil }
                let s = cols[i].trimmingCharacters(in: .whitespaces); return s.isEmpty ? nil : s
            }
            guard let company = str(companyIdx) else {
                result.skipped += 1; result.skippedRows.append("(missing company)"); continue
            }
            let name = str(nameIdx) ?? company
            let key = "\(name.lowercased())|\(company.lowercased())"

            if let existing = map[key] {
                if let v = str(phoneIdx)    { existing.contactNumber = v }
                if let v = str(emailIdx)    { existing.email         = v }
                if let v = str(addrIdx)     { existing.address       = v }
                if let v = str(postcodeIdx) { existing.postcode      = v }
                if let v = str(stateIdx)    { existing.state         = v }
                if let v = str(countryIdx)  { existing.country       = v }
                if let v = str(notesIdx)    { existing.notes         = v }
                result.updated += 1
            } else {
                let v = Vendor(
                    name: name, company: company,
                    contactNumber: str(phoneIdx)    ?? "",
                    address:       str(addrIdx)     ?? "",
                    postcode:      str(postcodeIdx) ?? "",
                    state:         str(stateIdx)    ?? "",
                    country:       str(countryIdx)  ?? "",
                    email:         str(emailIdx)    ?? "",
                    notes:         str(notesIdx)    ?? ""
                )
                modelContext.insert(v)
                result.created += 1
            }
        }
        try? modelContext.save()
        importResult = result
        isProcessing = false
    }

    private func makeTemplate() -> URL? {
        let rows = [
            "name,company,contactNumber,email,address,postcode,state,country,notes",
            "Tan Ah Kow,Apple Distributor Sdn Bhd,+60341234567,sales@appledist.com,Lot 7 Jalan Industri,41000,Klang,Malaysia,Preferred supplier",
            "Siti binti Rahmat,Samsung Parts Bhd,+60321234567,procurement@samsung.com,Block C Menara Tech,50480,Kuala Lumpur,Malaysia,"
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CompQuote_Vendors_Template.csv")
        try? rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Shared UI helpers
struct ImportResultRow: View {
    let icon: String; let color: Color; let label: String; let count: Int
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(color)
            Text(label)
            Spacer()
            Text("\(count)").fontWeight(.bold).foregroundColor(color)
        }
    }
}

struct ColRow: View {
    let column: String; let required: Bool; let note: String
    init(_ column: String, req: Bool, _ note: String) {
        self.column = column; self.required = req; self.note = note
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(column)
                .font(.system(.caption, design: .monospaced)).fontWeight(.semibold)
                .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(required ? "REQUIRED" : "optional")
                    .font(.caption2).fontWeight(required ? .bold : .regular)
                    .foregroundColor(required ? .red : .secondary)
                Text(note).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
