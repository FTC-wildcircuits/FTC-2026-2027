//
//  PitOpsModels.swift
//  FTCTeamHub
//
//  Data models for the new Pit Ops tab: battery cycle tracking, pre/post
//  flight checklists, and parts/tools inventory with QR labels.
//

import Foundation
import SwiftData

// MARK: - Battery Cycle Tracker

enum BatteryStatus: String, Codable, CaseIterable, Identifiable {
    case charged = "Charged"
    case inUse = "In Use"
    case charging = "Charging"
    case dead = "Dead"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .charged: return "battery.100"
        case .inUse: return "battery.75"
        case .charging: return "battery.100.bolt"
        case .dead: return "battery.0"
        }
    }
}

@Model
final class Battery {
    @Attribute(.unique) var id: UUID
    var label: String              // e.g. "B1"
    var statusRaw: String
    var cycleCount: Int
    var lastChargedAt: Date?
    var notes: String
    var addedAt: Date

    var status: BatteryStatus {
        get { BatteryStatus(rawValue: statusRaw) ?? .charged }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), label: String, status: BatteryStatus = .charged,
         cycleCount: Int = 0, lastChargedAt: Date? = nil, notes: String = "", addedAt: Date = .now) {
        self.id = id
        self.label = label
        self.statusRaw = status.rawValue
        self.cycleCount = cycleCount
        self.lastChargedAt = lastChargedAt
        self.notes = notes
        self.addedAt = addedAt
    }
}

// MARK: - Pre/Post-Flight Checklists

enum ChecklistType: String, Codable, CaseIterable {
    case preFlight = "Pre-Flight"
    case postFlight = "Post-Flight"

    /// Default items shown when starting a new checklist run. Teams can
    /// extend this list later; kept as static constants for now to avoid
    /// adding an editable-template layer before the core feature is proven.
    var defaultItems: [String] {
        switch self {
        case .preFlight:
            return [
                "Set screws tightened",
                "Chains / belts tensioned",
                "Battery voltage checked (12.0V+)",
                "Phone / Control Hub mount secured",
                "Code configuration verified",
                "Bumpers on and legal",
                "Wiring inspected, no loose connectors"
            ]
        case .postFlight:
            return [
                "Battery removed and placed on charger",
                "Field-damage inspection",
                "Loose hardware check",
                "Notes logged for next match"
            ]
        }
    }
}

struct ChecklistItemResult: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var checked: Bool
}

@Model
final class ChecklistRun {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var itemResults: [ChecklistItemResult]
    var completedByID: UUID
    var completedByName: String
    var timestamp: Date

    var type: ChecklistType {
        get { ChecklistType(rawValue: typeRaw) ?? .preFlight }
        set { typeRaw = newValue.rawValue }
    }

    var allChecked: Bool { itemResults.allSatisfy { $0.checked } }

    init(id: UUID = UUID(), type: ChecklistType, itemResults: [ChecklistItemResult],
         completedByID: UUID, completedByName: String, timestamp: Date = .now) {
        self.id = id
        self.typeRaw = type.rawValue
        self.itemResults = itemResults
        self.completedByID = completedByID
        self.completedByName = completedByName
        self.timestamp = timestamp
    }
}

// MARK: - Parts & Tools Inventory

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: String           // free text, e.g. "Electronics", "Printed Parts", "Tools"
    var binLocation: String
    var quantity: Int
    var isCheckedOut: Bool
    var checkedOutByName: String
    var notes: String
    var addedAt: Date

    init(id: UUID = UUID(), name: String, category: String, binLocation: String,
         quantity: Int = 1, isCheckedOut: Bool = false, checkedOutByName: String = "",
         notes: String = "", addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.category = category
        self.binLocation = binLocation
        self.quantity = quantity
        self.isCheckedOut = isCheckedOut
        self.checkedOutByName = checkedOutByName
        self.notes = notes
        self.addedAt = addedAt
    }

    /// The QR label encodes the item's own UUID — scanning it (or just
    /// printing it on a bin/part label) lets you look the item straight up
    /// by ID rather than typing a name.
    var qrPayload: String { "ftcteamhub:item:\(id.uuidString)" }
}
