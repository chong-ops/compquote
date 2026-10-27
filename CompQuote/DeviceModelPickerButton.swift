//
//  DeviceModelPickerButton.swift
//  CompQuote
//
//  Created by Chong Zte Siang on 09/06/2026.
//


import SwiftUI

// MARK: - Standard device list
// Users can add custom entries which are saved to UserDefaults
private let standardDevices: [String: [String]] = [
    "Mac" : [
        "MacBook Pro 13\"",
        "MacBook Pro 14\"",
        "MacBook Pro 16\"",
        "MacBook Air 13\"",
        "MacBook Air 15\"",
        "iMac 24\"",
        "Mac mini",
        "Mac Studio",
        "Mac Pro",
    ],
    "iPad" : [
        "iPad Pro 11\"",
        "iPad Pro 13\"",
        "iPad Air 11\"",
        "iPad Air 13\"",
        "iPad mini",
        "iPad (Standard)",
    ],
    "iPhone" : [
        "iPhone 16 Pro Max",
        "iPhone 16 Pro",
        "iPhone 16 Plus",
        "iPhone 16",
        "iPhone 15 Pro Max",
        "iPhone 15 Pro",
        "iPhone 15 Plus",
        "iPhone 15",
        "iPhone 14",
        "iPhone SE",
    ],
    "Other" : [
        "Apple Watch",
        "AirPods",
        "AirPods Pro",
        "Apple TV",
        "HomePod",
    ]
]

private let standardOrder = ["Mac", "iPad", "iPhone", "Other"]
private let customDevicesKey = "customDeviceModels"
private let showApplePresetsKey = "showApplePresetDevices"

// MARK: - Button shown inline in the form
struct DeviceModelPickerButton: View {
    @Binding var deviceModel: String
    @Binding var showPicker: Bool

    var body: some View {
        Button { showPicker = true } label: {
            HStack {
                Text(deviceModel.isEmpty ? "Select Device Model…" : deviceModel)
                    .foregroundColor(deviceModel.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-screen searchable picker sheet
struct DeviceModelPickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    // Turn off to hide the built-in Apple list and use only your own devices.
    @AppStorage(showApplePresetsKey) private var showApplePresets = true
    @State private var searchText = ""
    @State private var customModels: [String] = []
    @State private var showAddCustom = false
    @State private var newCustomModel = ""

    private var allDevices: [String: [String]] {
        var result = showApplePresets ? standardDevices : [:]
        if !customModels.isEmpty {
            result["Custom"] = customModels
        }
        return result
    }

    private var groupOrder: [String] {
        var order = showApplePresets ? standardOrder : []
        if customModels.isEmpty == false { order.append("Custom") }
        return order
    }

    private var filteredGroups: [(group: String, items: [String])] {
        if searchText.isEmpty {
            return groupOrder.compactMap { group in
                guard let items = allDevices[group], !items.isEmpty else { return nil }
                return (group, items)
            }
        }
        let q = searchText.lowercased()
        return groupOrder.compactMap { group in
            guard let items = allDevices[group] else { return nil }
            let matched = items.filter { $0.lowercased().contains(q) }
            return matched.isEmpty ? nil : (group, matched)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Current selection
                if !selected.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                            Text(selected).fontWeight(.medium)
                            Spacer()
                            Button("Clear") { selected = ""; dismiss() }
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } header: { Text("Current") }
                }

                // Filtered groups
                ForEach(filteredGroups, id: \.group) { group, items in
                    Section(group == "Custom" ? "My Devices" : group) {
                        ForEach(items, id: \.self) { item in
                            Button {
                                selected = item
                                dismiss()
                            } label: {
                                HStack {
                                    Text(item).foregroundColor(.primary)
                                    Spacer()
                                    if selected == item {
                                        Image(systemName: "checkmark").foregroundColor(.blue)
                                    }
                                }
                            }
                            // Your own devices can be removed with a swipe.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if group == "Custom" {
                                    Button(role: .destructive) {
                                        customModels.removeAll { $0 == item }
                                        saveCustom()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                if filteredGroups.isEmpty && searchText.isEmpty {
                    Section {
                        Text("No devices yet. Tap Add Custom Model to add your own.")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }

                // Add custom
                Section {
                    Button {
                        newCustomModel = searchText  // pre-fill with search text
                        showAddCustom = true
                    } label: {
                        Label("Add Custom Model…", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Custom models are saved for future use. Swipe a custom model left to delete it.")
                }

                Section {
                    Toggle("Show Apple device list", isOn: $showApplePresets)
                } footer: {
                    Text("Turn off if you do not service Apple products. Only your own devices will be listed.")
                }
            }
            .searchable(text: $searchText, prompt: "Search device models…")
            .navigationTitle("Device Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "device-done", placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { loadCustom() }
            .alert("Add Custom Model", isPresented: $showAddCustom) {
                TextField("e.g. Mac mini M4 Pro", text: $newCustomModel)
                    .autocorrectionDisabled()
                Button("Add") {
                    let trimmed = newCustomModel.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    if !customModels.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                        customModels.append(trimmed)
                    }
                    saveCustom()
                    selected = trimmed
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the device model name.")
            }
        }
    }

    private func loadCustom() {
        customModels = UserDefaults.standard.stringArray(forKey: customDevicesKey) ?? []
    }

    private func saveCustom() {
        UserDefaults.standard.set(customModels, forKey: customDevicesKey)
    }
}