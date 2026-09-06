//
//  FirebaseSyncService.swift
//  FTCTeamHub
//
//  Cross-device backend sync using Firebase Firestore — the free-tier
//  alternative to CloudKit, since CloudKit's capability is locked behind a
//  paid Apple Developer Program membership and this app is built for
//  free-Apple-ID AltStore sideloading. Firestore needs no special Apple
//  entitlements, just the GoogleService-Info.plist from your own free
//  Firebase project (see FIREBASE_SETUP.md).
//
//  SCOPE: This syncs `TaskItem` and `ActivityEvent` bidirectionally in real
//  time — the two collections where "did my teammate already see/do this"
//  actually matters most day-to-day. `NotebookEntry`, `TestRunRecord`, and
//  `Idea` can be wired in following the exact same pattern (see the two
//  push/listen pairs below as a template) once you're happy with this
//  layer's behavior.
//
//  Design: every write goes to SwiftData FIRST (so the app is always fully
//  usable offline), then mirrors to Firestore. Incoming Firestore snapshot
//  listeners upsert into SwiftData by matching on the model's own `id`
//  (stored as the Firestore document ID), so the same record is never
//  duplicated across devices.
//

import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
final class FirebaseSyncService {

    private let db = Firestore.firestore()
    private var taskListener: ListenerRegistration?
    private var activityListener: ListenerRegistration?
    private weak var modelContext: ModelContext?

    /// Call once, after Firebase has been configured and you have a
    /// ModelContext available (see FTCTeamHubApp.swift).
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
        // Skip if our local copy is already newer or the same (avoids
        // clobbering an in-flight local edit with a stale remote write).
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
        guard (try? context.fetch(descriptor).first) == nil else { return } // already have it

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
