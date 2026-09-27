//
//  ScoringModels.swift
//  FTCTeamHub
//
//  Backing model for the Scoring Simulator. Point values are fully
//  user-configurable rather than hardcoded, since official numbers
//  change every season — teams enter their own once the current Game
//  Manual is released, and the calculator keeps working for future
//  seasons without an app update.
//

import Foundation
import SwiftData

enum ScoringPhase: String, Codable, CaseIterable, Identifiable {
    case autonomous = "Autonomous"
    case teleop = "TeleOp"
    case endgame = "Endgame"
    var id: String { rawValue }
}

@Model
final class ScoringElement {
    @Attribute(.unique) var id: UUID
    var name: String
    var phaseRaw: String
    var pointValue: Int
    var sortOrder: Int

    var phase: ScoringPhase {
        get { ScoringPhase(rawValue: phaseRaw) ?? .autonomous }
        set { phaseRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, phase: ScoringPhase, pointValue: Int = 0, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.phaseRaw = phase.rawValue
        self.pointValue = pointValue
        self.sortOrder = sortOrder
    }
}
