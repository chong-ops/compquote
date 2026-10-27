import SwiftUI

// MARK: - Currency Config
// Single source of truth for currency symbol used across the entire app.
// All formatting goes through formatCurrency() — never hardcode "$" directly.

struct CurrencyConfig {
    static let presets: [(name: String, symbol: String, code: String)] = [
        ("Malaysian Ringgit", "RM",  "MYR"),
        ("US Dollar",         "$",   "USD"),
        ("Singapore Dollar",  "S$",  "SGD"),
        ("Australian Dollar", "A$",  "AUD"),
        ("British Pound",     "£",   "GBP"),
        ("Euro",              "€",   "EUR"),
        ("Japanese Yen",      "¥",   "JPY"),
        ("Chinese Yuan",      "¥",   "CNY"),
        ("Hong Kong Dollar",  "HK$", "HKD"),
        ("Thai Baht",         "฿",   "THB"),
        ("Indonesian Rupiah", "Rp",  "IDR"),
        ("Philippine Peso",   "₱",   "PHP"),
    ]
}

// MARK: - Cached formatters
// NumberFormatter construction is expensive, and these run for every row on
// every render. The currency symbol is appended separately, so the formatters
// never need invalidating when the currency setting changes.
private let cachedCurrencyFormatter: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.minimumFractionDigits = 2
    nf.maximumFractionDigits = 2
    nf.groupingSeparator = ","
    nf.decimalSeparator = "."
    return nf
}()

private let cachedCurrencyFormatterShort: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.minimumFractionDigits = 0
    nf.maximumFractionDigits = 0
    nf.groupingSeparator = ","
    return nf
}()

// MARK: - Global formatter
// Call formatCurrency(1234.50) anywhere to get "RM1,234.50" etc.
func formatCurrency(_ amount: Double) -> String {
    let symbol = UserDefaults.standard.string(forKey: AppStorageKeys.currencySymbol) ?? "RM"
    let formatted = cachedCurrencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
    return "\(symbol)\(formatted)"
}

// Short version without decimals for tight spaces
func formatCurrencyShort(_ amount: Double) -> String {
    let symbol = UserDefaults.standard.string(forKey: AppStorageKeys.currencySymbol) ?? "RM"
    let formatted = cachedCurrencyFormatterShort.string(from: NSNumber(value: amount)) ?? String(format: "%.0f", amount)
    return "\(symbol)\(formatted)"
}

// MARK: - Currency Picker View (used in Settings)
struct CurrencyPickerSection: View {
    @AppStorage(AppStorageKeys.currencySymbol) private var symbol = "RM"
    @AppStorage(AppStorageKeys.currencyCode)   private var code   = "MYR"
    @State private var showCustom = false
    @State private var customSymbol = ""

    var selectedName: String {
        CurrencyConfig.presets.first { $0.symbol == symbol }?.name ?? "Custom (\(symbol))"
    }

    var body: some View {
        Section {
            Menu {
                ForEach(CurrencyConfig.presets, id: \.code) { preset in
                    Button {
                        symbol = preset.symbol
                        code   = preset.code
                        showCustom = false
                    } label: {
                        HStack {
                            Text("\(preset.symbol)  \(preset.name)")
                            if symbol == preset.symbol {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Custom Symbol…") { showCustom = true }
            } label: {
                HStack {
                    Text("Currency").foregroundColor(.primary)
                    Spacer()
                    Text("\(symbol) — \(selectedName)")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }

            // Live preview
            HStack {
                Text("Preview").foregroundColor(.secondary).font(.caption)
                Spacer()
                Text(formatCurrency(1234.50))
                    .font(.caption).foregroundColor(.blue)
            }
        } header: {
            SettingsSectionHeader(icon: "dollarsign.circle", title: "Currency")
        } footer: {
            Text("Applied to all documents, PDFs and the margin calculator.")
        }
        .alert("Custom Currency Symbol", isPresented: $showCustom) {
            TextField("e.g. RM, $, £", text: $customSymbol)
                .autocorrectionDisabled()
            Button("Set") {
                let s = customSymbol.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { symbol = s; code = "CUSTOM" }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the symbol to show before amounts.")
        }
    }
}
