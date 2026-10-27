//
//  TechnicianPickerButton.swift
//  CompQuote
//
//  Created by Chong Zte Siang on 09/06/2026.
//


import SwiftUI

private let technicianListKey = "savedTechnicians"

// MARK: - Inline button
struct TechnicianPickerButton: View {
    @Binding var technicianName: String
    @Binding var showPicker: Bool

    var body: some View {
        Button { showPicker = true } label: {
            HStack {
                Text(technicianName.isEmpty ? "Select Technician…" : technicianName)
                    .foregroundColor(technicianName.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Picker sheet
struct TechnicianPickerSheet: View {
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss

    @State private var technicians: [String] = []
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var newName = ""
    @State private var deleteMode = false

    private var filtered: [String] {
        guard !searchText.isEmpty else { return technicians }
        return technicians.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                // Current selection
                if !selected.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: "person.fill.checkmark").foregroundColor(.blue)
                            Text(selected).fontWeight(.medium)
                            Spacer()
                            Button("Clear") { selected = ""; dismiss() }
                                .font(.caption).foregroundColor(.secondary)
                        }
                    } header: { Text("Current") }
                }

                // Technician list
                if filtered.isEmpty && searchText.isEmpty {
                    Section {
                        Text("No technicians added yet.")
                            .foregroundColor(.secondary).font(.subheadline)
                    }
                } else {
                    Section("Technicians") {
                        ForEach(filtered, id: \.self) { name in
                            Button {
                                selected = name
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "person.circle")
                                        .foregroundColor(.secondary)
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if selected == name {
                                        Image(systemName: "checkmark").foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            technicians.remove(atOffsets: idx)
                            save()
                        }
                    }
                }

                // Add new
                Section {
                    Button {
                        newName = searchText
                        showAdd = true
                    } label: {
                        Label("Add Technician…", systemImage: "plus.circle")
                    }
                } footer: {
                    Text("Swipe left to remove a technician from the list.")
                }
            }
            .searchable(text: $searchText, prompt: "Search technicians…")
            .navigationTitle("Technician")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(id: "tech-cancel", placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(id: "tech-edit", placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .onAppear { load() }
            .alert("Add Technician", isPresented: $showAdd) {
                TextField("Full name", text: $newName).autocorrectionDisabled()
                Button("Add") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, !technicians.contains(name) else { return }
                    technicians.append(name)
                    technicians.sort()
                    save()
                    selected = name
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the technician's name.")
            }
        }
    }

    private func load() {
        technicians = UserDefaults.standard.stringArray(forKey: technicianListKey) ?? []
    }
    private func save() {
        UserDefaults.standard.set(technicians, forKey: technicianListKey)
    }
}