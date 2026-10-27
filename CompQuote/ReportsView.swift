import SwiftUI
import SwiftData
import Charts

// MARK: - Period filter
nonisolated enum ReportPeriod: String, CaseIterable, Identifiable {
    case month = "This month"
    case quarter = "3 months"
    case year = "This year"
    case all = "All"

    var id: String { rawValue }

    /// First day included, or nil for everything.
    func start(from now: Date = Date()) -> Date? {
        let cal = Calendar.current
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        switch self {
        case .month:   return monthStart
        case .quarter: return cal.date(byAdding: .month, value: -2, to: monthStart)
        case .year:    return cal.dateInterval(of: .year, for: now)?.start
        case .all:     return nil
        }
    }
}

// One bar in the monthly chart.
private struct ReportBar: Identifiable {
    let label: String
    let kind: String
    let amount: Double
    var id: String { label + "|" + kind }
}

private struct ReportCustomer: Identifiable {
    let name: String
    let total: Double
    var id: String { name }
}

// MARK: - Reports
// Money reports built from invoices. Billed = invoice totals, Received = payments on
// those invoices, Outstanding = what is still owed. Overdue always shows today's picture.
struct ReportsView: View {
    @Query(sort: \Invoice.date, order: .reverse) private var invoices: [Invoice]
    @AppStorage(AppStorageKeys.currencySymbol) private var currencySymbol = "RM"
    @State private var period: ReportPeriod = .quarter

    // MARK: Data
    private var periodInvoices: [Invoice] {
        guard let start = period.start() else { return invoices }
        return invoices.filter { $0.date >= start }
    }

    private var billed: Double { periodInvoices.reduce(0) { $0 + $1.grandTotal } }
    private var received: Double { periodInvoices.reduce(0) { $0 + $1.paidAmount } }
    private var outstanding: Double { periodInvoices.reduce(0) { $0 + $1.balanceDue } }
    private var outstandingCount: Int { periodInvoices.filter { $0.balanceDue > 0.005 }.count }

    private var overdueInvoices: [Invoice] {
        invoices.filter { $0.isOverdue }.sorted { $0.daysOverdue > $1.daysOverdue }
    }
    private var overdueTotal: Double { overdueInvoices.reduce(0) { $0 + $1.balanceDue } }

    private var collectedPercent: Int {
        guard billed > 0 else { return 0 }
        return Int((received / billed * 100).rounded())
    }

    private var bars: [ReportBar] {
        let cal = Calendar.current
        let now = Date()
        let thisMonth = cal.dateInterval(of: .month, for: now)?.start ?? now
        let limit = cal.date(byAdding: .month, value: -11, to: thisMonth) ?? thisMonth
        var first: Date = period.start() ?? (invoices.last?.date ?? now)
        first = cal.dateInterval(of: .month, for: first)?.start ?? first
        if first < limit { first = limit }

        var result: [ReportBar] = []
        var cursor = first
        while cursor <= thisMonth {
            var billedSum = 0.0
            var receivedSum = 0.0
            for inv in invoices where cal.isDate(inv.date, equalTo: cursor, toGranularity: .month) {
                billedSum += inv.grandTotal
                receivedSum += inv.paidAmount
            }
            let label = cursor.formatted(.dateTime.month(.abbreviated))
            result.append(ReportBar(label: label, kind: "Billed", amount: billedSum))
            result.append(ReportBar(label: label, kind: "Received", amount: receivedSum))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private var topCustomers: [ReportCustomer] {
        var totals: [String: Double] = [:]
        for inv in periodInvoices {
            totals[inv.customerName, default: 0] += inv.grandTotal
        }
        let list: [ReportCustomer] = totals.map { ReportCustomer(name: $0.key, total: $0.value) }
        return Array(list.sorted { $0.total > $1.total }.prefix(5))
    }

    private func money(_ value: Double) -> String {
        let number: String = value.formatted(.number.precision(.fractionLength(0)))
        return currencySymbol + " " + number
    }

    // MARK: Body
    var body: some View {
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(ReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if invoices.isEmpty {
                ContentUnavailableView(
                    "No invoices yet",
                    systemImage: "chart.bar",
                    description: Text("Reports appear once you create invoices from delivered quotations.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ReportKPI(label: "Billed", value: money(billed),
                                  note: "\(periodInvoices.count) invoice\(periodInvoices.count == 1 ? "" : "s")",
                                  noteColor: .secondary)
                        ReportKPI(label: "Received", value: money(received),
                                  note: "\(collectedPercent)% of billed", noteColor: .green)
                        ReportKPI(label: "Outstanding", value: money(outstanding),
                                  note: "\(outstandingCount) invoice\(outstandingCount == 1 ? "" : "s")",
                                  noteColor: .orange)
                        ReportKPI(label: "Overdue now", value: money(overdueTotal),
                                  note: "\(overdueInvoices.count) invoice\(overdueInvoices.count == 1 ? "" : "s")",
                                  noteColor: .red)
                    }
                    .listRowInsets(.init(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                Section("Billed vs received by month") {
                    Chart(bars) { bar in
                        BarMark(x: .value("Month", bar.label),
                                y: .value("Amount", bar.amount))
                            .foregroundStyle(by: .value("Type", bar.kind))
                            .position(by: .value("Type", bar.kind))
                    }
                    .chartForegroundStyleScale(["Billed": Color.blue, "Received": Color.green])
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let amount = value.as(Double.self) {
                                    Text(amount.formatted(.number.notation(.compactName)))
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                    .padding(.vertical, 6)
                }

                Section("Top customers") {
                    if topCustomers.isEmpty {
                        Text("No invoices in this period.").foregroundColor(.secondary)
                    } else {
                        ForEach(topCustomers) { customer in
                            HStack {
                                Text(customer.name).lineLimit(1)
                                Spacer()
                                Text(money(customer.total)).fontWeight(.semibold)
                            }
                        }
                    }
                }

                Section {
                    if overdueInvoices.isEmpty {
                        Label("Nothing overdue", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        ForEach(overdueInvoices) { inv in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(inv.invoiceNumber).fontWeight(.semibold)
                                    Text("\(inv.customerName) · \(inv.daysOverdue) day\(inv.daysOverdue == 1 ? "" : "s") overdue")
                                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(money(inv.balanceDue))
                                    .fontWeight(.semibold).foregroundColor(.red)
                            }
                        }
                    }
                } header: {
                    Text("Overdue invoices")
                } footer: {
                    Text("Overdue uses the due date from each invoice's payment term, for example Net 30 Days. It always shows today, whatever period is chosen.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - KPI card
private struct ReportKPI: View {
    let label: String
    let value: String
    let note: String
    let noteColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(note).font(.caption2).foregroundColor(noteColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
