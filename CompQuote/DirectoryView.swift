import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DirectoryView: View {
    @Query(sort: \Customer.name) private var customers: [Customer]
    @Query(sort: \Vendor.name) private var vendors: [Vendor]
    @Query(sort: \Product.itemCode) private var products: [Product]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSegment = 0  // 0=Customers 1=Vendors 2=Products
    @State private var searchText = ""
    @State private var productToEdit: Product?
    @State private var productToDuplicate: Product?
    @State private var productStatusFilter = 0  // 0=All 1=Active 2=Inactive
    @State private var customerToEdit: Customer?
    @State private var customerToDuplicate: Customer?
    @State private var vendorToEdit: Vendor?
    @State private var vendorToDuplicate: Vendor?
    @State private var showAddCustomerSheet = false
    @State private var showAddVendorSheet = false
    @State private var showAddProductSheet = false
    @State private var deleteTarget: DeleteTarget?
    @State private var showDeleteConfirm = false

    private let directoryTabs: [(label: String, icon: String, selection: Int)] = [
        ("Customers", "person.2", 0),
        ("Vendors", "building.2", 1),
        ("Products", "shippingbox", 2)
    ]

    enum DeleteTarget {
        case customer(Customer)
        case vendor(Vendor)
        case product(Product)

        var label: String {
            switch self {
            case .customer(let c): return c.name
            case .vendor(let v):   return v.name
            case .product(let p):  return p.itemCode
            }
        }
    }

    var filteredCustomers: [Customer] {
        let tokens = searchText
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

    var filteredVendors: [Vendor] {
        let tokens = searchText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return vendors }
        return vendors.filter { v in
            let haystack = [v.name, v.company, v.contactNumber, v.email,
                            v.address, v.postcode, v.state, v.country, v.notes]
                .joined(separator: " ")
            return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

    var filteredProducts: [Product] {
        let base: [Product]
        switch productStatusFilter {
        case 1:  base = products.filter {  $0.isActive }
        case 2:  base = products.filter { !$0.isActive }
        default: base = products
        }
        let tokens = searchText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return base }
        return base.filter { p in
            let haystack = "\(p.itemCode) \(p.itemDescription)"
            return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(directoryTabs, id: \.selection) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSegment = tab.selection
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: selectedSegment == tab.selection ? .semibold : .regular))
                            Text(tab.label)
                                .font(.system(size: 11, weight: selectedSegment == tab.selection ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(selectedSegment == tab.selection ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.systemGroupedBackground))
            .overlay(alignment: .bottom) {
                GeometryReader { geo in
                    let tabWidth = geo.size.width / CGFloat(directoryTabs.count)
                    let selectedIndex = directoryTabs.firstIndex(where: { $0.selection == selectedSegment }) ?? 0
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: tabWidth, height: 2)
                        .offset(x: tabWidth * CGFloat(selectedIndex))
                        .animation(.easeInOut(duration: 0.2), value: selectedSegment)
                }
            }
            .onChange(of: selectedSegment) { _, _ in searchText = "" }

            Divider()

            if selectedSegment == 0 {
                List {
                    ForEach(alphaGroups(filteredCustomers, key: { $0.name })) { group in
                    Section {
                    ForEach(group.items) { customer in
                        HStack(spacing: 12) {
                            DirectoryIconChip(
                                systemName: customer.directoryType.symbol,
                                tint: customer.directoryType.tint
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(customer.name).font(.headline)
                                Text(customer.company).font(.subheadline).foregroundColor(.secondary)
                                if !customer.contactNumber.isEmpty {
                                    Text(customer.contactNumber).font(.caption).foregroundColor(.blue)
                                }
                                if !customer.address.isEmpty {
                                    Text(customer.fullAddress).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { customerToEdit = customer }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = .customer(customer)
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }

                            Button {
                                customerToDuplicate = customer
                            } label: { Label("Duplicate", systemImage: "person.badge.plus") }
                            .tint(.orange)
                        }
                    }
                    } header: { AlphaHeader(letter: group.letter, count: group.items.count) }
                }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .searchable(text: $searchText, prompt: "Search customers…")
                .overlay {
                    if filteredCustomers.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No Customers" : "No Results",
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                }
            } else if selectedSegment == 1 {
                // VENDORS
                List {
                    ForEach(alphaGroups(filteredVendors, key: { $0.name })) { group in
                    Section {
                    ForEach(group.items) { vendor in
                        HStack(spacing: 12) {
                            DirectoryIconChip(systemName: "building.2.fill", tint: .purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(vendor.name).font(.headline)
                                Text(vendor.company).font(.subheadline).foregroundColor(.secondary)
                                if !vendor.contactNumber.isEmpty {
                                    Text(vendor.contactNumber).font(.caption).foregroundColor(.blue)
                                }
                                if !vendor.email.isEmpty {
                                    Text(vendor.email).font(.caption).foregroundColor(.purple)
                                }
                                if !vendor.address.isEmpty {
                                    Text(vendor.fullAddress).font(.caption2).foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { vendorToEdit = vendor }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = .vendor(vendor)
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }

                            Button {
                                vendorToDuplicate = vendor
                            } label: { Label("Duplicate", systemImage: "person.badge.plus") }
                            .tint(.orange)
                        }
                    }
                    } header: { AlphaHeader(letter: group.letter, count: group.items.count) }
                }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .searchable(text: $searchText, prompt: "Search vendors…")
                .overlay {
                    if filteredVendors.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No Vendors" : "No Results",
                            systemImage: "building.2"
                        )
                    }
                }
            } else {
                Picker("Status", selection: $productStatusFilter) {
                    Text("All").tag(0)
                    Text("Active").tag(1)
                    Text("Inactive").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.bottom, 4)

                List {
                    ForEach(alphaGroups(filteredProducts, key: { $0.itemCode })) { group in
                    Section {
                    ForEach(group.items) { product in
                        HStack {
                            DirectoryIconChip(
                                systemName: product.directoryCategory.symbol,
                                tint: product.directoryCategory.tint,
                                isDimmed: !product.isActive
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(product.itemCode).font(.headline)
                                        .foregroundColor(product.isActive ? .primary : .secondary)
                                    if !product.isActive {
                                        Text("INACTIVE")
                                            .font(.caption2).fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(Color.secondary)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(product.itemDescription).font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .opacity(product.isActive ? 1.0 : 0.5)
                                if product.defaultCost > 0 {
                                    Text(String(format: "Margin %.1f%%", product.margin))
                                        .font(.caption2).fontWeight(.medium)
                                        .foregroundColor(product.margin >= 0 ? .green : .red)
                                }
                            } // end VStack
                            .contentShape(Rectangle())
                            .onTapGesture { productToEdit = product }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(formatCurrency(product.defaultUnitPrice))
                                    .font(.body).fontWeight(.semibold)
                                if product.defaultCost > 0 {
                                    Text("Cost \(formatCurrency(product.defaultCost))")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                            }

                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteTarget = .product(product)
                                showDeleteConfirm = true
                            } label: { Label("Delete", systemImage: "trash") }

                            Button { productToDuplicate = product } label: {
                                Label("Duplicate", systemImage: "doc.on.doc")
                            }
                            .tint(.orange)
                        }
                    }
                    } header: { AlphaHeader(letter: group.letter, count: group.items.count) }
                }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .searchable(text: $searchText, prompt: "Search code or description…")
                .overlay {
                    if filteredProducts.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No Products" : "No Results",
                            systemImage: "shippingbox"
                        )
                    }
                }
            }
        }
        .navigationTitle("Directory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button {
                if selectedSegment == 0 { showAddCustomerSheet = true }
                else if selectedSegment == 1 { showAddVendorSheet = true }
                else { showAddProductSheet = true }
            } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showAddCustomerSheet) { AddCustomerSheet() }
        .sheet(isPresented: $showAddVendorSheet) { AddVendorSheet() }
        .sheet(isPresented: $showAddProductSheet) { AddProductSheet() }
        .sheet(item: $productToDuplicate) { DuplicateProductSheet(original: $0) }
        .sheet(item: $productToEdit) { MasterEditProductSheet(product: $0) }
        .sheet(item: $customerToEdit) { EditCustomerSheet(customer: $0) }
        .sheet(item: $customerToDuplicate) { DuplicateCustomerSheet(original: $0) }
        .sheet(item: $vendorToEdit) { EditVendorSheet(vendor: $0) }
        .sheet(item: $vendorToDuplicate) { DuplicateVendorSheet(original: $0) }
        .deleteConfirmation(
            isPresented: $showDeleteConfirm,
            itemName: deleteTarget?.label ?? ""
        ) {
            switch deleteTarget {
            case .customer(let c): withAnimation { modelContext.delete(c) }
            case .vendor(let v):   withAnimation { modelContext.delete(v) }
            case .product(let p):  withAnimation { modelContext.delete(p) }
            case nil:              break
            }
            deleteTarget = nil
        }
    }
}

