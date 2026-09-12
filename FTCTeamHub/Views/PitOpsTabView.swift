//
//  PitOpsTabView.swift
//  FTCTeamHub
//
//  NEW: Inventory section now has a dedicated "Scan" button that opens
//  the camera-based QR check-in/check-out flow (QRCheckInOutView).
//

import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins
import UIKit

struct PitOpsTabView: View {
    @State private var section: Section = .batteries

    enum Section: String, CaseIterable, Identifiable {
        case batteries = "Batteries", checklists = "Checklists", inventory = "Inventory"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch section {
                case .batteries: BatteryListView()
                case .checklists: ChecklistsView()
                case .inventory: InventoryListView()
                }
            }
            .navigationTitle("Pit Ops")
        }
    }
}

// MARK: - Batteries

private struct BatteryListView: View {
    @Query(sort: \Battery.label) private var batteries: [Battery]
    @Query private var allTestRuns: [TestRunRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var isPresentingNewBattery = false

    var body: some View {
        List {
            if batteries.isEmpty {
                EmptyStateView(icon: "battery.100", title: "No batteries tracked",
                               subtitle: "Add your team's batteries to start tracking cycles and performance.",
                               tint: .green, actionTitle: "Add Battery") { isPresentingNewBattery = true }
                    .listRowSeparator(.hidden)
            }
            ForEach(batteries) { battery in
                NavigationLink {
                    BatteryDetailView(battery: battery, runsUsingThisBattery: allTestRuns.filter { $0.batteryLabel == battery.label })
                } label: {
                    BatteryRow(battery: battery)
                }
            }
            Section {
                Button { isPresentingNewBattery = true } label: {
                    Label("Add Battery", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $isPresentingNewBattery) { NewBatterySheet() }
    }
}

private struct BatteryRow: View {
    @Bindable var battery: Battery
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    private var statusColor: Color {
        switch battery.status {
        case .charged: return .green
        case .inUse: return .blue
        case .charging: return .orange
        case .dead: return .red
        }
    }

    var body: some View {
        HStack {
            Image(systemName: battery.status.systemImage)
                .foregroundStyle(statusColor)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(battery.label).font(.body.weight(.semibold))
                Text("\(battery.cycleCount) cycles").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(BatteryStatus.allCases) { status in
                    Button(status.rawValue) { setStatus(status) }
                }
            } label: {
                Text(battery.status.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 2)
    }

    private func setStatus(_ status: BatteryStatus) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        battery.status = status
        if status == .charged { battery.lastChargedAt = .now }
        if status == .inUse { battery.cycleCount += 1 }
        syncService?.pushBattery(battery)

        if let user = authManager.currentUser {
            let event = ActivityEvent(authorID: user.id, authorName: user.name, kind: .batteryStatusChanged,
                                       message: "marked battery \(battery.label) as \(status.rawValue)")
            context.insert(event)
            syncService?.pushActivity(event)
        }
    }
}

private struct BatteryDetailView: View {
    let battery: Battery
    let runsUsingThisBattery: [TestRunRecord]

    private var averageTotalScore: Double {
        guard !runsUsingThisBattery.isEmpty else { return 0 }
        let total = runsUsingThisBattery.reduce(0) { $0 + $1.totalScore }
        return Double(total) / Double(runsUsingThisBattery.count)
    }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Status", value: battery.status.rawValue)
                LabeledContent("Cycle count", value: "\(battery.cycleCount)")
                if let lastCharged = battery.lastChargedAt {
                    LabeledContent("Last charged", value: lastCharged.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("Performance (\(runsUsingThisBattery.count) run\(runsUsingThisBattery.count == 1 ? "" : "s"))") {
                if runsUsingThisBattery.isEmpty {
                    Text("No test runs logged with this battery yet.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Avg total score", value: String(format: "%.1f", averageTotalScore))
                    if battery.cycleCount > 30 && averageTotalScore < 40 {
                        Label("High cycle count with low scores — consider retiring this cell.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            if !battery.notes.isEmpty {
                Section("Notes") { Text(battery.notes) }
            }
        }
        .navigationTitle(battery.label)
    }
}

private struct NewBatterySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @State private var label = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label (e.g. B1)", text: $label)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("New Battery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(label.isEmpty)
                }
            }
        }
    }

    private func save() {
        let battery = Battery(label: label, notes: notes)
        context.insert(battery)
        syncService?.pushBattery(battery)
        dismiss()
    }
}

// MARK: - Checklists

private struct ChecklistsView: View {
    @Query(sort: \ChecklistRun.timestamp, order: .reverse) private var runs: [ChecklistRun]
    @State private var activeChecklistType: ChecklistType?

    var body: some View {
        List {
            Section {
                ForEach(ChecklistType.allCases, id: \.self) { type in
                    Button {
                        activeChecklistType = type
                    } label: {
                        Label("Start \(type.rawValue) Checklist", systemImage: type.systemImage)
                    }
                }
            }

            Section("Recent Checklists") {
                if runs.isEmpty {
                    Text("No checklists completed yet.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(runs) { run in
                    HStack {
                        Image(systemName: run.allChecked ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(run.allChecked ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.type.rawValue).font(.subheadline.weight(.medium))
                            Text("\(run.completedByName) · \(run.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $activeChecklistType) { type in
            ChecklistRunSheet(type: type)
        }
    }
}

extension ChecklistType: Identifiable {
    public var id: String { rawValue }
}

private struct ChecklistRunSheet: View {
    let type: ChecklistType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var checkedStates: [Bool]

    init(type: ChecklistType) {
        self.type = type
        _checkedStates = State(initialValue: Array(repeating: false, count: type.defaultItems.count))
    }

    private var allChecked: Bool { checkedStates.allSatisfy { $0 } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(type.defaultItems.enumerated()), id: \.offset) { index, item in
                    Button {
                        checkedStates[index].toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Image(systemName: checkedStates[index] ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checkedStates[index] ? .green : .secondary)
                            Text(item).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle(type.rawValue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !allChecked {
                    Text("All items should be checked before the robot leaves the pit.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
        }
    }

    private func submit() {
        guard let user = authManager.currentUser else { return }
        let results = zip(type.defaultItems, checkedStates).map { ChecklistItemResult(text: $0, checked: $1) }
        let run = ChecklistRun(type: type, itemResults: results, completedByID: user.id, completedByName: user.name)
        context.insert(run)
        syncService?.pushChecklistRun(run)

        let event = ActivityEvent(authorID: user.id, authorName: user.name, kind: .checklistCompleted,
                                   message: "completed \(type.rawValue) checklist" + (allChecked ? "" : " (incomplete)"))
        context.insert(event)
        syncService?.pushActivity(event)

        UINotificationFeedbackGenerator().notificationOccurred(allChecked ? .success : .warning)
        dismiss()
    }
}

// MARK: - Inventory

private struct InventoryListView: View {
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]
    @State private var isPresentingNewItem = false
    @State private var isPresentingScanner = false

    var body: some View {
        List {
            if items.isEmpty {
                EmptyStateView(icon: "shippingbox", title: "No items tracked",
                               subtitle: "Log expensive or easy-to-lose parts here.",
                               tint: .orange, actionTitle: "Add Item") { isPresentingNewItem = true }
                    .listRowSeparator(.hidden)
            }
            ForEach(items) { item in
                NavigationLink {
                    InventoryDetailView(item: item)
                } label: {
                    InventoryRow(item: item)
                }
            }
            Section {
                Button { isPresentingNewItem = true } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingScanner = true } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewItem) { NewInventoryItemSheet() }
        .fullScreenCover(isPresented: $isPresentingScanner) { QRCheckInOutView() }
    }
}

private struct InventoryRow: View {
    let item: InventoryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text("\(item.category) · Bin \(item.binLocation)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.isCheckedOut {
                Text("Checked out")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct InventoryDetailView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Category", value: item.category)
                LabeledContent("Bin location", value: item.binLocation)
                LabeledContent("Quantity", value: "\(item.quantity)")
                if !item.notes.isEmpty { LabeledContent("Notes", value: item.notes) }
            }

            Section("QR Label") {
                if let qrImage = QRCodeGenerator.generate(from: item.qrPayload) {
                    HStack {
                        Spacer()
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 160, height: 160)
                        Spacer()
                    }
                    ShareLink(item: Image(uiImage: qrImage), preview: SharePreview("\(item.name) QR Label", image: Image(uiImage: qrImage))) {
                        Label("Print / Share Label", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button {
                    toggleCheckout()
                } label: {
                    Label(item.isCheckedOut ? "Check In" : "Check Out", systemImage: item.isCheckedOut ? "arrow.uturn.down" : "arrow.up.right")
                }
            }
        }
        .navigationTitle(item.name)
    }

    private func toggleCheckout() {
        guard let user = authManager.currentUser else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        item.isCheckedOut.toggle()
        item.checkedOutByName = item.isCheckedOut ? user.name : ""
        syncService?.pushInventoryItem(item)

        let event = ActivityEvent(authorID: user.id, authorName: user.name, kind: .inventoryUpdated,
                                   message: item.isCheckedOut ? "checked out: \(item.name)" : "returned: \(item.name)")
        context.insert(event)
        syncService?.pushActivity(event)
    }
}

private struct NewInventoryItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @State private var name = ""
    @State private var category = ""
    @State private var binLocation = ""
    @State private var quantity = 1
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Category (e.g. Electronics)", text: $category)
                TextField("Bin location (e.g. Shelf 2, Bin B)", text: $binLocation)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...100)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("New Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        let item = InventoryItem(name: name, category: category.isEmpty ? "Uncategorized" : category,
                                  binLocation: binLocation, quantity: quantity, notes: notes)
        context.insert(item)
        syncService?.pushInventoryItem(item)
        dismiss()
    }
}

// MARK: - QR generation helper

enum QRCodeGenerator {
    static func generate(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return PitOpsTabView()
        .modelContainer(container)
        .environment(authManager)
}
