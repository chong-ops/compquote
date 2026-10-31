import SwiftUI
import SwiftData

struct ServiceReportsView: View {
    @Query(sort: \ServiceReport.date, order: .reverse) private var reports: [ServiceReport]
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var filterStatus: ServiceStatus? = nil
    @State private var showCreateSheet = false
    @State private var reportToEdit: ServiceReport?
    @State private var pdfToShare: IdentifiableURL?
    @State private var pdfToPreview: IdentifiableURL?
    @State private var reportToDelete: ServiceReport?
    @State private var showDeleteConfirm = false

    private let statusTabs: [(label: String, icon: String, status: ServiceStatus?)] = [
        ("All", "line.3.horizontal.decrease.circle", nil),
        ("Open", "exclamationmark.circle", .open),
        ("Progress", "wrench.and.screwdriver", .inProgress),
        ("Resolved", "checkmark.seal", .resolved),
        ("Closed", "archivebox", .closed)
    ]

    var filteredReports: [ServiceReport] {
        reports.filter { report in
            let matchesSearch = searchText.isEmpty ||
                report.reportNumber.localizedCaseInsensitiveContains(searchText) ||
                report.customerName.localizedCaseInsensitiveContains(searchText) ||
                report.technicianName.localizedCaseInsensitiveContains(searchText)
            let matchesStatus = filterStatus == nil || report.status == filterStatus
            return matchesSearch && matchesStatus
        }
    }

    private var reportGroups: [MonthGroup<ServiceReport>] {
        monthGroups(filteredReports, date: \.date, total: { _ in 0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(statusTabs, id: \.label) { tab in
                    let count = tab.status.map { status in reports.filter { $0.status == status }.count } ?? reports.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filterStatus = tab.status }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 17, weight: filterStatus == tab.status ? .semibold : .regular))
                            Text(tab.label)
                                .font(.system(size: 10, weight: filterStatus == tab.status ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text("\(count)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundColor(filterStatus == tab.status ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    let tabWidth = geo.size.width / CGFloat(statusTabs.count)
                    let selectedIndex = statusTabs.firstIndex(where: { $0.status == filterStatus }) ?? 0
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: tabWidth, height: 2)
                        .offset(x: tabWidth * CGFloat(selectedIndex))
                        .animation(.easeInOut(duration: 0.2), value: filterStatus)
                }
            }

            Divider()

            List {
                ForEach(reportGroups) { group in
                  Section {
                    ForEach(group.items) { report in
                        ServiceReportRow(report: report)
                            .contentShape(Rectangle())
                            .onTapGesture { reportToEdit = report }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    reportToDelete = report
                                    showDeleteConfirm = true
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button { sharePDF(for: report) } label: {
                                    Label("Share PDF", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                            }
                            .contextMenu {
                                Button { reportToEdit = report } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                Button { previewPDF(for: report) } label: {
                                    Label("Preview PDF", systemImage: "eye")
                                }
                                Button { sharePDF(for: report) } label: {
                                    Label("Share PDF", systemImage: "square.and.arrow.up")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    reportToDelete = report
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                  } header: {
                    ReportMonthHeader(date: group.id, count: group.items.count)
                  }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .searchable(text: $searchText, prompt: "Search reports…")
            .overlay {
                if filteredReports.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Service Reports" : "No Results",
                        systemImage: "wrench.and.screwdriver",
                        description: Text(searchText.isEmpty ? "Tap + to log your first service job." : "Try adjusting your search or filter.")
                    )
                }
            }
        }
        .navigationTitle("Service Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { showCreateSheet = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showCreateSheet) { CreateServiceReportView() }
        .sheet(item: $reportToEdit) { EditServiceReportView(report: $0) }
        .sheet(item: $pdfToShare) { wrapped in
            ActivityShareSheet(items: [wrapped.url])
        }
        .sheet(item: $pdfToPreview) { wrapped in
            NavigationStack {
                PDFViewer(url: wrapped.url)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("PDF Preview")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { pdfToPreview = nil }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { pdfToShare = wrapped } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("Share PDF")
                        }
                    }
            }
        }
        .deleteConfirmation(
            isPresented: $showDeleteConfirm,
            itemName: reportToDelete?.reportNumber ?? ""
        ) {
            if let report = reportToDelete {
                withAnimation { modelContext.delete(report) }
            }
            reportToDelete = nil
        }
    }

    private func sharePDF(for report: ServiceReport) {
        guard let url = PDFGenerator.generate(
            view: ServiceReportPDFView(report: report),
            filename: report.reportNumber
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func previewPDF(for report: ServiceReport) {
        guard let url = PDFGenerator.generate(
            view: ServiceReportPDFView(report: report),
            filename: report.reportNumber
        ) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }
}

// MARK: - Month header (reports have no money total, so show the count only)
struct ReportMonthHeader: View {
    let date: Date
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(date.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(count == 1 ? "1 report" : "\(count) reports")
                .font(.caption).foregroundColor(.secondary)
        }
        .textCase(nil)
        .foregroundColor(.primary)
    }
}

// MARK: - Service Report Row
// Same layout as DocumentRow: status chip, number + status, customer + date.
struct ServiceReportRow: View {
    let report: ServiceReport

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.status.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(report.status.color)
                .frame(width: 36, height: 36)
                .background(report.status.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(report.status.rawValue)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(report.reportNumber).fontWeight(.semibold)
                    Spacer(minLength: 8)
                    Text(report.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(report.status.color)
                        .lineLimit(1).fixedSize()
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(report.customerName)
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortDocumentDate(report.date))
                        .font(.caption2).foregroundColor(.secondary)
                        .lineLimit(1).fixedSize()
                }
                if !report.deviceModel.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "desktopcomputer").font(.caption2)
                        Text(report.deviceModel).font(.caption)
                        if !report.serialNumber.isEmpty {
                            Text("· S/N: \(report.serialNumber)").font(.caption2)
                        }
                    }
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }
                if !report.issueDescription.isEmpty {
                    Text(report.issueDescription)
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Status Badge
struct StatusBadge: View {
    let status: ServiceStatus
    var body: some View {
        Text(status.rawValue)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(status.color.opacity(0.15))
            .foregroundColor(status.color)
            .clipShape(Capsule())
    }
}

// MARK: - Create Service Report
struct CreateServiceReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ServiceReport.date, order: .reverse) private var existing: [ServiceReport]
    @Query(sort: \Customer.name) private var customers: [Customer]