// MARK: - Icon colours (each type / category gets its own colour)
private extension CustomerType {
    var tint: Color {
        switch self {
        case .personal: return .blue
        case .school:   return .green
        case .business: return .teal
        }
    }
}

private extension ProductCategory {
    var tint: Color {
        switch self {
        case .general:      return .gray
        case .computer:     return .blue
        case .display:      return .indigo
        case .keyboard:     return .teal
        case .mouse:        return .cyan
        case .printer:      return .brown
        case .phoneTablet:  return .pink
        case .networking:   return .mint
        case .storage:      return .purple
        case .cableAdapter: return .gray
        case .audio:        return .red
        case .camera:       return .orange
        case .software:     return .green
        case .components:   return .orange
        case .accessories:  return .brown
        }
    }
}

private extension Customer {
    var directoryType: CustomerType { CustomerType(rawValue: customerTypeRawValue ?? "") ?? .personal }
}

private extension Product {
    var directoryCategory: ProductCategory { ProductCategory(rawValue: categoryRawValue ?? "") ?? .general }
}

// MARK: - A–Z grouping helpers
private struct AlphaGroup<T>: Identifiable {
    let letter: String
    let items: [T]
    var id: String { letter }
}

/// Groups already-sorted items under their first letter ("#" for digits/symbols, last).
private func alphaGroups<T>(_ items: [T], key: (T) -> String) -> [AlphaGroup<T>] {
    var order: [String] = []
    var buckets: [String: [T]] = [:]
    for item in items {
        let first = key(item).trimmingCharacters(in: .whitespaces).first
        let letter = (first?.isLetter == true) ? String(first!).uppercased() : "#"
        if buckets[letter] == nil { order.append(letter) }
        buckets[letter, default: []].append(item)
    }
    let sorted = order.sorted { a, b in
        if a == "#" { return false }
        if b == "#" { return true }
        return a < b
    }
    return sorted.map { AlphaGroup(letter: $0, items: buckets[$0] ?? []) }
}

