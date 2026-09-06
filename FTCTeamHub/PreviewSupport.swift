//
//  PreviewSupport.swift
//  FTCTeamHub
//
//  Shared in-memory ModelContainer + rich sample data used by every
//  SwiftUI `#Preview` block in this project, so every screen can be
//  designed and tested instantly in Xcode without running the full app
//  or signing in manually each time.
//

import Foundation
import SwiftData

@MainActor
func makePreviewContainer() -> ModelContainer {
    let schema = Schema([
        AppUser.self, TaskItem.self, NotebookEntry.self,
        TestRunRecord.self, Idea.self, ActivityEvent.self, TrackedTeam.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = container.mainContext

    let alex = AppUser(email: "alex@team24211.com", name: "Alex Rivera", role: .softwareLead,
                        avatarColor: .blue, passwordHash: "", isLogged: true)
    let sam = AppUser(email: "sam@team24211.com", name: "Sam Okafor", role: .hardware,
                       avatarColor: .orange, passwordHash: "")
    let priya = AppUser(email: "priya@team24211.com", name: "Priya Nandan", role: .strategy,
                         avatarColor: .purple, passwordHash: "")
    let jordan = AppUser(email: "jordan@team24211.com", name: "Jordan Lee", role: .builder,
                          avatarColor: .green, passwordHash: "")

    [alex, sam, priya, jordan].forEach { context.insert($0) }

    context.insert(TaskItem(title: "Mount odometry pods",
                             taskDescription: "Finalize bracket for dead-wheel pods on drivetrain.",
                             assignedToID: sam.id, assignedToName: sam.name,
                             status: .inProgress, priority: .high,
                             deadline: Calendar.current.date(byAdding: .day, value: 2, to: .now),
                             tags: ["Hardware", "Chassis"], authorID: priya.id, authorName: priya.name))

    context.insert(TaskItem(title: "Tune PID for arm subsystem",
                             taskDescription: "Reduce overshoot below 3 degrees.",
                             assignedToID: alex.id, assignedToName: alex.name,
                             status: .toDo, priority: .critical,
                             deadline: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                             tags: ["Software"], authorID: alex.id, authorName: alex.name))

    context.insert(TaskItem(title: "Finalize sponsor outreach packet",
                             assignedToID: priya.id, assignedToName: priya.name,
                             status: .blocked, priority: .low,
                             tags: ["Outreach"], authorID: priya.id, authorName: priya.name))

    context.insert(TestRunRecord(driverID: jordan.id, driverName: jordan.name, date: .now,
                                  autoScore: 28, teleopScore: 64, endgameScore: 15,
                                  cycleTimeSeconds: 4.2, autoConsistencyPercent: 85,
                                  mechanicalIssues: ["Intake Jam"], notes: "Consistent auto, strong cycle time.",
                                  recordedByID: alex.id, recordedByName: alex.name))

    context.insert(TestRunRecord(driverID: jordan.id, driverName: jordan.name,
                                  date: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now,
                                  autoScore: 18, teleopScore: 50, endgameScore: 10,
                                  cycleTimeSeconds: 5.1, autoConsistencyPercent: 65,
                                  mechanicalIssues: ["Belt Slipped", "Code Crash"], notes: "Rough first week.",
                                  recordedByID: alex.id, recordedByName: alex.name))

    context.insert(NotebookEntry(authorID: alex.id, authorName: alex.name, title: "IMU drift investigation",
                                  content: "## Summary\nObserved yaw drift after 8 minutes of continuous operation.",
                                  tags: ["Software", "IMU"],
                                  imuLog: IMUTuningLog(chip: "BHI260AP", logoFacingDirection: "UP",
                                                        usbFacingDirection: "FORWARD", yawOffsetDegrees: 1.2,
                                                        driftOverTenMinDegrees: 2.8,
                                                        calibrationNotes: "Re-ran calibration after remounting hub level.")))

    context.insert(Idea(authorID: sam.id, authorName: sam.name, summary: "Dual-intake system",
                         detail: "Add a second intake on the rear to cut travel distance in half.",
                         upvoterIDs: [alex.id, priya.id]))

    context.insert(ActivityEvent(authorID: sam.id, authorName: sam.name, kind: .taskCompleted,
                                  message: "completed task: Wire drivetrain motors"))
    context.insert(ActivityEvent(authorID: jordan.id, authorName: jordan.name, kind: .testLogged,
                                  message: "logged a test run"))
    context.insert(ActivityEvent(authorID: sam.id, authorName: sam.name, kind: .ideaPosted,
                                  message: "posted idea: Dual-intake system"))

    context.insert(TrackedTeam(teamNumber: 18234, teamName: "Circuit Breakers",
                                note: "Strong auto, watch their endgame climb.",
                                addedByID: priya.id, addedByName: priya.name))

    try? context.save()
    return container
}
