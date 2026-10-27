import SwiftUI

// MARK: - Margin Calculator Data Model (shared between tab and sheet)
struct MarginCalculatorState {
    var cp1String    = ""   // Actual cost
    var sp1String    = ""   // Selling price 1
    var rebateString = ""   // Rebate % (applied to SP1 to derive CP2)
    var disc1String  = ""   // Discount % for Profit 1
    var sp2String    = ""   // Selling price 2
    var disc2String  = ""   // Discount % for Profit 2 (separate)

    // Parsed doubles
    var cp1:    Double { Double(cp1String)    ?? 0 }
    var sp1:    Double { Double(sp1String)    ?? 0 }
    var rebate: Double { Double(rebateString) ?? 0 }
    var disc1:  Double { Double(disc1String)  ?? 0 }
    var sp2:    Double { Double(sp2String)    ?? 0 }
    var disc2:  Double { Double(disc2String)  ?? 0 }

    // CP2 = CP1 − (SP1 × rebate%)
    var cp2: Double { cp1 - (sp1 * rebate / 100) }

    // Profit 1 = SP1 × (1 − disc1%) − CP1
    var netSP1:   Double { sp1 * (1 - disc1 / 100) }
    var profit1:  Double { netSP1 - cp1 }
    var margin1:  Double { sp1 > 0 ? (profit1 / netSP1) * 100 : 0 }

    // Profit 2 = SP2 × (1 − disc2%) − CP2
    var netSP2:   Double { sp2 * (1 - disc2 / 100) }
    var profit2:  Double { netSP2 - cp2 }
    var margin2:  Double { sp2 > 0 ? (profit2 / netSP2) * 100 : 0 }

    var hasEnoughData: Bool { cp1 > 0 && (sp1 > 0 || sp2 > 0) }
}

// MARK: - Standalone Tab View
struct MarginCalculatorTab: View {
    @State private var calc = MarginCalculatorState()

