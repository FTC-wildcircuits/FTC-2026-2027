//
//  ChatTabView.swift
//  FTCTeamHub
//
//  Team chat backed by ChatService and Firestore.
//

import SwiftUI

struct ChatTabView: View {
    @Environment(\.chatService) private var chatService
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(TabRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !cloudSyncEnabled {
                    ContentUnavailableView {
                        Label("Team chat is paused", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Enable team cloud sync in Team settings when you are ready to connect.")
                    } actions: {
                        Button("Open team settings") { router.selection = .team }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let chatService {
                    if chatService.messages.isEmpty {
                        switch chatService.connectionState {
                        case .connecting:
                            ProgressView("Connecting to team chat…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .connected:
                            ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right",
                                                   description: Text("Say hello to the team."))
                        case .cached:
                            ContentUnavailableView {
                                Label("Showing saved messages", systemImage: "icloud.slash")
                            } description: {
                                Text("New messages may wait on this device until Firestore reconnects.")
                            } actions: {
                                Button("Reconnect") { reconnect(chatService) }
                            }
                        case .unavailable(let message):
                            ContentUnavailableView {
                                Label("Chat unavailable", systemImage: "bubble.left.slash")
                            } description: {
                                Text(message)
                            } actions: {
                                Button("Reconnect") {
                                    reconnect(chatService)
                                }
                            }
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(chatService.messages) { message in
                                        ChatBubble(message: message, isMine: message.authorID == authManager.currentUser?.id.uuidString)
                                            .id(message.id)
                                    }
                                }
                                .padding()
                            }
                            .onChange(of: chatService.messages.count) {
                                if let last = chatService.messages.last {
                                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }

                    if case .cached = chatService.connectionState, !chatService.messages.isEmpty {
                        HStack {
                            Label("Offline — messages may be waiting to sync", systemImage: "icloud.slash")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                            Spacer()
                            Button("Reconnect") { reconnect(chatService) }
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }

                    if case .unavailable(let message) = chatService.connectionState, !chatService.messages.isEmpty {
                        HStack {
                            Label(message, systemImage: "wifi.exclamationmark")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                            Spacer()
                            Button("Reconnect") {
                                reconnect(chatService)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                    }
                } else {
                    ContentUnavailableView("Chat unavailable", systemImage: "bubble.left.slash",
                                           description: Text("Chat service isn't connected."))
                }

                if cloudSyncEnabled {
                    Divider()

                    HStack(spacing: 8) {
                        TextField("Message", text: $draft, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .disabled(isSending || chatService == nil)
                        Button {
                            send()
                        } label: {
                            Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                                .font(.largeTitle)
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || chatService == nil)
                    }
                    .padding()

                    if let sendError {
                        Text(sendError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("Team Chat")
            .onAppear {
                if cloudSyncEnabled { chatService?.start() }
            }
            .onChange(of: cloudSyncEnabled) { _, enabled in
                if enabled {
                    chatService?.start()
                } else {
                    chatService?.stop()
                }
            }
            .onDisappear { chatService?.stop() }
        }
    }

    private func send() {
        guard let user = authManager.currentUser, let chatService else { return }
        let message = draft
        isSending = true
        sendError = nil
        chatService.send(text: message, authorID: user.id, authorName: user.name) { error in
            isSending = false
            if let error {
                sendError = error.localizedDescription
            } else {
                draft = ""
            }
        }
    }

    private func reconnect(_ service: ChatService) {
        sendError = nil
        service.stop()
        service.start()
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 40) }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine {
                    Text(message.authorName).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isMine ? Color.accentColor.opacity(0.14) : FTCDesign.secondarySurface,
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.primary)
                if message.isPending {
                    Text("Waiting to sync…")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                } else {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}
