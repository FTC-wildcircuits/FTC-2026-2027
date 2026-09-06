//
//  FirebaseSyncService.swift
//  FTCTeamHub
//
//  Cross-device backend sync using Firebase Firestore.
//
//  CRASH FIX: `db` was previously `private let db = Firestore.firestore()`.
//  Swift initializes a class's stored property defaults immediately when
//  the instance is constructed — and this class gets constructed as part
//  of FTCTeamHubApp's OWN property initialization, which happens BEFORE
//  FTCTeamHubApp.init()'s body (where FirebaseApp.configure() lives) ever
//  runs. That meant Firestore.firestore() was being called before Firebase
//  was configured, which throws an uncaught Objective-C exception and
//  aborts the whole app instantly on launch — exactly the "kicked out"
//  symptom. Making `db` `lazy var` defers its creation until the first
//  time it's actually accessed (inside `start(modelContext:)`, called from
//  `.onAppear` well after `configure()` has already run), which fixes it.
//

import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
final class FirebaseSyncService {

    private lazy var db = Firestore.firestore()
    private var taskListener: ListenerRegistration?
    private var activityListener: ListenerRegistration?
    private weak var modelContext: ModelContext?

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        listenForTaskChanges()
        listenForActivityChanges()
    }

    func stop() {
        taskListener?.remove()
        activityListener?.remove()
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
}