    var body: some View {
        NavigationStack {
            MarginCalculatorForm(calc: $calc, onUsePrice: nil)
                .navigationTitle("Margin Calculator")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - Sheet version (launched from Add Item, returns chosen price)
struct MarginCalculatorSheet: View {
    @Binding var calc: MarginCalculatorState
    let onUsePrice: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MarginCalculatorForm(calc: $calc, onUsePrice: onUsePrice)
                .navigationTitle("Margin Calculator")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(id: "ti_4", placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Core Calculator Form (shared UI)
struct MarginCalculatorForm: View {
    @Binding var calc: MarginCalculatorState
    /// nil = standalone tab (no "Use this price" action)
    let onUsePrice: ((Double) -> Void)?

    @FocusState private var focusedField: CalcField?
    @Environment(\.dismiss) private var dismiss

    enum CalcField: Hashable {
        case cp1, sp1, rebate, disc1, sp2, disc2
    }

    var body: some View {
        Form {

            // ── Section 1: Cost & First Selling Price ────────────────────
            Section {
                PriceRow(label: "Actual Cost (CP1)", symbol: "$",
                         text: $calc.cp1String, field: .cp1, focused: $focusedField)
                PriceRow(label: "Selling Price 1 (SP1)", symbol: "$",
                         text: $calc.sp1String, field: .sp1, focused: $focusedField)
                PriceRow(label: "Rebate %", symbol: "%",
                         text: $calc.rebateString, field: .rebate, focused: $focusedField)
            } header: {
                Text("Cost Inputs")
            } footer: {
                if calc.cp1 > 0 && calc.sp1 > 0 {
                    Text("CP2 = $\(String(format: "%.2f", calc.cp1)) − ($\(String(format: "%.2f", calc.sp1)) × \(String(format: "%.1f", calc.rebate))%) = \(formatCurrency(calc.cp2))")
                }
            }

            // ── Section 2: Profit 1 ──────────────────────────────────────
            Section("Scenario 1  —  SP1 with Discount") {
                PriceRow(label: "Discount %", symbol: "%",
                         text: $calc.disc1String, field: .disc1, focused: $focusedField)

                if calc.sp1 > 0 {
                    ResultRow(
                        label: "Net SP1 after discount",
                        value: calc.netSP1,
                        isPrice: true,
                        color: .primary
                    )
                    ResultRow(
                        label: "Profit 1",
                        value: calc.profit1,
                        isPrice: true,
                        color: calc.profit1 >= 0 ? .green : .red
                    )
                    ResultRow(
                        label: "Margin 1",
                        value: calc.margin1,
                        isPrice: false,
                        color: calc.margin1 >= 0 ? .green : .red
                    )

                    if let onUse = onUsePrice {
                        Button {
                            onUse(calc.sp1)
                            dismiss()
                        } label: {
                            Label("Use SP1 ($\(String(format: "%.2f", calc.sp1))) as Unit Price",
                                  systemImage: "checkmark.circle.fill")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        .tint(.blue)
                    }
                }
            }

            // ── Section 3: Profit 2 ──────────────────────────────────────
            Section("Scenario 2  —  SP2 with Separate Discount") {
                PriceRow(label: "Selling Price 2 (SP2)", symbol: "$",
                         text: $calc.sp2String, field: .sp2, focused: $focusedField)
                PriceRow(label: "Discount 2 %", symbol: "%",
                         text: $calc.disc2String, field: .disc2, focused: $focusedField)

                if calc.sp2 > 0 {
                    ResultRow(
                        label: "Net SP2 after discount",
                        value: calc.netSP2,
                        isPrice: true,
                        color: .primary
                    )
                    ResultRow(
                        label: "Profit 2",
                        value: calc.profit2,
                        isPrice: true,
                        color: calc.profit2 >= 0 ? .green : .red
                    )
                    ResultRow(
                        label: "Margin 2",
                        value: calc.margin2,
                        isPrice: false,
                        color: calc.margin2 >= 0 ? .green : .red
                    )

                    if let onUse = onUsePrice {
                        Button {
                            onUse(calc.sp2)
                            dismiss()
                        } label: {
                            Label("Use SP2 ($\(String(format: "%.2f", calc.sp2))) as Unit Price",
                                  systemImage: "checkmark.circle.fill")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        .tint(.green)
                    }
                }
            }

            // ── Section 4: Summary card (shown when both scenarios ready) ─
            if calc.sp1 > 0 && calc.sp2 > 0 && calc.cp1 > 0 {
                Section("Side-by-Side Summary") {
                    ComparisonCard(calc: calc)
                        .listRowInsets(.init())
                        .listRowBackground(Color.clear)
                }
            }

            // ── Reset ────────────────────────────────────────────────────
            Section {
                Button(role: .destructive) {
                    calc = MarginCalculatorState()
                    focusedField = nil
                } label: {
                    Label("Reset All Fields", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }
}

// MARK: - Price Input Row
private struct PriceRow: View {
    let label: String
    let symbol: String
    @Binding var text: String
    let field: MarginCalculatorForm.CalcField
    var focused: FocusState<MarginCalculatorForm.CalcField?>.Binding

    var body: some View {
        HStack {
            Text(label).foregroundColor(.primary)
            Spacer()
            Text(symbol).foregroundColor(.secondary).font(.subheadline)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused(focused, equals: field)
                .frame(minWidth: 110, maxWidth: 160, minHeight: 44)
        }
        // Tapping anywhere on the row (label, gap or field) starts editing.
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = field }
    }
}

// MARK: - Result Display Row
private struct ResultRow: View {
    let label: String
    let value: Double
    let isPrice: Bool
    let color: Color

    var formatted: String {
        isPrice
            ? formatCurrency(value)
            : String(format: "%.1f%%", value)
    }

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(formatted)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Side-by-Side Comparison Card
private struct ComparisonCard: View {
    let calc: MarginCalculatorState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("Scenario 1").frame(width: 110, alignment: .center)
                    .font(.caption).fontWeight(.bold).foregroundColor(.blue)
                Text("Scenario 2").frame(width: 110, alignment: .center)
                    .font(.caption).fontWeight(.bold).foregroundColor(.green)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.systemGray6))

            Divider()
            ComparisonRow(label: "Sell Price",
                          v1: "$\(String(format: "%.2f", calc.sp1))",
                          v2: "$\(String(format: "%.2f", calc.sp2))")
            ComparisonRow(label: "Cost",
                          v1: "$\(String(format: "%.2f", calc.cp1))",
                          v2: "$\(String(format: "%.2f", calc.cp2))")
            ComparisonRow(label: "Net (after disc.)",
                          v1: "$\(String(format: "%.2f", calc.netSP1))",
                          v2: "$\(String(format: "%.2f", calc.netSP2))")
            ComparisonRow(label: "Profit $",
                          v1: "$\(String(format: "%.2f", calc.profit1))",
                          v2: "$\(String(format: "%.2f", calc.profit2))",
                          c1: calc.profit1 >= 0 ? .green : .red,
                          c2: calc.profit2 >= 0 ? .green : .red)
            ComparisonRow(label: "Margin %",
                          v1: String(format: "%.1f%%", calc.margin1),
                          v2: String(format: "%.1f%%", calc.margin2),
                          c1: calc.margin1 >= 0 ? .green : .red,
                          c2: calc.margin2 >= 0 ? .green : .red)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.systemGray4), lineWidth: 0.5))
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

private struct ComparisonRow: View {
    let label: String
    let v1: String
    let v2: String
    var c1: Color = .primary
    var c2: Color = .primary

    var body: some View {
        HStack(spacing: 0) {
            Text(label).font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(v1).font(.caption).fontWeight(.semibold).foregroundColor(c1)
                .frame(width: 110, alignment: .center)
            Text(v2).font(.caption).fontWeight(.semibold).foregroundColor(c2)
                .frame(width: 110, alignment: .center)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        Divider()
    }
}