private struct AlphaHeader: View {
    let letter: String
    let count: Int
    var body: some View {
        HStack {
            Text(letter).font(.headline).foregroundColor(.primary)
            Spacer()
            Text("\(count)").font(.subheadline).foregroundColor(.secondary)
        }
        .textCase(nil)
    }
}

private struct DirectoryIconChip: View {
    let systemName: String
    let tint: Color
    var isDimmed = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 52, height: 52)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isDimmed ? 0.35 : 1)
            .accessibilityHidden(true)
    }
}

private struct CustomerTypePicker: View {
    @Binding var selection: CustomerType

    var body: some View {
        Picker("Customer Type", selection: $selection) {
            ForEach(CustomerType.allCases) { type in
                Label(type.title, systemImage: type.symbol).tag(type)
            }
        }
    }
}

// MARK: - Add Customer Sheet
struct AddCustomerSheet: View {
    var prefilledName: String = ""
    var onCreated: ((Customer) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var name = ""
    @State private var company = ""
    @State private var contactNumber = ""
    @State private var email = ""
    @State private var whatsappNumber = ""
    @State private var address = ""
    @State private var postcode = ""
    @State private var state = ""
    @State private var country = ""
    @State private var customerType: CustomerType = .personal

    enum Field { case name, company, contact, address, postcode, state, country }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Info") {
                    TextField("Full Name", text: $name).focused($focusedField, equals: .name)
                    TextField("Company Name", text: $company).focused($focusedField, equals: .company)
                    TextField("Phone Number", text: $contactNumber)
                        .keyboardType(.phonePad).focused($focusedField, equals: .contact)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("WhatsApp Number (if different)", text: $whatsappNumber)
                        .keyboardType(.phonePad)
                    CustomerTypePicker(selection: $customerType)
                }
                Section("Address") {
                    TextField("Street Address", text: $address)
                        .autocorrectionDisabled().focused($focusedField, equals: .address)
                    TextField("Postcode", text: $postcode)
                        .keyboardType(.numbersAndPunctuation).focused($focusedField, equals: .postcode)
                    TextField("State / City", text: $state).focused($focusedField, equals: .state)
                    TextField("Country", text: $country).focused($focusedField, equals: .country)
                }
            }
            .navigationTitle("New Customer")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if name.isEmpty { name = prefilledName }
            }
            .toolbar {
                ToolbarItem(id: "cancel-add-customer", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "ti_8", placement: .topBarTrailing) {
                    Button("Save") {
                        let customer = Customer(
                            name: name, company: company, contactNumber: contactNumber,
                            address: address, postcode: postcode, state: state, country: country,
                            customerTypeRawValue: customerType.rawValue
                        )
                        customer.email = email.trimmingCharacters(in: .whitespaces)
                        customer.whatsappNumber = whatsappNumber.trimmingCharacters(in: .whitespaces)
                        modelContext.insert(customer)
                        try? modelContext.save()
                        onCreated?(customer)
                        dismiss()
                    }
                    .disabled(name.isEmpty || company.isEmpty)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .presentationSizing(.page)
    }
}

