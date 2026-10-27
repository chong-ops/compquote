import SwiftUI
import SwiftData

// PREVIEW-ONLY mockup of the proposed Edit Quotation redesign.
// Not wired into the app. Delete this file after review.

struct EditQuotationViewPreviewMockup: View {
    // Mock data (no SwiftData model needed for a pure visual preview)
    let quoteNumber   = "Q26212"
    let customerName  = "Sivanesamalar Sivajawthe [Sivanesamalar Enterprise]"
    let statusText    = "Draft"
    let statusColor   = Color.secondary
    let grandTotal    = 5_999.00
    let items: [MockItem] = [
        .init(index: 1, code: "MDVH4ZP/A",
              desc: "15-inch MacBook Air: Apple M5 chip with 10-core CPU, 10-core GPU, 24GB RAM, 512GB SSD",
              qty: 1, unit: 5_499.00, total: 5_499.00),
        .init(index: 2, code: "MU8F3ZP/A",
              desc: "AppleCare+ for MacBook Air",
              qty: 1, unit: 500.00, total: 500.00)
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Form {
                    // ── ①  Summary Card ─────────────────────────────
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quoteNumber)
                                        .font(.title2).fontWeight(.bold)
                                    Text(customerName)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                                Spacer()
                                StatusPill(text: statusText, color: statusColor)
                            }
                            Divider()
                            HStack {
                                Text("Grand Total").font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("RM \(String(format: "%.2f", grandTotal))")
                                    .font(.title3).fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            // Segmented Status control (Option ②)
                            Picker("", selection: .constant(0)) {
                                Text("Draft").tag(0)
                                Text("Confirmed").tag(1)
                                Text("Cancelled").tag(2)
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .listRowInsets(.init(top: 8, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                    }

                    // ── Document Details ────────────────────────────
                    Section("Document Details") {
                        HStack { Text("Quotation Number"); Spacer(); Text(quoteNumber).foregroundColor(.secondary) }
                        HStack { Text("Date"); Spacer(); Text("22 Jul 2026").foregroundColor(.secondary) }
                        HStack { Text("Customer"); Spacer(); Text("Sivanesamalar…").foregroundColor(.secondary) }

                        // Collapsed by default — tap to reveal Student Name & ID.
                        DisclosureGroup {
                            HStack { Text("Student Name"); Spacer(); Text("").foregroundColor(.secondary) }
                            HStack { Text("Student ID"); Spacer(); Text("").foregroundColor(.secondary) }
                        } label: {
                            HStack {
                                Image(systemName: "graduationcap")
                                    .foregroundColor(.secondary).font(.footnote)
                                Text("Student Details (optional)")
                            }
                        }
                    }

                    // ── ③  Line Items as Numbered Cards ─────────────
                    Section("Line Items") {
                        ForEach(items) { item in
                            LineItemCard(item: item)
                                .listRowInsets(.init(top: 6, leading: 12, bottom: 6, trailing: 12))
                                .listRowBackground(Color.clear)
                        }

                        Button {
                        } label: {
                            Label("Add Item", systemImage: "plus.circle")
                        }
                    }

                    // ── Discount & Tax (compact preview) ────────────
                    Section("Discount & Tax") {
                        HStack { Text("Discount %"); Spacer(); Text("0.00 %").foregroundColor(.secondary) }
                        HStack { Text("Tax (SST) %"); Spacer(); Text("0.00 %").foregroundColor(.secondary) }
                    }

                    Color.clear.frame(height: 80).listRowBackground(Color.clear)
                }

                // Sticky Grand Total bar
                HStack {
                    Text("Grand Total").font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                    Spacer()
                    Text("RM \(String(format: "%.2f", grandTotal))")
                        .font(.title3).fontWeight(.bold).foregroundColor(.blue)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .navigationTitle("Edit Quotation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // ── ⑤  Consolidated toolbar ────────────────────────
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { } label: { Label("Preview PDF", systemImage: "eye") }
                        Button { } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
                        Button { } label: { Label("Email PDF", systemImage: "envelope") }
                        Divider()
                        Button { } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { }.fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Helpers used only in the preview

struct MockItem: Identifiable {
    let id = UUID()
    let index: Int
    let code: String
    let desc: String
    let qty: Int
    let unit: Double
    let total: Double
}

private struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.badge.clock").font(.caption)
            Text(text).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}

private struct LineItemCard: View {
    let item: MockItem
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.15)).frame(width: 26, height: 26)
                Text("\(item.index)").font(.caption).fontWeight(.bold).foregroundColor(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.code).font(.headline)
                Text(item.desc).font(.caption).foregroundColor(.secondary).lineLimit(2)
                Text("Qty \(item.qty) × RM \(String(format: "%.2f", item.unit))")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Spacer()
            Text("RM \(String(format: "%.2f", item.total))")
                .fontWeight(.semibold)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    EditQuotationViewPreviewMockup()
}
