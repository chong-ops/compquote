import SwiftUI
import SwiftData

// MARK: - Current currency symbol
// Reads the same key formatCurrency() uses. For input-field prefixes and labels.
var appCurrencySymbol: String {
    UserDefaults.standard.string(forKey: AppStorageKeys.currencySymbol) ?? "RM"
}

// MARK: - Context Save Helper
// Wraps modelContext.save() so failures are logged and can be surfaced to the
// user instead of being silently discarded by `try?`.
@discardableResult
func saveContext(_ context: ModelContext, action: String = "") -> Bool {
    do {
        try context.save()
        return true
    } catch {
        print("⚠️ SwiftData save failed\(action.isEmpty ? "" : " — \(action)"): \(error)")
        return false
    }
}

// MARK: - Shared Add/Edit Line Item Sheet
struct LineItemFormSheet: View {
    enum Mode {
        case addToTemp(binding: Binding<[TempLineItem]>, isPO: Bool = false)
        case addToQuotation(Quotation, modelContext: ModelContext)
        case addToPO(PurchaseOrder, modelContext: ModelContext)
    }

    let mode: Mode
    let products: [Product]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Search & selection
    @State private var itemSearchText = ""
    @State private var selectedProduct: Product? = nil

    // Item fields
    @State private var customItemCode = ""
    @State private var customDescription = ""
    @State private var qty = 1
    @State private var unitPriceString = ""
    @State private var costString = ""
    @State private var saveToDirectory = false
    // Which pricing scenario of the selected product this line uses (1 or 2).
    @State private var scenario = 1

    // Clone flow
    @State private var productToDuplicate: Product? = nil

    @FocusState private var focusedField: ItemField?

    enum ItemField: Hashable {
        case search, code, desc, price, cost
    }

    private var sp1: Double { Double(unitPriceString) ?? 0 }
    private var cp1: Double { Double(costString)      ?? 0 }

    // PO uses cost as the line price; Quotation uses sell price.
    private var finalSelectedPrice: Double {
        isPOMode ? (cp1 > 0 ? cp1 : sp1) : sp1
    }

