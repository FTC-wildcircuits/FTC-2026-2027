//
//  Models.swift
//  FTCTeamHub
//
//  Production SwiftData models for the FTC Team Management platform.
//  SwiftData is used (iOS 17+) instead of raw CoreData for less boilerplate
//  while keeping full relational, queryable, sync-ready persistence.
//
//  Design notes:
//  - Every mutable entity carries `authorID` + `timestamp` for contribution
//    tracking (mandate #2).
//  - Enums are `String, Codable, CaseIterable` so they persist cleanly in
//    SwiftData AND round-trip through any future REST/GraphQL backend.
//  - Relationships use SwiftData's `@Relationship` with explicit delete
//    rules to avoid orphaned records once real multi-user sync lands.
//

import Foundation
import SwiftData

// MARK: - Identity & Roles

/// The functional role of a team member. Drives default dashboard filters
/// and permission gating (e.g. only Strategy can lock the picklist).
enum TeamRole: String, Codable, CaseIterable, Identifiable {
    case software = "Software"
    case hardware = "Hardware"
    case strategy = "Strategy"
    case scouter  = "Scouter"
    case outreach = "Outreach"
    case mentor   = "Mentor"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .software: return "chevron.left.forwardslash.chevron.right"
        case .hardware: return "wrench.and.screwdriver"
        case .strategy: return "chart.bar.xaxis"
        case .scouter:  return "binoculars"
        case .outreach: return "megaphone"
        case .mentor:   return "person.badge.shield.checkmark"
        }
    }
}

/// AppUser is the root identity record. In production this row is created
/// on first sign-in (Firebase Auth / Supabase / CloudKit user record) and
/// `authKey` stores the provider's stable UID — never a password.
@Model
final class AppUser {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: TeamRole
    /// Opaque identifier from the auth provider (Firebase UID, Supabase sub,
    /// or CKRecord.ID). Never store credentials here.
    var authKey: String
    var teamNumber: Int
    var joinedAt: Date
    /// Cached small avatar (SF Symbol name fallback if no photo uploaded).
    var avatarSymbolName: String

    init(id: UUID = UUID(),
         name: String,
         role: TeamRole,
         authKey: String,
         teamNumber: Int,
         joinedAt: Date = .now,
         avatarSymbolName: String = "person.crop.circle.fill") {
        self.id = id
        self.name = name
        self.role = role
        self.authKey = authKey
        self.teamNumber = teamNumber
        self.joinedAt = joinedAt
        self.avatarSymbolName = avatarSymbolName
    }
}

// MARK: - Tasks & Kanban

enum TaskPriority: String, Codable, CaseIterable, Comparable, Identifiable {
    case low = "Low", medium = "Medium", high = "High", critical = "Critical"
    var id: String { rawValue }

    private var sortWeight: Int {
        switch self { case .low: 0; case .medium: 1; case .high: 2; case .critical: 3 }
    }
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool { lhs.sortWeight < rhs.sortWeight }

