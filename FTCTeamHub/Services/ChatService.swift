//
//  ChatService.swift
//  FTCTeamHub
//
//  Team chat, live across all devices, independent of practice sessions —
//  a running channel for anything the team needs to discuss. Deliberately
//  NOT mirrored into SwiftData: chat is inherently an online, ephemeral-ish
//  feed, so it's kept purely in Firestore and streamed straight into an
//  in-memory published array. If you later want offline read history,
//  mirror this into a SwiftData model the same way FirebaseSyncService
//  does for Tasks/Notebook/etc.
//
//  Same crash-avoidance pattern as FirebaseSyncService: `db` is `lazy var`
//  so Firestore isn't touched until after FirebaseApp.configure() has run.
//

import Foundation
import FirebaseFirestore
import Observation

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let authorID: String
    let authorName: String
    let text: String
    let timestamp: Date
}

@MainActor
@Observable
final class ChatService {

    private lazy var db = Firestore.firestore()
    private var listener: ListenerRegistration?

    private(set) var messages: [ChatMessage] = []

    func start() {
        listener = db.collection("chat")
            .order(by: "timestamp", descending: false)
            .limit(toLast: 300)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot, error == nil else { return }
                self.messages = snapshot.documents.compactMap { doc in
                    let data = doc.data()
                    guard let authorID = data["authorID"] as? String,
                          let authorName = data["authorName"] as? String,
                          let text = data["text"] as? String else { return nil }
                    let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? .now
                    return ChatMessage(id: doc.documentID, authorID: authorID, authorName: authorName,
                                       text: text, timestamp: timestamp)
                }
            }
    }

    func stop() {
        listener?.remove()
    }

    func send(text: String, authorID: UUID, authorName: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let data: [String: Any] = [
            "authorID": authorID.uuidString,
            "authorName": authorName,
            "text": trimmed,
            "timestamp": Date()
        ]
        db.collection("chat").addDocument(data: data)
    }
}