    var filteredInventory: [Product] {
        let tokens = itemSearchText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return [] }
        return products.filter { p in
            guard p.isActive else { return false }
            let haystack = "\(p.itemCode) \(p.itemDescription)"
            return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

    private var canAdd: Bool { !customItemCode.isEmpty && !customDescription.isEmpty }

    /// Cost per unit saved on a quotation line for the internal margin. 0 = unknown.
    private var scenarioUnitCost: Double {
        guard !isPOMode, let p = selectedProduct else { return 0 }
        if scenario == 2, let c2 = QuotationMargin.cost2(p) { return c2 }
        return QuotationMargin.cost1(p) ?? 0
    }

    /// True when adding to a Purchase Order — changes labels from SP/margin to CP/cost
    private var isPOMode: Bool {
        switch mode {
        case .addToPO: return true
        case .addToTemp(_, let isPO): return isPO
        default: return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {

                // ── SECTION 1: Search ─────────────────────────────────────
                Section("Search Product") {
                    if let product = selectedProduct {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.itemCode).fontWeight(.semibold)
                                Text(product.itemDescription).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Change") { clearSelection() }
                                .font(.caption).foregroundColor(.blue)
                        }
                    } else {
                        TextField("Type code or description…", text: $itemSearchText)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .search)

                        if !itemSearchText.isEmpty {
                            if filteredInventory.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No matching items found.")
                                        .font(.subheadline).foregroundColor(.secondary)
                                    if !products.isEmpty {
                                        Text("Clone a similar product as a starting point:")
                                            .font(.caption).foregroundColor(.secondary)
                                        ForEach(products.prefix(5)) { p in
                                            Button {
                                                productToDuplicate = p
                                            } label: {
                                                HStack {
                                                    VStack(alignment: .leading, spacing: 2) {
                                                        Text(p.itemCode).fontWeight(.semibold)
                                                        Text(p.itemDescription).font(.caption).foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Label("Clone", systemImage: "doc.on.doc")
                                                        .font(.caption).foregroundColor(.orange)
                                                }
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            } else {
                                ForEach(filteredInventory) { p in
                                    HStack(alignment: .top) {
                                        Button { selectProduct(p) } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(p.itemCode)
                                                    .font(.subheadline).fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                                Text(p.itemDescription)
                                                    .font(.subheadline)
                                                    .foregroundColor(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        Spacer(minLength: 8)
                                        VStack(alignment: .trailing, spacing: 6) {
                                            Text(formatCurrency(p.defaultUnitPrice))
                                                .font(.footnote).foregroundColor(.blue)
                                            Button {
                                                productToDuplicate = p
                                            } label: {
                                                Image(systemName: "doc.on.doc").foregroundColor(.orange)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── SECTION 2: Item Details ───────────────────────────────
                Section("Item Details") {
                    TextField("Item Code / SKU", text: $customItemCode)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .code)
                    TextField("Description", text: $customDescription, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focusedField, equals: .desc)
                    // Same field in both modes — SP1 for quotation, also SP1 for PO (rebate reference)
                    CalcInputRow(label: "Sell Price (SP1)", symbol: appCurrencySymbol,
                                 text: $unitPriceString, field: .price, focused: $focusedField)
                    // PO mode — Cost Price drives the Line Total (qty × CP1).
                    if isPOMode {
                        CalcInputRow(label: "Cost Price (CP1)", symbol: appCurrencySymbol,
                                     text: $costString, field: .cost, focused: $focusedField)
                    }
                    HStack {
                        Text("Quantity").foregroundColor(.primary)
                        Spacer()
                        QtyField(qty: $qty)
                        Stepper("", value: $qty, in: 1...999).labelsHidden()
                    }
                    if qty > 0 && (sp1 > 0 || cp1 > 0) {
                        HStack {
                            Text("Line Total").foregroundColor(.secondary)
                            Spacer()
                            Text(formatCurrency(Double(qty) * finalSelectedPrice))
                                .fontWeight(.semibold).foregroundColor(.blue)
                        }
                    }
                }

                // ── Scenario (quotation only, when the product has a second price/cost) ──
                if !isPOMode, let p = selectedProduct, QuotationMargin.hasScenario2(p) {
                    Section {
                        Picker("Scenario", selection: $scenario) {
                            Text("Scenario 1").tag(1)
                            Text("Scenario 2").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: scenario) { _, new in
                            if new == 2, let np2 = QuotationMargin.netPrice2(p) {
                                unitPriceString = String(format: "%.2f", np2)
                            } else if new == 1, p.defaultUnitPrice > 0 {
                                unitPriceString = String(format: "%.2f", p.defaultUnitPrice)
                            }
                        }
                    } header: {
                        Text("Pricing Scenario")
                    } footer: {
                        Text("Sets the sell price and saves the matching cost on this quotation for your profit margin reference (not printed).")
                    }
                }

                // ── Save to Directory toggle — shown in all modes ─────────
                Section {
                    Toggle(isOn: $saveToDirectory) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save as New Product").fontWeight(.medium)
                            Text("Adds this item permanently to your product catalog.")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .tint(.green)
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "ti_15", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .toolbar {
                ToolbarItem(id: "ti_16", placement: .topBarTrailing) {
                    Button("Add") { commitItem() }.disabled(!canAdd)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            // sheet(item:) hands the product to the sheet itself, so it can never open blank.
            .sheet(item: $productToDuplicate) { base in
                CloneProductIntoItemSheet(baseProduct: base) { code, desc, price, cost in
                    customItemCode    = code
                    customDescription = desc
                    unitPriceString   = String(format: "%.2f", price)
                    costString        = String(format: "%.2f", cost)
                    itemSearchText    = ""
                    productToDuplicate = nil
                }
            }
        }
    }

    // MARK: - Helpers
    private func selectProduct(_ p: Product) {
        selectedProduct   = p
        customItemCode    = p.itemCode
        customDescription = p.itemDescription
        unitPriceString   = p.defaultUnitPrice > 0 ? String(format: "%.2f", p.defaultUnitPrice) : ""
        costString        = p.defaultCost      > 0 ? String(format: "%.2f", p.defaultCost)      : ""
        scenario          = 1
        itemSearchText    = ""
        focusedField      = nil
    }

    private func clearSelection() {
        selectedProduct   = nil
        scenario          = 1
        customItemCode    = ""
        customDescription = ""
        unitPriceString   = ""
        costString        = ""
        itemSearchText    = ""
    }

    private func commitItem() {
        let price = finalSelectedPrice
        switch mode {
        case .addToTemp(let binding, _):
            binding.wrappedValue.append(
                TempLineItem(itemCode: customItemCode, itemDescription: customDescription, qty: qty, unitPrice: price, unitCost: scenarioUnitCost)
            )
            if saveToDirectory { saveProductIfNew(price: price, context: modelContext) }
        case .addToQuotation(let quotation, let ctx):
            if saveToDirectory { saveProductIfNew(price: price, context: ctx) }
            let nextOrder = (quotation.items.map(\.sortOrder).max() ?? -1) + 1
            let line = LineItem(itemCode: customItemCode, itemDescription: customDescription, qty: qty, unitPrice: price, sortOrder: nextOrder)
            line.unitCost = scenarioUnitCost
            quotation.items.append(line)
        case .addToPO(let order, let ctx):
            if saveToDirectory { saveProductIfNew(price: price, context: ctx) }
            let nextOrder = (order.items.map(\.sortOrder).max() ?? -1) + 1
            order.items.append(LineItem(itemCode: customItemCode, itemDescription: customDescription, qty: qty, unitPrice: price, sortOrder: nextOrder))
        }
        dismiss()
    }

    private func saveProductIfNew(price: Double, context: ModelContext) {
        let code = customItemCode.lowercased()
        guard !products.contains(where: { $0.itemCode.lowercased() == code }) else { return }
        let p = Product(
            itemCode: customItemCode,
            itemDescription: customDescription,
            defaultUnitPrice: sp1,
            defaultCost: cp1
        )
        context.insert(p)
        try? context.save()
    }
}

// MARK: - Shared Input Row
struct CalcInputRow: View {
    let label: String
    let symbol: String
    @Binding var text: String
    let field: LineItemFormSheet.ItemField
    var focused: FocusState<LineItemFormSheet.ItemField?>.Binding

    var body: some View {
        HStack {
            Text(label).foregroundColor(.primary)
            Spacer()
            Text(symbol).foregroundColor(.secondary).font(.subheadline)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused(focused, equals: field)
                .frame(width: 90)
        }
    }
}

// MARK: - Compact Calculator Table
struct CompactCalculatorTable: View {
    @Binding var sp1: String
    @Binding var cp1: String
    @Binding var r1:  String
    @Binding var d1:  String
    @Binding var df1: String
    @Binding var sp2: String
    @Binding var cp2: String
    @Binding var r2:  String
    @Binding var d2:  String
    @Binding var df2: String
    @Binding var selectedScenario: Int?
    let isPOMode: Bool

    @FocusState private var focused: CalcField?
    enum CalcField: Hashable { case sp1,cp1,r1,d1,df1,sp2,cp2,r2,d2,df2 }

    // Which of the two discount fields the user typed last; the other one follows it.
    private enum DiscSource { case percent, amount }
    @State private var src1: DiscSource = .percent
    @State private var src2: DiscSource = .percent

    private func amountText(_ v: Double) -> String { v > 0 ? String(format: "%.2f", v) : "" }
    private func percentText(_ v: Double) -> String {
        guard v > 0 else { return "" }
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
    private func fromPercent(_ sp: Double, _ pct: Double) -> String { sp > 0 ? amountText(sp * pct / 100) : "" }
    private func fromAmount(_ sp: Double, _ amt: Double) -> String { sp > 0 ? percentText(amt / sp * 100) : "" }

    private var vSP1:  Double { Double(sp1)  ?? 0 }
    private var vCP1:  Double { Double(cp1)  ?? 0 }
    private var vR1:   Double { Double(r1)   ?? 0 }
    private var vD1:   Double { Double(d1)   ?? 0 }
    private var vDF1:  Double { Double(df1)  ?? 0 }
    private var vSP2:  Double { Double(sp2)  ?? 0 }
    private var vCP2:  Double { Double(cp2)  ?? 0 }
    private var vR2:   Double { Double(r2)   ?? 0 }
    private var vD2:   Double { Double(d2)   ?? 0 }
    private var vDF2:  Double { Double(df2)  ?? 0 }

    // Rebate always uses SP1 for both scenarios
    private var ec1:     Double { vCP1 - (vSP1 * vR1 / 100) }
    // % and RM are two views of one discount (kept in step below): the RM amount is exact when present.
    private var np1:     Double { vDF1 > 0 ? max(0, vSP1 - vDF1) : max(0, vSP1 * (1 - vD1/100)) }
    private var pf1:     Double { np1 - ec1 }
    private var mg1:     Double { np1 > 0 ? (pf1/np1)*100 : 0 }
    private var cp2Base: Double { vCP2 > 0 ? vCP2 : vCP1 }
    private var ec2:     Double { cp2Base - (vSP1 * vR2 / 100) }
    private var np2:     Double { vDF2 > 0 ? max(0, vSP2 - vDF2) : max(0, vSP2 * (1 - vD2/100)) }
    private var pf2:     Double { np2 - ec2 }
    private var mg2:     Double { np2 > 0 ? (pf2/np2)*100 : 0 }

    // Selection: PO uses effective cost, quotation uses net price
    private var sel1: Double { isPOMode ? ec1 : np1 }
    private var sel2: Double { isPOMode ? ec2 : np2 }
    private var hasData1: Bool { vSP1 > 0 || vCP1 > 0 }
    private var hasData2: Bool { vSP2 > 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                Text("Scenario 1")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.blue)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                    .background(Color.blue.opacity(0.08))
                Text("Scenario 2")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.green)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                    .background(Color.green.opacity(0.08))
            }
            Divider()

            // Input rows
            cRow("Sell Price", sym: "$") {
                cCell($sp1, .sp1); cCell($sp2, .sp2)
            }
            cRow("Cost Price", sym: "$") {
                cCell($cp1, .cp1); cCell($cp2, .cp2, placeholder: "= CP1")
            }
            cRow("Rebate % (×SP1)", sym: "%") {
                cCell($r1, .r1, suffix: true); cCell($r2, .r2, suffix: true)
            }
            cRow("Discount %", sym: "%") {
                cCell($d1, .d1, suffix: true); cCell($d2, .d2, suffix: true)
            }
            cRow("Discount \(appCurrencySymbol)", sym: appCurrencySymbol) {
                cCell($df1, .df1); cCell($df2, .df2)
            }

            // Results divider
            HStack {
                Text("Results").font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }.background(Color(.systemGray6))
            Divider()

            // Result rows
            rRow("Eff. Cost") {
                rVal(hasData1 ? formatCurrency(ec1) : "—", ec1 < 0 ? .red : .primary)
                rVal((hasData2 || vCP2 > 0) ? formatCurrency(ec2) : "—", ec2 < 0 ? .red : .primary)
            }
            rRow("Net Price") {
                rVal(hasData1 ? formatCurrency(np1) : "—", .primary)
                rVal(hasData2 ? formatCurrency(np2) : "—", .primary)
            }
            rRow("Profit") {
                rVal(hasData1 ? formatCurrency(pf1) : "—", pf1 >= 0 ? .green : .red)
                rVal(hasData2 ? formatCurrency(pf2) : "—", pf2 >= 0 ? .green : .red)
            }
            rRow("Margin") {
                rVal(hasData1 ? String(format: "%.1f%%", mg1) : "—", mg1 >= 0 ? .green : .red)
                rVal(hasData2 ? String(format: "%.1f%%", mg2) : "—", mg2 >= 0 ? .green : .red)
            }

            // Selection buttons
            if hasData1 || hasData2 {
                Divider()
                HStack(spacing: 10) {
                    selBtn(
                        label: isPOMode ? "Eff. Cost 1" : "Sell Price 1",
                        value: hasData1 ? formatCurrency(sel1) : "—",
                        isSelected: selectedScenario == 1,
                        color: .blue,
                        enabled: hasData1
                    ) { selectedScenario = 1 }

                    selBtn(
                        label: isPOMode ? "Eff. Cost 2" : "Sell Price 2",
                        value: hasData2 ? formatCurrency(sel2) : "—",
                        isSelected: selectedScenario == 2,
                        color: .green,
                        enabled: hasData2
                    ) { selectedScenario = 2 }
                }
                .padding(12)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 0.5))
        .padding(.horizontal, 4).padding(.vertical, 4)
        // Discount % and RM follow each other.
        .onChange(of: d1)  { _, v in
            if focused == .d1 { src1 = .percent; df1 = Double(v) == nil ? "" : fromPercent(vSP1, vD1) }
            else if focused != .df1, src1 == .percent { df1 = fromPercent(vSP1, vD1) }   // loaded from a product
        }
        .onChange(of: df1) { _, v in if focused == .df1 { src1 = .amount;  d1  = Double(v) == nil ? "" : fromAmount(vSP1, vDF1) } }
        .onChange(of: d2)  { _, v in
            if focused == .d2 { src2 = .percent; df2 = Double(v) == nil ? "" : fromPercent(vSP2, vD2) }
            else if focused != .df2, src2 == .percent { df2 = fromPercent(vSP2, vD2) }   // loaded from a product
        }
        .onChange(of: df2) { _, v in if focused == .df2 { src2 = .amount;  d2  = Double(v) == nil ? "" : fromAmount(vSP2, vDF2) } }
        // Changing the sell price re-works the follower from whatever the user typed last.
        .onChange(of: sp1) { _, _ in if src1 == .percent { df1 = fromPercent(vSP1, vD1) } else { d1 = fromAmount(vSP1, vDF1) } }
        .onChange(of: sp2) { _, _ in if src2 == .percent { df2 = fromPercent(vSP2, vD2) } else { d2 = fromAmount(vSP2, vDF2) } }
        // Product defaults load a % only: fill in the matching RM.
        .onAppear {
            if vDF1 == 0, vD1 > 0 { df1 = fromPercent(vSP1, vD1) }
            if vDF2 == 0, vD2 > 0 { df2 = fromPercent(vSP2, vD2) }
        }
    }

    // MARK: Builder helpers
    @ViewBuilder
    private func cRow(_ label: String, sym: String, @ViewBuilder cells: () -> some View) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 14)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 7)
            cells()
        }
        Divider()
    }

    @ViewBuilder
    private func cCell(_ val: Binding<String>, _ field: CalcField, suffix: Bool = false, placeholder: String = "0") -> some View {
        TextField(placeholder, text: val)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .focused($focused, equals: field)
            .font(.system(size: 15, weight: .medium))
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 8)
            .background(Color(.systemGray6).opacity(0.5))
            // The whole shaded cell is the tap target, not just the digits.
            .contentShape(Rectangle())
            .onTapGesture { focused = field }
    }

    @ViewBuilder
    private func rRow(_ label: String, @ViewBuilder values: () -> some View) -> some View {
        HStack(spacing: 0) {
            Text(label).font(.system(size: 14)).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 7)
            values()
        }
        Divider()
    }

    @ViewBuilder
    private func rVal(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundColor(color)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func selBtn(label: String, value: String, isSelected: Bool, color: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label).font(.system(size: 13))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                Text(value).font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? .white : color)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(isSelected ? color : color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

// MARK: - Quantity field
/// Number field that clears when tapped so a single digit can be typed straight away.
/// The value is kept between 1 and 999; an empty field reverts to the last valid quantity.
struct QtyField: View {
    @Binding var qty: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(qty), text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .frame(width: 64, height: 36)
            .background(Color(.systemGray6).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onAppear { text = String(qty) }
            .onChange(of: focused) { _, isFocused in
                if isFocused { text = "" }               // tap = ready for a new number
                else { text = String(qty) }              // blank or done = show the real value
            }
            .onChange(of: text) { _, newText in
                let digits = newText.filter(\.isNumber)
                if digits != newText { text = digits; return }
                guard let v = Int(digits) else { return }  // empty: keep the old quantity
                let clamped = min(max(v, 1), 999)
                qty = clamped
                if clamped != v { text = String(clamped) }
            }
            .onChange(of: qty) { _, newQty in
                if !focused || (Int(text) != nil && Int(text) != newQty) { text = String(newQty) }
            }
    }
}

// MARK: - Clone Product Into Item Sheet
struct CloneProductIntoItemSheet: View {
    let baseProduct: Product
    let onConfirm: (String, String, Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    @State private var itemCode = ""
    @State private var itemDescription = ""
    @State private var unitPriceString = ""
    @State private var costString = ""
    @State private var didPrefill = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Clone from: \(baseProduct.itemCode)") {
                    TextField("New Item Code", text: $itemCode)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($anyFocused)
                    HStack {
                        Text("Sell Price"); Spacer()
                        Text(appCurrencySymbol).foregroundColor(.secondary)
                        TextField("0.00", text: $unitPriceString)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($anyFocused).frame(width: 90)
                    }
                    HStack {
                        Text("Cost Price"); Spacer()
                        Text(appCurrencySymbol).foregroundColor(.secondary)
                        TextField("0.00", text: $costString)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($anyFocused).frame(width: 90)
                    }
                }
            }
            .navigationTitle("Clone Product")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didPrefill else { return }
                didPrefill = true
                itemCode        = baseProduct.itemCode + "-V2"
                itemDescription = baseProduct.itemDescription
                unitPriceString = String(format: "%.2f", baseProduct.defaultUnitPrice)
                costString      = baseProduct.defaultCost > 0 ? String(format: "%.2f", baseProduct.defaultCost) : ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "ti_17", placement: .topBarTrailing) {
                    Button("Use") {
                        onConfirm(itemCode, itemDescription,
                                  Double(unitPriceString) ?? 0,
                                  Double(costString) ?? 0)
                    }
                    .disabled(itemCode.isEmpty)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
        }
    }
}

// MARK: - Inline Edit Item Sheet (shared)
struct InlineEditItemSheet: View {
    @Bindable var item: LineItem
    var isPOMode: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var unitPriceString = ""
    @State private var showMarginCalculator = false
    @FocusState private var anyFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Identity") {
                    TextField("Item Code", text: $item.itemCode)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Description", text: $item.itemDescription, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($anyFocused)
                }
                Section("Quantity & Pricing") {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        QtyField(qty: $item.qty)
                        Stepper("", value: $item.qty, in: 1...999).labelsHidden()
                    }
                    HStack {
                        Text("Unit Price"); Spacer()
                        Text(appCurrencySymbol).foregroundColor(.secondary)
                        TextField("0.00", text: $unitPriceString)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($anyFocused).frame(width: 90)
                    }
                    HStack {
                        Text("Line Total").foregroundColor(.secondary)
                        Spacer()
                        let price = Double(unitPriceString) ?? item.unitPrice
                        Text(formatCurrency(Double(item.qty) * price))
                            .fontWeight(.semibold).foregroundColor(.blue)
                    }
                    Button {
                        showMarginCalculator = true
                    } label: {
                        Label("Margin Calculator", systemImage: "function")
                    }
                }
            }
            .navigationTitle("Edit Line Item")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { unitPriceString = String(format: "%.2f", item.unitPrice) }
            .cancelEdits(of: item,
                         extraChanges: { (Double(unitPriceString) ?? item.unitPrice) != item.unitPrice }) { i in
                ModelSnapshot([
                    FieldSnapshot(i, \.itemCode),
                    FieldSnapshot(i, \.itemDescription),
                    FieldSnapshot(i, \.qty)
                ])
            }
            .toolbar {
                ToolbarItem(id: "ti_18", placement: .topBarTrailing) {
                    Button("Done") {
                        if let price = Double(unitPriceString) { item.unitPrice = price }
                        item.recalculate()
                        dismiss()
                    }
                    .disabled(item.itemCode.isEmpty || item.itemDescription.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
            .sheet(isPresented: $showMarginCalculator) {
                LineItemMarginCalculatorSheet(
                    itemCode: item.itemCode,
                    itemDescription: item.itemDescription,
                    currentUnitPrice: Double(unitPriceString) ?? item.unitPrice,
                    isPOMode: isPOMode
                ) { chosenPrice in
                    unitPriceString = String(format: "%.2f", chosenPrice)
                }
            }
        }
    }
}

// MARK: - Line Item Margin Calculator Sheet
// Presents the same Pricing Calculator layout used on the Product edit page,
// pre-filled from the matching Product in the directory when found.
struct LineItemMarginCalculatorSheet: View {
    let itemCode: String
    let itemDescription: String
    let currentUnitPrice: Double
    let isPOMode: Bool
    let onUsePrice: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.itemCode) private var products: [Product]
    @State private var calc = ProductMarginCalc()
    @State private var selectedScenario: Int? = nil
    @State private var didLoad = false
    @State private var productToEdit: Product?