    @State private var reportNumber = ""
    @State private var customerSearchText = ""
    @State private var selectedCustomer: Customer?
    @State private var customerToDuplicate: Customer?
    @State private var showAddCustomer = false
    @State private var deviceModel = ""
    @State private var serialNumber = ""
    @State private var showDevicePicker = false
    @State private var showTechPicker = false
    @State private var notes = ""
    @State private var issueDescription = ""
    @State private var resolution = ""
    @State private var technicianName = ""
    @State private var status: ServiceStatus = .open
    @State private var quotationNumber = ""
    @State private var warrantyStatus = ""
    @State private var extraItems = ""
    @State private var conditionCheck = ""
    @State private var termsText = ServiceReport.defaultTerms

    var filteredCustomers: [Customer] {
        // Same search as the quotation: every word must match somewhere on the customer.
        let tokens = customerSearchText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return customers }
        return customers.filter { c in
            let haystack = [c.name, c.company, c.contactNumber, c.email, c.whatsappNumber,
                            c.address, c.postcode, c.state, c.country]
                .joined(separator: " ")
            return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Report Details") {
                    TextField("Report Number", text: $reportNumber).autocorrectionDisabled()
                    Picker("Status", selection: $status) {
                        ForEach(ServiceStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("Customer") {
                    if let c = selectedCustomer {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).fontWeight(.semibold)
                                Text(c.company).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Change") { selectedCustomer = nil; customerSearchText = "" }
                                .font(.footnote).foregroundColor(.blue)
                        }
                    } else {
                        TextField("Search customer name or company…", text: $customerSearchText)
                            .autocorrectionDisabled()

                        if !customerSearchText.isEmpty {
                            ForEach(filteredCustomers) { c in
                                HStack {
                                    Button {
                                        selectedCustomer = c; customerSearchText = ""
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(c.name).fontWeight(.medium).foregroundColor(.primary)
                                            Text(c.company).font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    .buttonStyle(.borderless)

                                    Spacer()

                                    Button { customerToDuplicate = c } label: {
                                        Image(systemName: "person.badge.plus").foregroundColor(.orange)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Duplicate \(c.name)")
                                }
                                .swipeActions(edge: .trailing) {
                                    Button { customerToDuplicate = c } label: {
                                        Label("Duplicate", systemImage: "person.badge.plus")
                                    }
                                    .tint(.orange)
                                }
                            }

                            if filteredCustomers.isEmpty {
                                Text("No customer found for \"\(customerSearchText)\"")
                                    .font(.caption).foregroundColor(.secondary)
                                Button { showAddCustomer = true } label: {
                                    Label("Add \"\(customerSearchText)\" as new customer",
                                          systemImage: "person.crop.circle.badge.plus")
                                        .font(.footnote)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Device Information") {
                    DeviceModelPickerButton(deviceModel: $deviceModel, showPicker: $showDevicePicker)
                        .autocorrectionDisabled()
                    TextField("Serial Number", text: $serialNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    WarrantyPicker(selection: $warrantyStatus)
                    TitledMultiline(title: "Extra items sent in with device", placeholder: "e.g. charger, box, case", text: $extraItems, lines: 2...5)
                    TitledMultiline(title: "Device condition check", placeholder: "e.g. scratches, dents, screen, power on", text: $conditionCheck, lines: 3...8)
                }
                Section("Job Details") {
                    TextField("Issue Description", text: $issueDescription, axis: .vertical).lineLimit(3...10)
                    TextField("Resolution / Work Done", text: $resolution, axis: .vertical).lineLimit(3...10)
                    TechnicianPickerButton(technicianName: $technicianName, showPicker: $showTechPicker)
                    LabeledContent("Quotation No.") {
                        TextField("Optional", text: $quotationNumber)
                            .multilineTextAlignment(.trailing).autocorrectionDisabled()
                    }
                    TextField("Internal Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    TextField("Terms & Conditions", text: $termsText, axis: .vertical).lineLimit(4...14)
                } header: {
                    Text("Terms & Conditions")
                } footer: {
                    Text("Printed on the service report PDF. You can edit it for this report.")
                }
            }
            .navigationTitle("New Service Report")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                let reportPrefix = UserDefaults.standard.string(forKey: AppStorageKeys.reportNumberPrefix) ?? ""
                if !reportPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
                    reportNumber = DocumentNumberGenerator.next(
                        inAll: existing.map(\.reportNumber), prefix: reportPrefix
                    ) ?? "SR-2026-001"
                } else {
                    reportNumber = existing.first.map {
                        DocumentNumberGenerator.next(after: $0.reportNumber)
                    } ?? "SR-2026-001"
                }
            }
            .prefixPrompt(.report) {
                let p = UserDefaults.standard.string(forKey: AppStorageKeys.reportNumberPrefix) ?? ""
                reportNumber = DocumentNumberGenerator.next(
                    inAll: existing.map(\.reportNumber), prefix: p) ?? "SR-2026-001"
            }
            .sheet(isPresented: $showDevicePicker) {
                DeviceModelPickerSheet(selected: $deviceModel)
            }
            .sheet(isPresented: $showTechPicker) {
                TechnicianPickerSheet(selected: $technicianName)
            }
            .sheet(item: $customerToDuplicate) { original in
                DuplicateCustomerSheet(original: original) { newCustomer in
                    selectedCustomer = newCustomer
                    customerSearchText = ""
                }
            }
            .sheet(isPresented: $showAddCustomer) {
                AddCustomerSheet(prefilledName: customerSearchText) { newCustomer in
                    selectedCustomer = newCustomer
                    customerSearchText = ""
                }
            }
            .toolbar {
                ToolbarItem(id: "ti_5", placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            ToolbarItem(id: "ti_6", placement: .topBarTrailing) {
                    Button("Save") {
                        let customerLabel = selectedCustomer.map { "\($0.name) [\($0.company)]" } ?? "Walk-in Customer"
                        let report = ServiceReport(
                            reportNumber: reportNumber,
                            customerName: customerLabel,
                            deviceModel: deviceModel,
                            serialNumber: serialNumber,
                            issueDescription: issueDescription,
                            resolution: resolution,
                            technicianName: technicianName,
                            status: status
                        )
                        report.notes = notes
                        report.quotationNumber = quotationNumber.trimmingCharacters(in: .whitespaces)
                        report.warrantyStatus = warrantyStatus
                        report.extraItems = extraItems
                        report.conditionCheck = conditionCheck
                        report.termsText = termsText
                        modelContext.insert(report)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(reportNumber.isEmpty || issueDescription.isEmpty || technicianName.isEmpty)
                }
            }
        }
        .presentationSizing(.page)
    }
}

// MARK: - Edit Service Report
struct EditServiceReportView: View {
    @Bindable var report: ServiceReport
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    // Local state for status picker — computed properties can't be bound with $
    @State private var selectedStatus: ServiceStatus = .open
    @State private var showDevicePicker = false
    @State private var showTechPicker = false
    @State private var notes = ""
    @State private var pdfToShare: IdentifiableURL?
    @State private var sendInfo: SendDocumentInfo?
    @State private var pdfToPreview: IdentifiableURL?

    var body: some View {
        NavigationStack {
            Form {
                Section("Report Details") {
                    TextField("Report Number", text: $report.reportNumber).autocorrectionDisabled()
                    DatePicker("Date", selection: $report.date, displayedComponents: .date)
                    Picker("Status", selection: $selectedStatus) {
                        ForEach(ServiceStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: selectedStatus) { _, new in report.status = new }
                }

                Section("Customer") {
                    TextField("Customer Name", text: $report.customerName, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Device Information") {
                    DeviceModelPickerButton(deviceModel: $report.deviceModel, showPicker: $showDevicePicker)
                    TextField("Serial Number", text: $report.serialNumber)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                    WarrantyPicker(selection: $report.warrantyStatus)
                    TitledMultiline(title: "Extra items sent in with device", placeholder: "e.g. charger, box, case", text: $report.extraItems, lines: 2...5)
                    TitledMultiline(title: "Device condition check", placeholder: "e.g. scratches, dents, screen, power on", text: $report.conditionCheck, lines: 3...8)
                }

                Section("Job Details") {
                    TextField("Issue Description", text: $report.issueDescription, axis: .vertical).lineLimit(3...10)
                    TextField("Resolution / Work Done", text: $report.resolution, axis: .vertical).lineLimit(3...10)
                    TechnicianPickerButton(technicianName: $report.technicianName, showPicker: $showTechPicker)
                    LabeledContent("Quotation No.") {
                        TextField("Optional", text: $report.quotationNumber)
                            .multilineTextAlignment(.trailing).autocorrectionDisabled()
                    }
                    TextField("Internal Notes", text: $report.notes, axis: .vertical).lineLimit(2...4)
                }

                Section {
                    TextField("Terms & Conditions", text: $report.termsText, axis: .vertical).lineLimit(4...14)
                    if report.termsText.isEmpty {
                        Button("Use standard terms") { report.termsText = ServiceReport.defaultTerms }
                    }
                } header: {
                    Text("Terms & Conditions")
                } footer: {
                    Text("Printed on the service report PDF.")
                }

                DeleteRecordSection(title: "Delete Report", itemName: report.reportNumber) {
                    let target = report
                    dismiss()
                    modelContext.deleteAfterSheetCloses(target)
                }
            }
            .navigationTitle("Edit Report")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { selectedStatus = report.status }
            .cancelEdits(of: report) { r in
                ModelSnapshot([
                    FieldSnapshot(r, \.date), FieldSnapshot(r, \.reportNumber),
                    FieldSnapshot(r, \.customerName), FieldSnapshot(r, \.deviceModel),
                    FieldSnapshot(r, \.serialNumber), FieldSnapshot(r, \.issueDescription),
                    FieldSnapshot(r, \.resolution), FieldSnapshot(r, \.technicianName),
                    FieldSnapshot(r, \.notes), FieldSnapshot(r, \.statusRaw),
                    FieldSnapshot(r, \.quotationNumber), FieldSnapshot(r, \.warrantyStatus),
                    FieldSnapshot(r, \.extraItems), FieldSnapshot(r, \.conditionCheck),
                    FieldSnapshot(r, \.termsText)
                ])
            }
            .sheet(isPresented: $showDevicePicker) {
                DeviceModelPickerSheet(selected: $report.deviceModel)
            }
            .sheet(isPresented: $showTechPicker) {
                TechnicianPickerSheet(selected: $report.technicianName)
            }
            .toolbar {
                ToolbarItem(id: "report-pdf-actions", placement: .topBarTrailing) {
                    Menu {
                        Button { previewPDF() } label: {
                            Label("Preview PDF", systemImage: "eye")
                        }
                        Button { sharePDF() } label: {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        Button { sendInfo = SendDocumentInfo.serviceReport(report) } label: {
                            Label("Send to Customer…", systemImage: "paperplane")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(id: "ti_7", placement: .topBarTrailing) {
                    Button("Save") { try? modelContext.save(); dismiss() }
                }
            }
            .sheet(item: $pdfToShare) { wrapped in
                ActivityShareSheet(items: [wrapped.url])
            }
            .sheet(item: $sendInfo) { SendDocumentSheet(info: $0) }
            .sheet(item: $pdfToPreview) { wrapped in
                NavigationStack {
                    PDFViewer(url: wrapped.url)
                        .ignoresSafeArea(edges: .bottom)
                        .navigationTitle("PDF Preview")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Close") { pdfToPreview = nil }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button { pdfToShare = wrapped } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .accessibilityLabel("Share PDF")
                            }
                        }
                }
            }
        }
        .presentationSizing(.page)
    }

    private func sharePDF() {
        guard let url = PDFGenerator.generate(
            view: ServiceReportPDFView(report: report),
            filename: report.reportNumber
        ) else { return }
        pdfToShare = IdentifiableURL(url: url)
    }

    private func previewPDF() {
        guard let url = PDFGenerator.generate(
            view: ServiceReportPDFView(report: report),
            filename: report.reportNumber
        ) else { return }
        pdfToPreview = IdentifiableURL(url: url)
    }
}

// MARK: - Service Report PDF View
struct ServiceReportPDFView: View {
    let report: ServiceReport

    // Fixed colours for the PDF: the exported file must not depend on light/dark dynamic colours.
    private let boxGray = Color(red: 242/255, green: 242/255, blue: 247/255)

    @AppStorage(AppStorageKeys.companyName) private var companyName = "My Computer Shop"
    @AppStorage(AppStorageKeys.companyAddress) private var companyAddress = "123 Tech Street"
    @AppStorage(AppStorageKeys.companyContact) private var companyContact = "info@shop.com"
    @AppStorage(AppStorageKeys.selectedPDFLayout) private var selectedLayout = "Corporate Blue (Standard)"
    @AppStorage(AppStorageKeys.serviceReportTitle) private var documentTitle = "SERVICE REPORT"
    @AppStorage(AppStorageKeys.showCompanyLogo) private var showLogo = true
    @AppStorage(AppStorageKeys.uploadedLogoData) private var logoData: Data?

    var body: some View {
        let layout = PDFLayoutTemplate(rawValue: selectedLayout) ?? .corporate

        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(documentTitle)
                        .font(.system(size: 20, weight: .bold)).foregroundColor(layout.accentColor)
                    Text("No: \(report.reportNumber)").font(.system(size: 10))
                    Text("Date: \(report.date.formatted(date: .long, time: .omitted))")
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if showLogo, let data = logoData, let img = UIImage(data: data) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 36)
                    }
                    Text(companyName).font(.system(size: 11, weight: .bold))
                    Text(companyAddress).font(.system(size: 8)).foregroundColor(.secondary)
                    Text(companyContact).font(.system(size: 8)).foregroundColor(.secondary)
                }
            }

            Rectangle().fill(layout.accentColor).frame(height: 1.5)

            // Customer & Status & Device
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CUSTOMER").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(report.customerName).font(.system(size: 10, weight: .semibold)).foregroundColor(.black)
                    if !report.deviceModel.isEmpty {
                        Text("DEVICE").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary).padding(.top, 4)
                        Text(report.deviceModel).font(.system(size: 9)).foregroundColor(.black)
                        if !report.serialNumber.isEmpty {
                            Text("S/N: \(report.serialNumber)").font(.system(size: 8)).foregroundColor(.secondary)
                        }
                    }
                    if !report.warrantyStatus.isEmpty {
                        Text("WARRANTY").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary).padding(.top, 4)
                        Text(report.warrantyStatus).font(.system(size: 9)).foregroundColor(.black)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("STATUS").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(report.status.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(report.status.color.opacity(0.15))
                        .foregroundColor(report.status.color)
                        .clipShape(Capsule())
                }
            }
            .padding(10).background(boxGray, in: RoundedRectangle(cornerRadius: 6))

            // Items received and condition check
            if !report.extraItems.isEmpty || !report.conditionCheck.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if !report.extraItems.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("EXTRA ITEMS SENT WITH DEVICE").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                            Text(report.extraItems).font(.system(size: 10)).lineSpacing(2).foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !report.conditionCheck.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("DEVICE CONDITION CHECK").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                            Text(report.conditionCheck).font(.system(size: 10)).lineSpacing(2).foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(boxGray, in: RoundedRectangle(cornerRadius: 6))
            }

            // Issue Description
            VStack(alignment: .leading, spacing: 4) {
                Text("ISSUE DESCRIPTION").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                Text(report.issueDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.black)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
            .background(boxGray, in: RoundedRectangle(cornerRadius: 6))

            // Resolution
            VStack(alignment: .leading, spacing: 4) {
                Text("RESOLUTION / WORK PERFORMED").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                Text(report.resolution.isEmpty ? "Pending" : report.resolution)
                    .font(.system(size: 11))
                    .foregroundColor(.black)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(boxGray, in: RoundedRectangle(cornerRadius: 6))

            // Quotation number for this service
            if !report.quotationNumber.isEmpty {
                HStack(spacing: 6) {
                    Text("QUOTATION NO.").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(report.quotationNumber).font(.system(size: 10, weight: .semibold))
                }
            }

            // Terms & Conditions
            if !report.termsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TERMS & CONDITIONS").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(report.termsText).font(.system(size: 8)).lineSpacing(2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Technician & Signature
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SERVICED BY").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Text(report.technicianName).font(.system(size: 10, weight: .semibold))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("CUSTOMER SIGNATURE").font(.system(size: 7, weight: .bold)).foregroundColor(.secondary)
                    Rectangle().fill(Color(.systemGray4)).frame(width: 140, height: 1)
                }
            }
            .padding(.top, 8)
        }
        .frame(width: 531, alignment: .leading)
        .padding(32)
        .background(Color.white)
        .font(.system(size: 10))
    }
}


// MARK: - Warranty picker
/// Warranty status for a service report. An empty value means "not specified".
struct WarrantyPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Warranty Status", selection: $selection) {
            Text("Not specified").tag("")
            ForEach(ServiceReport.warrantyOptions, id: \.self) { Text($0).tag($0) }
            // Keep a value that is no longer in the list (e.g. restored from a backup).
            if !selection.isEmpty && !ServiceReport.warrantyOptions.contains(selection) {
                Text(selection).tag(selection)
            }
        }
    }
}


// MARK: - Multi-line field with a title that stays visible
struct TitledMultiline: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 2...6

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: $text, axis: .vertical).lineLimit(lines)
        }
    }
}