    var tint: String {
        switch self {
        case .low: return "systemGray"
        case .medium: return "systemBlue"
        case .high: return "systemOrange"
        case .critical: return "systemRed"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case toDo = "To Do", inProgress = "In Progress", blocked = "Blocked", done = "Done"
    var id: String { rawValue }
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var taskDescription: String
    /// Denormalized name for fast list rendering without a join.
    var assigneeName: String
    var assigneeID: UUID?
    var status: TaskStatus
    var priority: TaskPriority
    var deadline: Date?
    var tags: [String]
    var dateCreated: Date
    var authorID: UUID
    var lastModified: Date

    init(id: UUID = UUID(),
         title: String,
         taskDescription: String = "",
         assigneeName: String,
         assigneeID: UUID? = nil,
         status: TaskStatus = .toDo,
         priority: TaskPriority = .medium,
         deadline: Date? = nil,
         tags: [String] = [],
         dateCreated: Date = .now,
         authorID: UUID,
         lastModified: Date = .now) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.assigneeName = assigneeName
        self.assigneeID = assigneeID
        self.status = status
        self.priority = priority
        self.deadline = deadline
        self.tags = tags
        self.dateCreated = dateCreated
        self.authorID = authorID
        self.lastModified = lastModified
    }
}

// MARK: - Engineering Notebook

/// FTC-specific structured payload for autonomous test runs.
/// Kept as a lightweight Codable struct stored on the entry rather than a
/// separate @Model, since it's always 1:1 with a single notebook entry.
struct AutonomousTestLog: Codable, Hashable {
    var routineName: String
    var startingPosition: String
    var samplesOrSpecimensScored: Int
    var cycleTimeSeconds: Double
    var successRatePercent: Double
    var failureNotes: String
}

/// REV Control Hub configuration snapshot — useful when debugging
/// intermittent hardware faults across firmware/OS versions.
struct ControlHubConfigLog: Codable, Hashable {
    var controlHubOSVersion: String
    var sdkVersion: String
    var expansionHubCount: Int
    var motorPortMap: [String: String]   // e.g. ["0": "leftFront"]
    var servoPortMap: [String: String]
}

/// BHI260AP / BNO055 IMU tuning parameters. See FTC universal IMU interface
/// docs for the underlying `RevHubOrientationOnRobot` fields these mirror.
struct IMUTuningLog: Codable, Hashable {
    var chip: String              // "BHI260AP" or "BNO055"
    var logoFacingDirection: String
    var usbFacingDirection: String
    var yawOffsetDegrees: Double
    var driftOverTenMinDegrees: Double
    var calibrationNotes: String
}

enum NotebookTemplate: String, CaseIterable, Identifiable {
    case blank = "Blank Entry"
    case softwareLog = "Software Log"
    case hardwareLog = "Hardware Log"
    case autonomousTest = "Autonomous Routine Test"
    case controlHubConfig = "Control Hub Config"
    case imuTuning = "IMU Tuning (BHI260AP)"
    var id: String { rawValue }
}

@Model
final class NotebookEntry {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var authorName: String
    var title: String
    /// Raw Markdown source — rendered via `Text(markdown:)` / AttributedString.
    var content: String
    var tags: [String]
    var timestamp: Date

    // Optional structured, FTC-specific payloads (nil unless that template used)
    var autonomousLog: AutonomousTestLog?
    var hubConfigLog: ControlHubConfigLog?
    var imuLog: IMUTuningLog?

    /// Local filenames of attached media (CAD screenshots, wiring diagrams,
    /// whiteboard photos). Files live in the app's Documents/Attachments
    /// directory and sync via the backend's blob storage in production.
    var attachmentFileNames: [String]

    init(id: UUID = UUID(),
         authorID: UUID,
         authorName: String,
         title: String,
         content: String = "",
         tags: [String] = [],
         timestamp: Date = .now,
         autonomousLog: AutonomousTestLog? = nil,
         hubConfigLog: ControlHubConfigLog? = nil,
         imuLog: IMUTuningLog? = nil,
         attachmentFileNames: [String] = []) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.title = title
        self.content = content
        self.tags = tags
        self.timestamp = timestamp
        self.autonomousLog = autonomousLog
        self.hubConfigLog = hubConfigLog
        self.imuLog = imuLog
        self.attachmentFileNames = attachmentFileNames
    }
}

// MARK: - Scouting

@Model
final class ScoutingRecord {
    @Attribute(.unique) var id: UUID
    var matchNumber: Int
    var teamScouted: Int          // FTC team number being scouted
    var authorID: UUID
    var authorName: String
    var autoScore: Int
    var teleopScore: Int
    var endgameScore: Int
    var autoSamplesOrSpecimens: Int
    var teleopCycles: Int
    var driverRating: Int          // 1...5 subjective rating
    var notes: String
    var timestamp: Date

