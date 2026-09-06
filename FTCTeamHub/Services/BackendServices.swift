//
//  BackendServices.swift
//  FTCTeamHub
//
//  Auth + real-time sync abstraction layer, plus CSV export and rich sample
//  data used by SwiftUI previews and first-run demo mode.
//
//  Why a protocol-first design: the mandate lists Firebase Auth, Supabase,
//  or CloudKit as acceptable backends. Rather than hard-wiring one, every
//  ViewModel talks to `AuthServicing` / `SyncServicing`. Swap
//  `MockBackendService` for `FirebaseBackendService` or
//  `CloudKitBackendService` later without touching a single View.
//

import Foundation
import SwiftData
import Combine

// MARK: - Auth abstraction (Open/Closed: add providers without editing callers)

protocol AuthServicing: AnyObject {
    var currentUser: AppUser? { get }
    var currentUserPublisher: AnyPublisher<AppUser?, Never> { get }
    func signIn(name: String, role: TeamRole, teamNumber: Int) async throws -> AppUser
    func signOut()
}

// MARK: - Real-time sync abstraction

/// Represents "a change happened, tell everyone." A real implementation
/// (Firebase Firestore listeners, Supabase Realtime channels, or
/// CKQuerySubscription) publishes on this stream; every ModelContext-backed
/// view simply re-fetches from SwiftData when a matching event arrives.
protocol SyncServicing: AnyObject {
    var remoteChangePublisher: AnyPublisher<SyncChangeEvent, Never> { get }
    func broadcastActivity(_ event: ActivityEvent) async
}

struct SyncChangeEvent {
    enum Entity { case task, notebook, scouting, idea, activity, picklist }
    let entity: Entity
    let changedBy: UUID
}

// MARK: - Mock implementation (in-memory, deterministic — safe for previews & CI)

@MainActor
final class MockBackendService: AuthServicing, SyncServicing, ObservableObject {

    static let shared = MockBackendService()

    @Published private(set) var currentUser: AppUser?
    var currentUserPublisher: AnyPublisher<AppUser?, Never> { $currentUser.eraseToAnyPublisher() }

    private let changeSubject = PassthroughSubject<SyncChangeEvent, Never>()
    var remoteChangePublisher: AnyPublisher<SyncChangeEvent, Never> { changeSubject.eraseToAnyPublisher() }

    func signIn(name: String, role: TeamRole, teamNumber: Int) async throws -> AppUser {
        // Simulate network latency of a real auth round trip.
        try await Task.sleep(nanoseconds: 250_000_000)
        let user = AppUser(name: name, role: role, authKey: UUID().uuidString, teamNumber: teamNumber)
        currentUser = user
        return user
    }

    func signOut() {
        currentUser = nil
    }

    func broadcastActivity(_ event: ActivityEvent) async {
        changeSubject.send(SyncChangeEvent(entity: .activity, changedBy: event.authorID))
    }
}

// MARK: - CSV Export (Scouting → spreadsheet, mandate #3 Tab 1)