// MARK: - Edit Customer Sheet
struct EditCustomerSheet: View {
    @Bindable var customer: Customer
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact Info") {
                    TextField("Full Name", text: $customer.name).focused($anyFocused)
                    TextField("Company Name", text: $customer.company).focused($anyFocused)
                    TextField("Phone Number", text: $customer.contactNumber)
                        .keyboardType(.phonePad).focused($anyFocused)
                    TextField("Email", text: $customer.email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("WhatsApp Number (if different)", text: $customer.whatsappNumber)
                        .keyboardType(.phonePad).focused($anyFocused)
                    CustomerTypePicker(selection: Binding(
                        get: { CustomerType(rawValue: customer.customerTypeRawValue ?? "") ?? .personal },
                        set: { customer.customerTypeRawValue = $0.rawValue }
                    ))
                }
                Section("Address") {
                    TextField("Street Address", text: $customer.address)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Postcode", text: $customer.postcode)
                        .keyboardType(.numbersAndPunctuation).focused($anyFocused)
                    TextField("State / City", text: $customer.state).focused($anyFocused)
                    TextField("Country", text: $customer.country).focused($anyFocused)
                }
                DeleteRecordSection(title: "Delete Customer",
                                    itemName: customer.company.isEmpty ? customer.name : customer.company) {
                    let target = customer
                    dismiss()
                    modelContext.deleteAfterSheetCloses(target)
                }
            }
            .navigationTitle("Edit Customer")
            .navigationBarTitleDisplayMode(.inline)
            .cancelEdits(of: customer) { c in
                ModelSnapshot([
                    FieldSnapshot(c, \.name), FieldSnapshot(c, \.company),
                    FieldSnapshot(c, \.contactNumber), FieldSnapshot(c, \.address),
                    FieldSnapshot(c, \.postcode), FieldSnapshot(c, \.state),
                    FieldSnapshot(c, \.country), FieldSnapshot(c, \.customerTypeRawValue),
                    FieldSnapshot(c, \.email), FieldSnapshot(c, \.whatsappNumber)
                ])
            }
            .toolbar {
                ToolbarItem(id: "done-edit-customer", placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
        }
        .presentationSizing(.page)
    }
}

private struct ProductCategoryPicker: View {
    @Binding var selection: ProductCategory

    var body: some View {
        Picker("Category", selection: $selection) {
            ForEach(ProductCategory.allCases) { category in
                Label(category.title, systemImage: category.symbol).tag(category)
            }
        }
    }
}

// MARK: - Duplicate item-code check
/// True when another product already uses this code (case-insensitive, ignoring spaces).
func productCodeExists(_ code: String, in products: [Product], excluding: Product? = nil) -> Bool {
    let c = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !c.isEmpty else { return false }
    return products.contains {
        $0.persistentModelID != excluding?.persistentModelID &&
        $0.itemCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == c
    }
}

// MARK: - Add Product Sheet
struct AddProductSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    @State private var itemCode = ""
    @State private var itemDescription = ""
    @State private var category: ProductCategory = .general
    @State private var calc = ProductMarginCalc()
    @Query private var allProducts: [Product]

    private var isDuplicate: Bool { productCodeExists(itemCode, in: allProducts) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item Code / SKU", text: $itemCode)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($anyFocused)
                    ProductCategoryPicker(selection: $category)
                } header: {
                    Text("Product Details")
                } footer: {
                    if isDuplicate {
                        Text("Item code \"\(itemCode)\" already exists. Use a different code.")
                            .foregroundColor(.red)
                    }
                }
                ProductMarginSection(calc: $calc, focused: $anyFocused)
            }
            .navigationTitle("New Product")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "cancel-add-product", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "ti_9", placement: .topBarTrailing) {
                    Button("Save") {
                        let product = Product(
                            itemCode: itemCode,
                            itemDescription: itemDescription,
                            defaultUnitPrice: calc.sp1,
                            defaultCost: calc.cp1,
                            defaultSP2: calc.sp2,
                            defaultCP2: calc.cp2,
                            defaultRebate1: calc.rebate1,
                            defaultRebate2: calc.rebate2,
                            defaultDisc1: calc.disc1,
                            defaultDisc2: calc.disc2,
                            categoryRawValue: category.rawValue
                        )
                        modelContext.insert(product)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(itemCode.trimmingCharacters(in: .whitespaces).isEmpty || isDuplicate)
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
        }
        .presentationSizing(.page)
    }
}

// MARK: - Duplicate Product Sheet
struct DuplicateProductSheet: View {
    let original: Product
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    @State private var itemCode = ""
    @State private var itemDescription = ""
    @State private var category: ProductCategory = .general
    @State private var calc = ProductMarginCalc()
    @State private var didLoad = false
    @Query private var allProducts: [Product]

    private var isDuplicate: Bool { productCodeExists(itemCode, in: allProducts) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item Code / SKU", text: $itemCode)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Description", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($anyFocused)
                    ProductCategoryPicker(selection: $category)
                } header: {
                    Text("Cloned Product")
                } footer: {
                    if isDuplicate {
                        Text("Item code \"\(itemCode)\" already exists. Use a different code.")
                            .foregroundColor(.red)
                    }
                }
                ProductMarginSection(calc: $calc, focused: $anyFocused)
            }
            .navigationTitle("Duplicate Product")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                itemCode        = original.itemCode + "-COPY"
                itemDescription = original.itemDescription
                calc.load(from: original)
                category = ProductCategory(rawValue: original.categoryRawValue ?? "") ?? .general
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "ti_10", placement: .topBarTrailing) {
                    Button("Save Copy") {
                        let copy = Product(
                            itemCode: itemCode,
                            itemDescription: itemDescription,
                            defaultUnitPrice: calc.sp1,
                            defaultCost: calc.cp1,
                            defaultSP2: calc.sp2,
                            defaultCP2: calc.cp2,
                            defaultRebate1: calc.rebate1,
                            defaultRebate2: calc.rebate2,
                            defaultDisc1: calc.disc1,
                            defaultDisc2: calc.disc2,
                            categoryRawValue: category.rawValue
                        )
                        modelContext.insert(copy)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(itemCode.trimmingCharacters(in: .whitespaces).isEmpty || isDuplicate)
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
        }
        .presentationSizing(.page)
    }
}

