//
//  FirebaseSyncService.swift
//  FTCTeamHub
//
//  Cross-device backend sync using Firebase Firestore.
//
//  NEW: Team roster (`AppUser`) now syncs too. Every sign-up pushes the
//  user's profile (including password hash — see security note below) to
//  Firestore, and every device listens for other members' profiles so the
//  Roster tab shows the whole team regardless of which device each person
//  signed up on, AND so any team member can sign in from any device.
//
//  SECURITY NOTE: syncing the SHA256 password hash (not the plaintext
//  password) to Firestore is what makes "sign in from any device" work —
//  without it, a device that never saw a given signup could never verify
//  that user's password locally. This is an acceptable tradeoff for a
//  small internal team tool behind Firestore rules that are not publicly
//  exposed, but is NOT bank-grade security — don't reuse this pattern for
//  anything storing real user passwords at wider scale.
//

import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
final class FirebaseSyncService {

    private lazy var db = Firestore.firestore()
    private var taskListener: ListenerRegistration?
    private var activityListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private var notebookListener: ListenerRegistration?
    private var ideaListener: ListenerRegistration?
    private var testRunListener: ListenerRegistration?
    private weak var modelContext: ModelContext?

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        listenForUserChanges()
        listenForTaskChanges()
        listenForActivityChanges()
        listenForNotebookChanges()
        listenForIdeaChanges()
        listenForTestRunChanges()
    }

    func stop() {
        taskListener?.remove()
        activityListener?.remove()
        userListener?.remove()
        notebookListener?.remove()
        ideaListener?.remove()
        testRunListener?.remove()
    }

    // MARK: - Roster (AppUser)

    func pushUser(_ user: AppUser) {
        let data: [String: Any] = [
            "email": user.email,
            "name": user.name,
            "roleRaw": user.roleRaw,
            "avatarColorRaw": user.avatarColorRaw,
            "passwordHash": user.passwordHash,
            "joinedAt": user.joinedAt
        ]
        db.collection("users").document(user.id.uuidString).setData(data, merge: true)
    }

    private func listenForUserChanges() {
        userListener = db.collection("users").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges {
                self.upsertUser(from: change.document)
            }
        }
    }

    private func upsertUser(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first

        let user = existing ?? AppUser(
            id: id, email: data["email"] as? String ?? "",
            name: "", role: .builder, avatarColor: .blue, passwordHash: ""
        )
        user.email = data["email"] as? String ?? user.email
        user.name = data["name"] as? String ?? user.name
        user.roleRaw = data["roleRaw"] as? String ?? user.roleRaw
        user.avatarColorRaw = data["avatarColorRaw"] as? String ?? user.avatarColorRaw
        user.passwordHash = data["passwordHash"] as? String ?? user.passwordHash

        if existing == nil { context.insert(user) }
        try? context.save()
    }

    // MARK: - Tasks

    func pushTask(_ task: TaskItem) {
        let data: [String: Any] = [
            "title": task.title,
            "taskDescription": task.taskDescription,
            "assignedToID": task.assignedToID?.uuidString ?? "",
            "assignedToName": task.assignedToName,
            "status": task.status.rawValue,
            "priority": task.priority.rawValue,
            "deadline": task.deadline as Any,
            "tags": task.tags,
            "dateCreated": task.dateCreated,
            "authorID": task.authorID.uuidString,
            "authorName": task.authorName,
            "lastModified": task.lastModified
        ]
        db.collection("tasks").document(task.id.uuidString).setData(data, merge: true)
    }

    private func listenForTaskChanges() {
        taskListener = db.collection("tasks").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges {
                self.upsertTask(from: change.document)
            }
        }
    }

    private func upsertTask(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()

        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first

        let remoteModified = (data["lastModified"] as? Timestamp)?.dateValue() ?? .distantPast
        if let existing, existing.lastModified >= remoteModified { return }

        let task = existing ?? TaskItem(
            id: id, title: "", authorID: UUID(), authorName: ""
        )
        task.title = data["title"] as? String ?? task.title
        task.taskDescription = data["taskDescription"] as? String ?? task.taskDescription
        task.assignedToID = UUID(uuidString: data["assignedToID"] as? String ?? "")
        task.assignedToName = data["assignedToName"] as? String ?? task.assignedToName
        task.status = TaskStatus(rawValue: data["status"] as? String ?? "") ?? task.status
        task.priority = TaskPriority(rawValue: data["priority"] as? String ?? "") ?? task.priority
        task.tags = data["tags"] as? [String] ?? task.tags
        task.lastModified = remoteModified

        if existing == nil { context.insert(task) }
        try? context.save()
    }

    // MARK: - Activity feed

    func pushActivity(_ event: ActivityEvent) {
        let data: [String: Any] = [
            "authorID": event.authorID.uuidString,
            "authorName": event.authorName,
            "kind": event.kind.rawValue,
            "message": event.message,
            "timestamp": event.timestamp
        ]
        db.collection("activity").document(event.id.uuidString).setData(data, merge: true)
    }

    private func listenForActivityChanges() {
        activityListener = db.collection("activity")
            .order(by: "timestamp", descending: true)
            .limit(to: 200)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot, error == nil else { return }
                for change in snapshot.documentChanges where change.type == .added {
                    self.insertActivityIfNeeded(from: change.document)
                }
            }
    }

    private func insertActivityIfNeeded(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.id == id })
        guard (try? context.fetch(descriptor).first) == nil else { return }

        let data = document.data()
        guard let authorID = UUID(uuidString: data["authorID"] as? String ?? ""),
              let kindRaw = data["kind"] as? String,
              let kind = ActivityKind(rawValue: kindRaw) else { return }

        let event = ActivityEvent(
            id: id,
            authorID: authorID,
            authorName: data["authorName"] as? String ?? "",
            kind: kind,
            message: data["message"] as? String ?? "",
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? .now
        )
        context.insert(event)
        try? context.save()
    }

    // MARK: - Notebook entries

    func pushNotebookEntry(_ entry: NotebookEntry) {
        var data: [String: Any] = [
            "authorID": entry.authorID.uuidString,
            "authorName": entry.authorName,
            "title": entry.title,
            "content": entry.content,
            "tags": entry.tags,
            "timestamp": entry.timestamp
        ]
        if let auto = entry.autonomousLog, let encoded = try? JSONEncoder().encode(auto) {
            data["autonomousLog"] = String(data: encoded, encoding: .utf8)
        }
        if let hub = entry.hubConfigLog, let encoded = try? JSONEncoder().encode(hub) {
            data["hubConfigLog"] = String(data: encoded, encoding: .utf8)
        }
        if let imu = entry.imuLog, let encoded = try? JSONEncoder().encode(imu) {
            data["imuLog"] = String(data: encoded, encoding: .utf8)
        }
        db.collection("notebook").document(entry.id.uuidString).setData(data, merge: true)
    }

    private func listenForNotebookChanges() {
        notebookListener = db.collection("notebook").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges where change.type == .added {
                self.insertNotebookEntryIfNeeded(from: change.document)
            }
        }
    }

    private func insertNotebookEntryIfNeeded(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<NotebookEntry>(predicate: #Predicate { $0.id == id })
        guard (try? context.fetch(descriptor).first) == nil else { return }

        let data = document.data()
        guard let authorID = UUID(uuidString: data["authorID"] as? String ?? "") else { return }

        let entry = NotebookEntry(
            id: id, authorID: authorID, authorName: data["authorName"] as? String ?? "",
            title: data["title"] as? String ?? "", content: data["content"] as? String ?? "",
            tags: data["tags"] as? [String] ?? [],
            timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? .now
        )
        if let raw = data["autonomousLog"] as? String, let json = raw.data(using: .utf8) {
            entry.autonomousLog = try? JSONDecoder().decode(AutonomousTestLog.self, from: json)
        }
        if let raw = data["hubConfigLog"] as? String, let json = raw.data(using: .utf8) {
            entry.hubConfigLog = try? JSONDecoder().decode(ControlHubConfigLog.self, from: json)
        }
        if let raw = data["imuLog"] as? String, let json = raw.data(using: .utf8) {
            entry.imuLog = try? JSONDecoder().decode(IMUTuningLog.self, from: json)
        }
        context.insert(entry)
        try? context.save()
    }

    // MARK: - Ideas

    func pushIdea(_ idea: Idea) {
        let data: [String: Any] = [
            "authorID": idea.authorID.uuidString,
            "authorName": idea.authorName,
            "summary": idea.summary,
            "detail": idea.detail,
            "upvoterIDs": idea.upvoterIDs.map { $0.uuidString },
            "timestamp": idea.timestamp,
            "promotedToTask": idea.promotedToTask
        ]
        db.collection("ideas").document(idea.id.uuidString).setData(data, merge: true)
    }

    private func listenForIdeaChanges() {
        ideaListener = db.collection("ideas").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges {
                self.upsertIdea(from: change.document)
            }
        }
    }

    private func upsertIdea(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()

        let descriptor = FetchDescriptor<Idea>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        guard let authorID = UUID(uuidString: data["authorID"] as? String ?? "") else { return }

        let idea = existing ?? Idea(id: id, authorID: authorID, authorName: "", summary: "")
        idea.authorName = data["authorName"] as? String ?? idea.authorName
        idea.summary = data["summary"] as? String ?? idea.summary
        idea.detail = data["detail"] as? String ?? idea.detail
        idea.upvoterIDs = (data["upvoterIDs"] as? [String] ?? []).compactMap { UUID(uuidString: $0) }
        idea.promotedToTask = data["promotedToTask"] as? Bool ?? idea.promotedToTask

        if existing == nil { context.insert(idea) }
        try? context.save()
    }

    // MARK: - Test runs

    func pushTestRun(_ record: TestRunRecord) {
        let data: [String: Any] = [
            "driverID": record.driverID.uuidString,
            "driverName": record.driverName,
            "date": record.date,
            "autoScore": record.autoScore,
            "teleopScore": record.teleopScore,
            "endgameScore": record.endgameScore,
            "cycleTimeSeconds": record.cycleTimeSeconds,
            "autoConsistencyPercent": record.autoConsistencyPercent,
            "mechanicalIssues": record.mechanicalIssues,
            "notes": record.notes,
            "recordedByID": record.recordedByID.uuidString,
            "recordedByName": record.recordedByName
        ]
        db.collection("testRuns").document(record.id.uuidString).setData(data, merge: true)
    }

    private func listenForTestRunChanges() {
        testRunListener = db.collection("testRuns").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges where change.type == .added {
                self.insertTestRunIfNeeded(from: change.document)
            }
        }
    }

    private func insertTestRunIfNeeded(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<TestRunRecord>(predicate: #Predicate { $0.id == id })
        guard (try? context.fetch(descriptor).first) == nil else { return }

        let data = document.data()
        guard let driverID = UUID(uuidString: data["driverID"] as? String ?? ""),
              let recordedByID = UUID(uuidString: data["recordedByID"] as? String ?? "") else { return }

        let record = TestRunRecord(
            id: id, driverID: driverID, driverName: data["driverName"] as? String ?? "",
            date: (data["date"] as? Timestamp)?.dateValue() ?? .now,
            autoScore: data["autoScore"] as? Int ?? 0,
            teleopScore: data["teleopScore"] as? Int ?? 0,
            endgameScore: data["endgameScore"] as? Int ?? 0,
            cycleTimeSeconds: data["cycleTimeSeconds"] as? Double ?? 0,
            autoConsistencyPercent: data["autoConsistencyPercent"] as? Double ?? 0,
            mechanicalIssues: data["mechanicalIssues"] as? [String] ?? [],
            notes: data["notes"] as? String ?? "",
            recordedByID: recordedByID, recordedByName: data["recordedByName"] as? String ?? ""
        )
        context.insert(record)
        try? context.save()
    }
}