enum ScoutingCSVExporter {
    /// Produces RFC 4180-safe CSV text for one-tap export/share sheet.
    static func csv(from records: [ScoutingRecord]) -> String {
        var lines = ["MatchNumber,TeamScouted,Author,AutoScore,TeleopScore,EndgameScore,TotalScore,AutoSamplesOrSpecimens,TeleopCycles,DriverRating,Notes,Timestamp"]
        let formatter = ISO8601DateFormatter()
        for r in records.sorted(by: { $0.matchNumber < $1.matchNumber }) {
            let safeNotes = "\"\(r.notes.replacingOccurrences(of: "\"", with: "\"\""))\""
            let row = [
                "\(r.matchNumber)", "\(r.teamScouted)", r.authorName,
                "\(r.autoScore)", "\(r.teleopScore)", "\(r.endgameScore)", "\(r.totalScore)",
                "\(r.autoSamplesOrSpecimens)", "\(r.teleopCycles)", "\(r.driverRating)",
                safeNotes, formatter.string(from: r.timestamp)
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    /// Writes CSV to a temp file and returns its URL, ready for `ShareLink`.
    static func writeTempFile(records: [ScoutingRecord]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("scouting_export_\(Int(Date().timeIntervalSince1970)).csv")
        try csv(from: records).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Sample / Preview Data

@MainActor
enum PreviewData {

    static let alex = AppUser(name: "Alex Rivera", role: .software, authKey: "u1", teamNumber: 24211)
    static let sam = AppUser(name: "Sam Okafor", role: .hardware, authKey: "u2", teamNumber: 24211)
    static let priya = AppUser(name: "Priya Nandan", role: .strategy, authKey: "u3", teamNumber: 24211)
    static let jordan = AppUser(name: "Jordan Lee", role: .scouter, authKey: "u4", teamNumber: 24211)

    static var users: [AppUser] { [alex, sam, priya, jordan] }

    static var tasks: [TaskItem] {
        [
            TaskItem(title: "Mount odometry pods", taskDescription: "Finalize bracket for dead-wheel pods on drivetrain.",
                      assigneeName: sam.name, assigneeID: sam.id, status: .inProgress, priority: .high,
                      deadline: Calendar.current.date(byAdding: .day, value: 2, to: .now),
                      tags: ["Hardware", "Drivetrain"], authorID: priya.id),
            TaskItem(title: "Tune PID for arm subsystem", taskDescription: "Reduce overshoot below 3 degrees.",
                      assigneeName: alex.name, assigneeID: alex.id, status: .toDo, priority: .critical,
                      deadline: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                      tags: ["Software", "Controls"], authorID: alex.id),
            TaskItem(title: "Scout Week 1 quals", taskDescription: "Cover all qualification matches.",
                      assigneeName: jordan.name, assigneeID: jordan.id, status: .done, priority: .medium,
                      tags: ["Scouting"], authorID: jordan.id),
            TaskItem(title: "Finalize sponsor outreach packet", taskDescription: "PDF + email list.",
                      assigneeName: priya.name, assigneeID: priya.id, status: .blocked, priority: .low,
                      tags: ["Outreach"], authorID: priya.id)
        ]
    }

    static var notebookEntries: [NotebookEntry] {
        [
            NotebookEntry(authorID: alex.id, authorName: alex.name, title: "IMU drift investigation",
                          content: "## Summary\nObserved yaw drift after 8 minutes of continuous operation.",
                          tags: ["Software", "IMU"],
                          imuLog: IMUTuningLog(chip: "BHI260AP", logoFacingDirection: "UP", usbFacingDirection: "FORWARD",
                                               yawOffsetDegrees: 1.2, driftOverTenMinDegrees: 2.8,
                                               calibrationNotes: "Re-ran calibration after remounting hub level."))
        ]
    }

    static var scoutingRecords: [ScoutingRecord] {
        [
            ScoutingRecord(matchNumber: 12, teamScouted: 18234, authorID: jordan.id, authorName: jordan.name,
                            autoScore: 28, teleopScore: 64, endgameScore: 15, autoSamplesOrSpecimens: 4,
                            teleopCycles: 9, driverRating: 4, notes: "Consistent auto, strong cycle time.")
        ]
    }

    static var ideas: [Idea] {
        [
            Idea(authorID: sam.id, authorName: sam.name, summary: "Dual-intake system",
                 detail: "Add a second intake on the rear to cut travel distance in half.",
                 upvoterIDs: [alex.id, priya.id])
        ]
    }

    static var activity: [ActivityEvent] {
        [
            ActivityEvent(authorID: sam.id, authorName: sam.name, kind: .taskCompleted, message: "completed task: Scout Week 1 quals"),
            ActivityEvent(authorID: jordan.id, authorName: jordan.name, kind: .scoutingSubmitted, message: "submitted scouting data for Match 12"),
            ActivityEvent(authorID: sam.id, authorName: sam.name, kind: .ideaPosted, message: "posted idea: Dual-intake system")
        ]
    }
}