// MARK: - Edit Product Sheet
struct MasterEditProductSheet: View {
    @Bindable var product: Product
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    @State private var calc = ProductMarginCalc()
    @State private var initialCalc: ProductMarginCalc?
    @State private var didLoad = false
    @Query private var allProducts: [Product]

    private var isDuplicate: Bool { productCodeExists(product.itemCode, in: allProducts, excluding: product) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item Code / SKU", text: $product.itemCode)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Description", text: $product.itemDescription, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($anyFocused)
                    ProductCategoryPicker(selection: Binding(
                        get: { ProductCategory(rawValue: product.categoryRawValue ?? "") ?? .general },
                        set: { product.categoryRawValue = $0.rawValue }
                    ))
                    Toggle(isOn: $product.isActive) {
                        HStack(spacing: 8) {
                            Image(systemName: product.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(product.isActive ? .green : .secondary)
                            Text(product.isActive ? "Active" : "Inactive")
                        }
                    }
                    .tint(.green)
                } header: {
                    Text("Product Details")
                } footer: {
                    if isDuplicate {
                        Text("Item code \"\(product.itemCode)\" already exists. Use a different code.")
                            .foregroundColor(.red)
                    }
                }
                ProductMarginSection(calc: $calc, focused: $anyFocused)
                DeleteRecordSection(title: "Delete Product", itemName: product.itemCode) {
                    let target = product
                    dismiss()
                    modelContext.deleteAfterSheetCloses(target)
                }
            }
            .navigationTitle("Edit Product")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                calc.load(from: product)
                initialCalc = calc
            }
            .cancelEdits(of: product, extraChanges: { calc != initialCalc }) { p in
                ModelSnapshot([
                    FieldSnapshot(p, \.itemCode),
                    FieldSnapshot(p, \.itemDescription),
                    FieldSnapshot(p, \.isActive),
                    FieldSnapshot(p, \.categoryRawValue)
                ])
            }
            .toolbar {
                ToolbarItem(id: "ti_11", placement: .topBarTrailing) {
                    Button("Done") {
                        calc.save(to: product)
                        anyFocused = false
                        dismiss()
                    }
                    .disabled(product.itemCode.trimmingCharacters(in: .whitespaces).isEmpty || isDuplicate)
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
        }
        .presentationSizing(.page)
    }
}

// MARK: - Shared Margin Data Model for Product Sheets
struct ProductMarginCalc: Equatable {
    var sp1String     = ""
    var cp1String     = ""
    var rebate1String = ""
    var disc1String   = ""
    var sp2String     = ""
    var cp2String     = ""   // Direct CP2 input — independent cost for Scenario 2
    var rebate2String = ""   // Rebate 2 % (alternative way to derive CP2)
    var disc2String   = ""

    var sp1:     Double { Double(sp1String)     ?? 0 }
    var cp1:     Double { Double(cp1String)     ?? 0 }
    var rebate1: Double { Double(rebate1String) ?? 0 }
    var disc1:   Double { Double(disc1String)   ?? 0 }
    var sp2:     Double { Double(sp2String)     ?? 0 }
    var cp2:     Double { Double(cp2String)     ?? 0 }   // direct CP2 value
    var rebate2: Double { Double(rebate2String) ?? 0 }
    var disc2:   Double { Double(disc2String)   ?? 0 }

    var cp1Net:  Double { cp1 - (sp1 * rebate1 / 100) }
    var netSP1:  Double { sp1 * (1 - disc1 / 100) }
    var profit1: Double { netSP1 - cp1Net }
    var margin1: Double { netSP1 > 0 ? (profit1 / netSP1) * 100 : 0 }
    
    // Scenario 2 calculations: derived dynamically from baseline cp1 and rebate 2 %
    var cp2Base: Double { cp2 > 0 ? cp2 : cp1 }
    var cp2Net:  Double { cp2Base - (sp1 * rebate2 / 100) }
    var netSP2:  Double { sp2 * (1 - disc2 / 100) }
    var profit2: Double { netSP2 - cp2Net }
    var margin2: Double { netSP2 > 0 ? (profit2 / netSP2) * 100 : 0 }

    var showMargin:    Bool { cp1 > 0 && sp1 > 0 }
    var showScenario2: Bool { sp2 > 0 && cp1 > 0 }

