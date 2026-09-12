//
//  ChatTabView.swift
//  FTCTeamHub
//
//  TAB 8 — Team Chat. Simple, real-time messaging for whatever the team
//  needs to discuss, whether at practice or not. Bubble-style layout with
//  your own messages right-aligned and tinted, matching standard iOS
//  Messages conventions rather than inventing a new visual language.
//

import SwiftUI

struct ChatTabView: View {
    @Environment(\.chatService) private var chatService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let chatService {
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
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }

                    if chatService.messages.isEmpty {
                        ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right",
                                               description: Text("Say hello to the team."))
                    }
                } else {
                    ContentUnavailableView("Chat unavailable", systemImage: "bubble.left.slash",
                                           description: Text("Chat service isn't connected."))
                }

                Divider()

                HStack(spacing: 8) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Team Chat")
        }
    }

    private func send() {
        guard let user = authManager.currentUser, let chatService else { return }
        chatService.send(text: draft, authorID: user.id, authorName: user.name)
        draft = ""
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
                    .background(isMine ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(isMine ? .white : .primary)
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if !isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}