    init(id: UUID = UUID(),
         matchNumber: Int,
         teamScouted: Int,
         authorID: UUID,
         authorName: String,
         autoScore: Int = 0,
         teleopScore: Int = 0,
         endgameScore: Int = 0,
         autoSamplesOrSpecimens: Int = 0,
         teleopCycles: Int = 0,
         driverRating: Int = 3,
         notes: String = "",
         timestamp: Date = .now) {
        self.id = id
        self.matchNumber = matchNumber
        self.teamScouted = teamScouted
        self.authorID = authorID
        self.authorName = authorName
        self.autoScore = autoScore
        self.teleopScore = teleopScore
        self.endgameScore = endgameScore
        self.autoSamplesOrSpecimens = autoSamplesOrSpecimens
        self.teleopCycles = teleopCycles
        self.driverRating = driverRating
        self.notes = notes
        self.timestamp = timestamp
    }

    var totalScore: Int { autoScore + teleopScore + endgameScore }
}

/// One picklist entry — a curated tier assigned to a scouted team, derived
/// from (but independent of) raw ScoutingRecords, so Strategy can override
/// the algorithmic ranking during alliance selection.
@Model
final class PicklistEntry {
    @Attribute(.unique) var id: UUID
    var teamNumber: Int
    var teamName: String
    var tier: Int              // 1 = first pick, 2 = second pick, etc.
    var averageOPR: Double
    var notes: String
    var lastEditedBy: UUID
    var lastEditedAt: Date

    init(id: UUID = UUID(),
         teamNumber: Int,
         teamName: String,
         tier: Int,
         averageOPR: Double = 0,
         notes: String = "",
         lastEditedBy: UUID,
         lastEditedAt: Date = .now) {
        self.id = id
        self.teamNumber = teamNumber
        self.teamName = teamName
        self.tier = tier
        self.averageOPR = averageOPR
        self.notes = notes
        self.lastEditedBy = lastEditedBy
        self.lastEditedAt = lastEditedAt
    }
}

// MARK: - Ideas & Whiteboard

struct IdeaComment: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var authorID: UUID
    var authorName: String
    var text: String
    var timestamp: Date = .now
}

@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var authorName: String
    var summary: String
    var detail: String
    var upvoterIDs: [UUID]
    var comments: [IdeaComment]
    var timestamp: Date
    /// Local filename of an optional PencilKit sketch attached to this idea.
    var sketchFileName: String?
    var promotedToTask: Bool

    init(id: UUID = UUID(),
         authorID: UUID,
         authorName: String,
         summary: String,
         detail: String = "",
         upvoterIDs: [UUID] = [],
         comments: [IdeaComment] = [],
         timestamp: Date = .now,
         sketchFileName: String? = nil,
         promotedToTask: Bool = false) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.summary = summary
        self.detail = detail
        self.upvoterIDs = upvoterIDs
        self.comments = comments
        self.timestamp = timestamp
        self.sketchFileName = sketchFileName
        self.promotedToTask = promotedToTask
    }

    var upvoteCount: Int { upvoterIDs.count }
}

// MARK: - Activity Log

enum ActivityKind: String, Codable {
    case taskCompleted, taskCreated, scoutingSubmitted, ideaPosted, ideaUpvoted, notebookEntry, picklistUpdated
}

@Model
final class ActivityEvent {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var authorName: String
    var kind: ActivityKind
    var message: String
    var timestamp: Date

    init(id: UUID = UUID(),
         authorID: UUID,
         authorName: String,
         kind: ActivityKind,
         message: String,
         timestamp: Date = .now) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.kind = kind
        self.message = message
        self.timestamp = timestamp
    }

    var systemImage: String {
        switch kind {
        case .taskCompleted: return "checkmark.circle.fill"
        case .taskCreated: return "plus.circle"
        case .scoutingSubmitted: return "binoculars.fill"
        case .ideaPosted: return "lightbulb.fill"
        case .ideaUpvoted: return "hand.thumbsup.fill"
        case .notebookEntry: return "book.closed.fill"
        case .picklistUpdated: return "list.number"
        }
    }
}