    mutating func load(from p: Product) {
        sp1String     = p.defaultUnitPrice > 0 ? String(format: "%.2f", p.defaultUnitPrice) : ""
        cp1String     = p.defaultCost      > 0 ? String(format: "%.2f", p.defaultCost)      : ""
        sp2String     = p.defaultSP2       > 0 ? String(format: "%.2f", p.defaultSP2)       : ""
        cp2String     = p.defaultCP2       > 0 ? String(format: "%.2f", p.defaultCP2)       : ""
        rebate1String = p.defaultRebate1   > 0 ? String(format: "%.2f", p.defaultRebate1)   : ""
        rebate2String = p.defaultRebate2   > 0 ? String(format: "%.2f", p.defaultRebate2)   : ""
        disc1String   = p.defaultDisc1     > 0 ? String(format: "%.2f", p.defaultDisc1)     : ""
        disc2String   = p.defaultDisc2     > 0 ? String(format: "%.2f", p.defaultDisc2)     : ""
    }

    func save(to p: Product) {
        p.defaultUnitPrice = sp1
        p.defaultCost      = cp1
        p.defaultSP2       = sp2
        p.defaultCP2       = cp2
        p.defaultRebate1   = rebate1
        p.defaultRebate2   = rebate2
        p.defaultDisc1     = disc1
        p.defaultDisc2     = disc2
    }
}

// MARK: - Reusable Product Margin Section (used in Add, Edit, Duplicate sheets)
struct ProductMarginSection: View {
    @Binding var calc: ProductMarginCalc
    var focused: FocusState<Bool>.Binding

    // Dummy binding for selectedScenario — not used in product edit (no selection needed)
    @State private var dummyScenario: Int? = nil

    var body: some View {
        Section {
            CompactCalculatorTable(
                sp1: $calc.sp1String,
                cp1: $calc.cp1String,
                r1:  $calc.rebate1String,
                d1:  $calc.disc1String,
                df1: .constant(""),   // no fixed discount stored on product
                sp2: $calc.sp2String,
                cp2: $calc.cp2String,
                r2:  $calc.rebate2String,
                d2:  $calc.disc2String,
                df2: .constant(""),
                selectedScenario: $dummyScenario,
                isPOMode: false
            )
            .listRowInsets(.init())
            .listRowBackground(Color.clear)
        } header: {
            Text("Pricing Calculator")
        } footer: {
            Text("Values saved as defaults for this product. Rebate always calculated from SP1.")
                .font(.caption)
        }
    }
}

// Simple price/percent input row for product sheets
private struct PricingRow: View {
    let label: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var symbol: String = "$"

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(symbol).foregroundColor(.secondary).font(.subheadline)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused(focused)
                .frame(width: 90)
        }
    }
}

// MARK: - Add Vendor Sheet
struct AddVendorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    @State private var name = ""
    @State private var company = ""
    @State private var contactNumber = ""
    @State private var email = ""
    @State private var address = ""
    @State private var postcode = ""
    @State private var state = ""
    @State private var country = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Vendor / Supplier Info") {
                    TextField("Contact Name", text: $name).focused($anyFocused)
                    TextField("Company Name", text: $company).focused($anyFocused)
                    TextField("Phone Number", text: $contactNumber)
                        .keyboardType(.phonePad).focused($anyFocused)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($anyFocused)
                }
                Section("Address") {
                    TextField("Street Address", text: $address)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Postcode", text: $postcode)
                        .keyboardType(.numbersAndPunctuation).focused($anyFocused)
                    TextField("State / City", text: $state).focused($anyFocused)
                    TextField("Country", text: $country).focused($anyFocused)
                }
                Section("Notes") {
                    TextField("Internal notes about this vendor…", text: $notes,
                              axis: .vertical).lineLimit(2...4).focused($anyFocused)
                }
            }
            .navigationTitle("New Vendor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "cancel-add-vendor", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "ti_12", placement: .topBarTrailing) {
                    Button("Save") {
                        let v = Vendor(name: name, company: company,
                                       contactNumber: contactNumber,
                                       address: address, postcode: postcode,
                                       state: state, country: country,
                                       email: email, notes: notes)
                        modelContext.insert(v)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty || company.isEmpty)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
        }
        .presentationSizing(.page)
    }
}

// MARK: - Edit Vendor Sheet
struct EditVendorSheet: View {
    @Bindable var vendor: Vendor
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Vendor / Supplier Info") {
                    TextField("Contact Name", text: $vendor.name).focused($anyFocused)
                    TextField("Company Name", text: $vendor.company).focused($anyFocused)
                    TextField("Phone Number", text: $vendor.contactNumber)
                        .keyboardType(.phonePad).focused($anyFocused)
                    TextField("Email", text: $vendor.email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($anyFocused)
                }
                Section("Address") {
                    TextField("Street Address", text: $vendor.address)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Postcode", text: $vendor.postcode)
                        .keyboardType(.numbersAndPunctuation).focused($anyFocused)
                    TextField("State / City", text: $vendor.state).focused($anyFocused)
                    TextField("Country", text: $vendor.country).focused($anyFocused)
                }
                Section("Notes") {
                    TextField("Internal notes…", text: $vendor.notes,
                              axis: .vertical).lineLimit(2...4).focused($anyFocused)
                }
                DeleteRecordSection(title: "Delete Vendor",
                                    itemName: vendor.company.isEmpty ? vendor.name : vendor.company) {
                    let target = vendor
                    dismiss()
                    modelContext.deleteAfterSheetCloses(target)
                }
            }
            .navigationTitle("Edit Vendor")
            .navigationBarTitleDisplayMode(.inline)
            .cancelEdits(of: vendor) { v in
                ModelSnapshot([
                    FieldSnapshot(v, \.name), FieldSnapshot(v, \.company),
                    FieldSnapshot(v, \.contactNumber), FieldSnapshot(v, \.address),
                    FieldSnapshot(v, \.postcode), FieldSnapshot(v, \.state),
                    FieldSnapshot(v, \.country), FieldSnapshot(v, \.email),
                    FieldSnapshot(v, \.notes)
                ])
            }
            .toolbar {
                ToolbarItem(id: "done-edit-customer", placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
        }
        .presentationSizing(.page)
    }
}