    private var matchedProduct: Product? {
        let code = itemCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty else { return nil }
        return products.first { $0.itemCode.lowercased() == code }
    }

    // PO mode selects Eff. Cost; Quotation mode selects Net Sell Price.
    private var selectedPrice: Double? {
        switch selectedScenario {
        case 1: return isPOMode ? max(0, calc.cp1Net) : calc.netSP1
        case 2: return isPOMode ? max(0, calc.cp2Net) : calc.netSP2
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(itemCode.isEmpty ? "—" : itemCode)
                            .font(.headline)
                        if !itemDescription.isEmpty {
                            Text(itemDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if let product = matchedProduct {
                        Button {
                            productToEdit = product
                        } label: {
                            Label("Open Product Page", systemImage: "arrow.up.right.square")
                        }
                    }
                }

                Section {
                    CompactCalculatorTable(
                        sp1: $calc.sp1String,
                        cp1: $calc.cp1String,
                        r1:  $calc.rebate1String,
                        d1:  $calc.disc1String,
                        df1: $calc.df1String,
                        sp2: $calc.sp2String,
                        cp2: $calc.cp2String,
                        r2:  $calc.rebate2String,
                        d2:  $calc.disc2String,
                        df2: $calc.df2String,
                        selectedScenario: $selectedScenario,
                        isPOMode: isPOMode
                    )
                    .listRowInsets(.init())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Pricing Calculator")
                } footer: {
                    if matchedProduct != nil {
                        Text("Values loaded from product defaults. Rebate always calculated from SP1.")
                            .font(.caption)
                    } else {
                        Text("No matching product found in directory. Rebate always calculated from SP1.")
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Margin Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use") {
                        if let price = selectedPrice { onUsePrice(price) }
                        dismiss()
                    }
                    .disabled(selectedPrice == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                if let p = matchedProduct {
                    calc.load(from: p)
                } else if currentUnitPrice > 0 {
                    calc.sp1String = String(format: "%.2f", currentUnitPrice)
                }
                didLoad = true
            }
            .sheet(item: $productToEdit, onDismiss: {
                // Refresh calculator with any newly-saved product defaults.
                if let p = matchedProduct { calc.load(from: p) }
            }) { product in
                MasterEditProductSheet(product: product)
            }
        }
    }
}

// MARK: - Sticky Grand Total Bar
struct GrandTotalBar: View {
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"
    let total: Double
    var label: String = "Grand Total"
    var accentColor: Color = .blue

    var body: some View {
        HStack {
            Text(label).font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
            Spacer()
            Text(formatCurrency(total))
                .font(.title3).fontWeight(.bold).foregroundColor(accentColor)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Delete Confirmation Modifier
extension View {
    func deleteConfirmation(
        isPresented: Binding<Bool>,
        itemName: String,
        onDelete: @escaping () -> Void
    ) -> some View {
        self.confirmationDialog(
            "Delete \"\(itemName)\"?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This action cannot be undone.") }
    }
}

// MARK: - PDF Generation Service
struct PDFGenerator {
    @MainActor
    static func generate<V: View>(view: V, filename: String) -> URL? {
        let pageWidth:  CGFloat = 595
        let pageHeight: CGFloat = 842
        let renderer = ImageRenderer(content:
            view.frame(width: pageWidth, alignment: .top)
                .background(Color.white)
                .environment(\.colorScheme, .light)  // always render in light mode
        )
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        let tempDir  = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let outputURL = tempDir.appendingPathComponent("\(filename).pdf")
        renderer.render { size, context in
            let renderHeight = max(size.height, pageHeight)
            var box = CGRect(x: 0, y: 0, width: pageWidth, height: renderHeight)
            guard let pdf = CGContext(outputURL as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            pdf.translateBy(x: 0, y: renderHeight - size.height)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return outputURL
    }
}

// MARK: - On-Demand PDF Sharing
// Wraps a URL so it can drive .sheet(item:) presentation.
struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

// UIActivityViewController wrapper — presents the system share sheet
// for a PDF (or any file) generated on demand.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - PDF Viewer (PDFKit-backed) for accurate previews
import PDFKit
struct PDFViewer: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        view.backgroundColor = .systemGroupedBackground
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}


// MARK: - Preset tax rates
struct TaxPreset: Identifiable {
    let id = UUID()
    let label: String
    let rate: Double
}

let taxPresets: [TaxPreset] = [
    TaxPreset(label: "None",    rate: 0),
    TaxPreset(label: "SST 8%",  rate: 8),
    TaxPreset(label: "SST 6%",  rate: 6),
    TaxPreset(label: "GST 9%",  rate: 9),
    TaxPreset(label: "GST 10%", rate: 10),
    TaxPreset(label: "VAT 20%", rate: 20),
    TaxPreset(label: "Custom",  rate: -1),  // triggers manual entry
]

// MARK: - Shared Discount & Tax Section
struct DiscountTaxSection: View {
    // Discount bindings
    @Binding var discountPct:   Double
    @Binding var discountFixed: Double
    // Tax bindings
    @Binding var taxPct:   Double
    @Binding var taxLabel: String
    // Computed values passed in
    let itemsSubtotal:  Double
    let discountAmount: Double
    let taxAmount:      Double
    let grandTotal:     Double

    @State private var showCustomTax = false
    @State private var customTaxString = ""
    @FocusState private var anyFocused: Bool

    // Which preset is currently selected
    private var selectedPreset: TaxPreset? {
        if taxPct == 0 { return taxPresets.first { $0.rate == 0 } }
        return taxPresets.first { $0.rate == taxPct && $0.rate != -1 }
    }

    var body: some View {
        Section {
            // ── Discount row ──────────────────────────────────────────────
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Label("Discount", systemImage: "tag")
                        .font(.subheadline).foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // % input
                    HStack(spacing: 4) {
                        TextField("0", text: Binding(
                            get: { discountPct > 0 ? String(format: "%.2f", discountPct) : "" },
                            set: { discountPct = Double($0) ?? 0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 55)
                        .focused($anyFocused)
                        Text("%")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.trailing, 8)

                    // Fixed $ input
                    HStack(spacing: 4) {
                        Text(appCurrencySymbol).font(.subheadline).foregroundColor(.secondary)
                        TextField("0.00", text: Binding(
                            get: { discountFixed > 0 ? String(format: "%.2f", discountFixed) : "" },
                            set: { discountFixed = Double($0) ?? 0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 65)
                        .focused($anyFocused)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.vertical, 4)

                if discountAmount > 0 {
                    HStack {
                        Text("Discount applied")
                            .font(.caption2).foregroundColor(.orange)
                        Spacer()
                        Text("-" + formatCurrency(discountAmount))
                            .font(.caption2).fontWeight(.bold).foregroundColor(.orange)
                    }
                    .padding(.bottom, 4)
                }
            }

            // ── Tax row ───────────────────────────────────────────────────
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Label("Tax", systemImage: "percent")
                        .font(.subheadline).foregroundColor(.primary)

                    Spacer()

                    // Dropdown picker
                    Menu {
                        ForEach(taxPresets) { preset in
                            Button {
                                if preset.rate == -1 {
                                    showCustomTax = true
                                    customTaxString = taxPct > 0 ? String(format: "%.2f", taxPct) : ""
                                } else {
                                    taxPct = preset.rate
                                    taxLabel = preset.rate == 0 ? "Tax" : preset.label
                                    showCustomTax = false
                                }
                            } label: {
                                HStack {
                                    Text(preset.label)
                                    if preset.rate == taxPct && preset.rate != -1 {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(taxPct == 0 ? "None" : (selectedPreset?.label ?? "Custom \(String(format: "%.1f", taxPct))%"))
                                .font(.subheadline)
                                .foregroundColor(taxPct > 0 ? .primary : .secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)

                // Custom % input (shown when Custom selected)
                if showCustomTax || (taxPct > 0 && selectedPreset == nil) {
                    HStack(spacing: 8) {
                        TextField("Label (e.g. VAT)", text: $taxLabel)
                            .font(.caption).foregroundColor(.secondary)
                            .focused($anyFocused)
                        Spacer()
                        TextField("0.00", text: Binding(
                            get: { taxPct > 0 ? String(format: "%.2f", taxPct) : "" },
                            set: { taxPct = Double($0) ?? 0 }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        .focused($anyFocused)
                        Text("%").foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }

                if taxAmount > 0 {
                    HStack {
                        Text(taxLabel.isEmpty ? "Tax" : taxLabel)
                            .font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Text("+" + formatCurrency(taxAmount))
                            .font(.caption2).fontWeight(.bold).foregroundColor(.secondary)
                    }
                    .padding(.bottom, 4)
                }
            }
        } header: {
            Text("Discount & Tax")
        } footer: {
            if discountAmount > 0 || taxAmount > 0 {
                Text("Subtotal \(formatCurrency(itemsSubtotal)) → After discount \(formatCurrency(itemsSubtotal - discountAmount)) → Total \(formatCurrency(grandTotal))")
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Totals Summary Bar (subtotal + discount + tax + grand total)
struct TotalsSummaryBar: View {
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"
    let itemsSubtotal:  Double
    let discountAmount: Double
    let taxAmount:      Double
    let taxLabel:       String
    let grandTotal:     Double
    var accentColor: Color = .blue

    var body: some View {
        VStack(spacing: 0) {
            if discountAmount > 0 || taxAmount > 0 {
                VStack(spacing: 6) {
                    TotalsRow(label: "Subtotal",
                              value: formatCurrency(itemsSubtotal),
                              color: .secondary)
                    if discountAmount > 0 {
                        TotalsRow(label: "Discount",
                                  value: "-" + formatCurrency(discountAmount),
                                  color: .orange)
                    }
                    if taxAmount > 0 {
                        TotalsRow(label: taxLabel.isEmpty ? "Tax" : taxLabel,
                                  value: "+" + formatCurrency(taxAmount),
                                  color: .secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)

                Divider()
            }
            GrandTotalBar(total: grandTotal, accentColor: accentColor)
        }
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
    }
}

private struct TotalsRow: View {
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"
    let label: String
    let value: String
    let color: Color
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(color)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium).foregroundColor(color)
        }
    }
}


// MARK: - iPad adaptive layout
// iPhone is unchanged; these only act on iPad / regular-width windows.

/// Bumps the user's Dynamic Type setting up one step on iPad, so text is a
/// little larger on the bigger screen while still following their setting.
private struct PadTextScale: ViewModifier {
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.transformEnvironment(\.dynamicTypeSize) { size in
                let all = Array(DynamicTypeSize.allCases)
                if let i = all.firstIndex(of: size), i + 1 < all.count {
                    size = all[i + 1]
                }
            }
        } else {
            content
        }
    }
}

/// Keeps screen content to a comfortable width, centered, on wide windows.
private struct ReadableWidth: ViewModifier {
    @Environment(\.horizontalSizeClass) private var hSize
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if hSize == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
        } else {
            content
        }
    }
}

extension View {
    func iPadTextScale() -> some View { modifier(PadTextScale()) }
    func readableWidth(_ maxWidth: CGFloat = 900) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth))
    }
}


// MARK: - Cancel for live-edit sheets
// Edit sheets bind straight to a SwiftData object, so a Cancel button has to
// put the old values back. Snapshot the fields on open; restore on discard.

struct FieldSnapshot<M: AnyObject> {
    let restore: (M) -> Void
    let isChanged: (M) -> Bool

    init<V: Equatable>(_ model: M, _ keyPath: ReferenceWritableKeyPath<M, V>) {
        let original = model[keyPath: keyPath]
        restore = { $0[keyPath: keyPath] = original }
        isChanged = { $0[keyPath: keyPath] != original }
    }
}

struct ModelSnapshot<M: AnyObject> {
    let fields: [FieldSnapshot<M>]
    init(_ fields: [FieldSnapshot<M>]) { self.fields = fields }
    func hasChanges(_ model: M) -> Bool { fields.contains { $0.isChanged(model) } }
    func restore(_ model: M) { fields.forEach { $0.restore(model) } }
}

private struct CancelEditsModifier<M: AnyObject>: ViewModifier {
    let model: M
    let makeSnapshot: (M) -> ModelSnapshot<M>
    let extraChanges: () -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var snapshot: ModelSnapshot<M>?
    @State private var showConfirm = false

    func body(content: Content) -> some View {
        content
            .onAppear { if snapshot == nil { snapshot = makeSnapshot(model) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        let changed = (snapshot?.hasChanges(model) ?? false) || extraChanges()
                        if changed { showConfirm = true } else { dismiss() }
                    }
                }
            }
            .confirmationDialog("Discard your changes?",
                                isPresented: $showConfirm,
                                titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    snapshot?.restore(model)
                    try? modelContext.save()
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) { }
            }
    }
}

extension View {
    /// Adds a Cancel button that restores `model` to how it was when the sheet
    /// opened. `extraChanges` lets a sheet report edits held outside the model.
    func cancelEdits<M: AnyObject>(
        of model: M,
        extraChanges: @escaping () -> Bool = { false },
        snapshot: @escaping (M) -> ModelSnapshot<M>
    ) -> some View {
        modifier(CancelEditsModifier(model: model, makeSnapshot: snapshot, extraChanges: extraChanges))
    }
}


// MARK: - Line item snapshot (shared by quotation + PO Cancel)
struct ItemSnapshot: Equatable {
    let id: PersistentIdentifier
    var itemCode: String
    var itemDescription: String
    var qty: Int
    var unitPrice: Double
    var subTotal: Double
    var sortOrder: Int
    var linkedPONumber: String
    var linkedPOId: String
    var isDelivered: Bool
    var invoiceId: String
    var unitCost: Double
    var deliveryReference: String

    init(_ i: LineItem) {
        id = i.persistentModelID
        itemCode = i.itemCode
        itemDescription = i.itemDescription
        qty = i.qty
        unitPrice = i.unitPrice
        subTotal = i.subTotal
        sortOrder = i.sortOrder
        linkedPONumber = i.linkedPONumber
        linkedPOId = i.linkedPOId
        isDelivered = i.isDelivered
        invoiceId = i.invoiceId
        unitCost = i.unitCost
        deliveryReference = i.deliveryReference
    }

    func apply(to i: LineItem) {
        i.itemCode = itemCode
        i.itemDescription = itemDescription
        i.qty = qty
        i.unitPrice = unitPrice
        i.subTotal = subTotal
        i.sortOrder = sortOrder
        i.linkedPONumber = linkedPONumber
        i.linkedPOId = linkedPOId
        i.isDelivered = isDelivered
        i.invoiceId = invoiceId
        i.unitCost = unitCost
        i.deliveryReference = deliveryReference
    }
}


// MARK: - Shared editable line item row (quotation + purchase order)
// iPad: two lines, Qty pill beside the total, small "@ unit price" when qty > 1.
// iPhone: details on the left; total and trash share one right edge.

struct LineItemEditRow: View {
    let item: LineItem
    let index: Int
    var accent: Color = .blue
    /// iPhone only: show the numbered badge (the PO list keeps its plain look).
    var showIndexOnPhone: Bool = true
    let onDelete: () -> Void

    @Environment(\.horizontalSizeClass) private var hSize
    @State private var confirmDelete = false

    var body: some View {
        rowContent
            .confirmationDialog(
                "Delete \"\(item.itemCode)\"?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This line item will be removed.") }
    }

    @ViewBuilder
    private var rowContent: some View {
        if hSize == .regular {
            HStack(alignment: .center, spacing: 12) {
                numberBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.itemCode)
                        .font(.headline)
                    Text(item.itemDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text("Qty \(item.qty)")
                    .font(.footnote).foregroundColor(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.4), lineWidth: 0.5)
                    )
                    .fixedSize()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(item.subTotal))
                        .font(.headline).foregroundColor(accent)
                        .monospacedDigit()
                    if item.qty > 1 {
                        Text("@ \(formatCurrency(item.unitPrice))")
                            .font(.caption).foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(minWidth: 100, alignment: .trailing)
                deleteButton
            }
        } else {
            // iPhone: code + total on top, description across the full width,
            // then Qty × price and trash. Total and trash share the same right edge.
            HStack(alignment: .top, spacing: 10) {
                if showIndexOnPhone { numberBadge }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.itemCode)
                            .font(.headline)
                        Spacer()
                        Text(formatCurrency(item.subTotal))
                            .font(.headline).foregroundColor(accent)
                    }
                    Text(item.itemDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Qty \(item.qty) × \(formatCurrency(item.unitPrice))")
                            .font(.footnote).foregroundColor(.secondary)
                        Spacer()
                        deleteButton
                    }
                }
            }
        }
    }

    private var numberBadge: some View {
        ZStack {
            Circle().fill(accent.opacity(0.15)).frame(width: 26, height: 26)
            Text("\(index + 1)")
                .font(.caption).fontWeight(.bold).foregroundColor(accent)
        }
    }

    private var deleteButton: some View {
        Button { confirmDelete = true } label: {
            Image(systemName: "trash")
                .foregroundColor(.red)
                .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Delete item")
    }
}


// MARK: - Delete button inside an edit screen
/// A red "Delete …" row for the bottom of an edit Form. Asks to confirm, then runs `onDelete`.
struct DeleteRecordSection: View {
    let title: String
    let itemName: String
    let onDelete: () -> Void
    @State private var confirm = false

    var body: some View {
        Section {
            Button(role: .destructive) { confirm = true } label: {
                HStack {
                    Spacer()
                    Label(title, systemImage: "trash")
                    Spacer()
                }
            }
            .confirmationDialog("Delete \"\(itemName)\"?",
                                isPresented: $confirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This action cannot be undone.") }
        }
    }
}

extension ModelContext {
    /// Deletes a record after its edit sheet has closed. Deleting while the sheet is
    /// still on screen can make it read a record that no longer exists.
    func deleteAfterSheetCloses<T: PersistentModel>(_ model: T) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.delete(model)
            try? self.save()
        }
    }
}

// MARK: - Ask for a per-device number prefix before the first document
enum NumberPrefixKind {
    case quotation, purchaseOrder, report, invoice

    var key: String {
        switch self {
        case .quotation:     return AppStorageKeys.quotationNumberPrefix
        case .purchaseOrder: return AppStorageKeys.poNumberPrefix
        case .report:        return AppStorageKeys.reportNumberPrefix
        case .invoice:       return AppStorageKeys.invoiceNumberPrefix
        }
    }
    var askedKey: String { key + "Asked" }
    var article: String { self == .invoice ? "an" : "a" }
    var example: String {
        switch self {
        case .quotation:     return "e.g. QA"
        case .purchaseOrder: return "e.g. PA"
        case .report:        return "e.g. SA"
        case .invoice:       return "e.g. IA"
        }
    }
    var noun: String {
        switch self {
        case .quotation:     return "quotation"
        case .purchaseOrder: return "purchase order"
        case .report:        return "service report"
        case .invoice:       return "invoice"
        }
    }
}

struct PrefixPromptModifier: ViewModifier {
    let kind: NumberPrefixKind
    let onApplied: () -> Void
    @State private var show = false
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .onAppear {
                let ud = UserDefaults.standard
                let current = (ud.string(forKey: kind.key) ?? "").trimmingCharacters(in: .whitespaces)
                if current.isEmpty && !ud.bool(forKey: kind.askedKey) { show = true }
            }
            .alert("Set \(kind.article) \(kind.noun) number prefix?", isPresented: $show) {
                TextField(kind.example, text: $draft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Save Prefix") {
                    let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }   // empty: ask again next time
                    UserDefaults.standard.set(value, forKey: kind.key)
                    UserDefaults.standard.set(true, forKey: kind.askedKey)
                    onApplied()
                }
                Button("No Prefix") {
                    UserDefaults.standard.set(true, forKey: kind.askedKey)
                }
            } message: {
                Text("If you will create documents on more than one device (iPhone, iPad, Mac), give each device its own prefix, for example QA on the iPhone and QB on the iPad. That way two devices can never use the same number. You can change it later in Settings, Documents.")
            }
    }
}

extension View {
    func prefixPrompt(_ kind: NumberPrefixKind, onApplied: @escaping () -> Void) -> some View {
        modifier(PrefixPromptModifier(kind: kind, onApplied: onApplied))
    }
}
