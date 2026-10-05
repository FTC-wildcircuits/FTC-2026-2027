//
//  RosterTabView.swift
//  FTCTeamHub
//
//  The team roster: role badges, avatars, and each member's most
//  recent contribution from the shared activity feed.
//

import SwiftUI
import SwiftData

struct RosterTabView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Query(sort: \AppUser.name) private var users: [AppUser]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var activity: [ActivityEvent]
    @State private var isPresentingProfile = false

    var body: some View {
        NavigationStack {
            List {
                Section("Members") {
                    if users.isEmpty {
                        ContentUnavailableView("No team members", systemImage: "person.2",
                                               description: Text("Team members appear here after they create an account on this device."))
                    } else if filteredUsers.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ForEach(filteredUsers) { user in
                            RosterRow(
                                user: user,
                                isCurrentUser: user.id == authManager.currentUser?.id,
                                recentActivity: activity.first { $0.authorID == user.id }
                            )
                        }
                    }
                }
                if !activity.isEmpty {
                    Section("Recent activity") {
                        ForEach(Array(activity.prefix(10))) { event in
                            ActivityRow(event: event)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search members")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingProfile = true } label: { Image(systemName: "person.crop.circle") }
                        .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                        .accessibilityLabel("Profile")
                }
            }
            .sheet(isPresented: $isPresentingProfile) { ProfileSheet() }
        }
    }

    @State private var searchText = ""

    private var filteredUsers: [AppUser] {
        guard !searchText.isEmpty else { return users }
        return users.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct RosterRow: View {
    let user: AppUser
    let isCurrentUser: Bool
    let recentActivity: ActivityEvent?

    var body: some View {
        HStack(spacing: FTCDesign.space12) {
            Circle()
                .fill(user.avatarColor.color.opacity(0.18))
                .frame(width: FTCDesign.minimumHitTarget, height: FTCDesign.minimumHitTarget)
                .overlay {
                    Text(user.initials)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
            VStack(alignment: .leading, spacing: FTCDesign.space4) {
                Text(user.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Label(user.role.rawValue, systemImage: user.role.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let recentActivity {
                    Text(recentActivity.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: FTCDesign.space8)
            if isCurrentUser {
                Text("You")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, FTCDesign.space4)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: FTCDesign.space12) {
            Image(systemName: event.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
            VStack(alignment: .leading, spacing: FTCDesign.space4) {
                (Text(event.authorName).fontWeight(.semibold) + Text(" \(event.message)"))
                    .font(.body)
                Text(event.timestamp, style: .relative)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProfileSheet: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let user = authManager.currentUser {
                    Section("Signed in as") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.role.rawValue)
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

#Preview("Team roster · Light") {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return RosterTabView()
        .modelContainer(container)
        .environment(authManager)
        .preferredColorScheme(.light)
}

#Preview("Team roster · Dark") {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return RosterTabView()
        .modelContainer(container)
        .environment(authManager)
        .preferredColorScheme(.dark)
}

#Preview("Team roster · Accessibility") {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return RosterTabView()
        .modelContainer(container)
        .environment(authManager)
        .dynamicTypeSize(.accessibility5)
}