// MARK: - Duplicate Customer Sheet
// All fields pre-filled from the source customer but fully editable — useful for a
// 2nd contact at the same company, or a starting point for a similar new customer.
struct DuplicateCustomerSheet: View {
    let original: Customer
    var onCreated: ((Customer) -> Void)? = nil   // optional callback
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    @State private var name = ""
    @State private var company = ""
    @State private var contactNumber = ""
    @State private var email = ""
    @State private var whatsappNumber = ""
    @State private var address = ""
    @State private var postcode = ""
    @State private var state = ""
    @State private var country = ""
    @State private var customerType: CustomerType = .personal

    // CSV import
    @State private var showCSVImporter = false
    @State private var pendingRows: [OrderCSVRow] = []
    @State private var showRowPicker = false
    @State private var csvErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showCSVImporter = true
                    } label: {
                        Label("Import parent details from CSV…", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Fills Name, Phone Number, and Address from a school orders CSV.")
                }

                Section {
                    TextField("Full Name", text: $name).focused($anyFocused)
                    TextField("Company Name", text: $company).focused($anyFocused)
                    TextField("Phone Number", text: $contactNumber)
                        .keyboardType(.phonePad).focused($anyFocused)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("WhatsApp Number (if different)", text: $whatsappNumber)
                        .keyboardType(.phonePad).focused($anyFocused)
                    CustomerTypePicker(selection: $customerType)
                } header: {
                    Text("Contact Info")
                } footer: {
                    Text("Pre-filled from \(original.name). Edit any field to customize.")
                }

                Section("Address") {
                    TextField("Street Address", text: $address)
                        .autocorrectionDisabled().focused($anyFocused)
                    TextField("Postcode", text: $postcode)
                        .keyboardType(.numbersAndPunctuation).focused($anyFocused)
                    TextField("State / City", text: $state).focused($anyFocused)
                    TextField("Country", text: $country).focused($anyFocused)
                }
            }
            .navigationTitle("Duplicate Customer")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                name          = ""
                company       = original.company
                contactNumber = original.contactNumber
                email         = original.email
                whatsappNumber = original.whatsappNumber
                address       = original.address
                postcode      = original.postcode
                state         = original.state
                country       = original.country
                customerType = CustomerType(rawValue: original.customerTypeRawValue ?? "") ?? .personal
            }
            .fileImporter(
                isPresented: $showCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleCSVImport(result)
            }
            .sheet(isPresented: $showRowPicker) {
                OrderCSVRowPickerSheet(rows: pendingRows, preferredCompany: company) { row in
                    apply(row)
                }
            }
            .alert("Import Failed", isPresented: Binding(
                get: { csvErrorMessage != nil },
                set: { if !$0 { csvErrorMessage = nil } }
            )) {
                Button("OK") { csvErrorMessage = nil }
            } message: {
                Text(csvErrorMessage ?? "")
            }
            .toolbar {
                ToolbarItem(id: "dup-cust-cancel", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "dup-cust-save", placement: .topBarTrailing) {
                    Button("Save") {
                        let copy = Customer(
                            name: name,
                            company: company,
                            contactNumber: contactNumber,
                            address: address,
                            postcode: postcode,
                            state: state,
                            country: country,
                            customerTypeRawValue: customerType.rawValue
                        )
                        copy.email = email.trimmingCharacters(in: .whitespaces)
                        copy.whatsappNumber = whatsappNumber.trimmingCharacters(in: .whitespaces)
                        modelContext.insert(copy)
                        try? modelContext.save()
                        onCreated?(copy)
                        dismiss()
                    }
                    .disabled(name.isEmpty || company.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
        }
        .presentationSizing(.page)
    }

    private func handleCSVImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let err):
            csvErrorMessage = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let rows = OrderCSVRow.parse(csvText: text)
                if rows.isEmpty {
                    csvErrorMessage = "No rows with Parent Name / Mobile / Address found in this CSV."
                    return
                }
                if rows.count == 1 {
                    apply(rows[0])
                } else {
                    pendingRows = rows
                    showRowPicker = true
                }
            } catch {
                csvErrorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ row: OrderCSVRow) {
        if !row.parentName.isEmpty     { name = row.parentName }
        if !row.parentMobile.isEmpty   { contactNumber = row.parentMobile }
        if !row.address.isEmpty        { address = row.address }
    }
}

// MARK: - Order CSV Row + Parser
// Represents one row from the school orders CSV. Only the fields the
// Duplicate Customer sheet needs are exposed; the rest is retained for the
// picker sheet so the user can identify the right row.
struct OrderCSVRow: Identifiable {
    let id = UUID()
    let orderRef: String
    let date: String
    let school: String
    let studentName: String
    let parentName: String
    let parentMobile: String
    let address: String

    static func parse(csvText: String) -> [OrderCSVRow] {
        let lines = csvText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard let headerLine = lines.first else { return [] }
        let headers = splitCSVLine(headerLine)
        func idx(_ key: String) -> Int? { headers.firstIndex(of: key) }
        let orderRefI     = idx("Order Ref")
        let dateI         = idx("Date")
        let schoolI       = idx("School")
        let studentI      = idx("Student Name")
        let parentNameI   = idx("Parent Name")
        let parentMobileI = idx("Parent Mobile")
        let addressI      = idx("Address")

        return lines.dropFirst().compactMap { line in
            let fields = splitCSVLine(line)
            func at(_ i: Int?) -> String {
                guard let i, i < fields.count else { return "" }
                return fields[i].trimmingCharacters(in: .whitespaces)
            }
            let row = OrderCSVRow(
                orderRef:     at(orderRefI),
                date:         at(dateI),
                school:       at(schoolI),
                studentName:  at(studentI),
                parentName:   at(parentNameI),
                parentMobile: at(parentMobileI),
                address:      at(addressI)
            )
            // Skip rows where all three imported fields are empty.
            if row.parentName.isEmpty && row.parentMobile.isEmpty && row.address.isEmpty {
                return nil
            }
            return row
        }
    }

    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }
}

// MARK: - Row Picker Sheet
// Shown when the imported CSV has more than one row. Rows matching the
// current customer's company (school) are listed first so the user can
// spot the right parent quickly.
struct OrderCSVRowPickerSheet: View {
    let rows: [OrderCSVRow]
    let preferredCompany: String
    var onPick: (OrderCSVRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var sortedRows: [OrderCSVRow] {
        let filtered: [OrderCSVRow]
        if searchText.isEmpty {
            filtered = rows
        } else {
            filtered = rows.filter { r in
                [r.parentName, r.studentName, r.school, r.orderRef, r.parentMobile]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(searchText)
            }
        }
        guard !preferredCompany.isEmpty else { return filtered }
        return filtered.sorted { a, b in
            let aMatch = a.school.localizedCaseInsensitiveContains(preferredCompany)
            let bMatch = b.school.localizedCaseInsensitiveContains(preferredCompany)
            if aMatch == bMatch { return a.parentName < b.parentName }
            return aMatch && !bMatch
        }
    }

    var body: some View {
        NavigationStack {
            List(sortedRows) { row in
                Button {
                    onPick(row)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.parentName.isEmpty ? "(no parent name)" : row.parentName)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            if !row.parentMobile.isEmpty {
                                Text(row.parentMobile).font(.footnote).foregroundColor(.secondary)
                            }
                        }
                        if !row.studentName.isEmpty {
                            Text("Student: \(row.studentName)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if !row.school.isEmpty {
                            Text(row.school).font(.caption).foregroundColor(.secondary)
                        }
                        if !row.orderRef.isEmpty {
                            Text(row.orderRef).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search parent, student, school…")
            .navigationTitle("Select Parent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Duplicate Vendor Sheet
struct DuplicateVendorSheet: View {
    let original: Vendor
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var anyFocused: Bool

    @State private var name = ""
    @State private var contactNumber = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Company").foregroundColor(.secondary)
                        Spacer()
                        Text(original.company).foregroundColor(.primary)
                    }
                } header: {
                    Text("Duplicating from \(original.name)")
                } footer: {
                    Text("Company, address and notes are copied. Enter the new contact's details below.")
                }

                Section("New Contact Details") {
                    TextField("Contact Name", text: $name).focused($anyFocused)
                    TextField("Phone Number", text: $contactNumber)
                        .keyboardType(.phonePad).focused($anyFocused)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($anyFocused)
                }
            }
            .navigationTitle("Add 2nd Contact")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = ""; contactNumber = original.contactNumber; email = original.email }
            .toolbar {
                ToolbarItem(id: "dup-vend-cancel", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "dup-vend-save", placement: .topBarTrailing) {
                    Button("Save") {
                        let copy = Vendor(
                            name: name.isEmpty ? original.name + " (2)" : name,
                            company: original.company,
                            contactNumber: contactNumber,
                            address: original.address,
                            postcode: original.postcode,
                            state: original.state,
                            country: original.country,
                            email: email,
                            notes: original.notes
                        )
                        modelContext.insert(copy)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { anyFocused = false }
                }
            }
        }
        .presentationSizing(.page)
    }
}
