//
//  ActivityTabView.swift
//  FTCTeamHub
//
//  TAB 5 — Activity Log. Global, chronologically sorted feed of every
//  contribution across the team, satisfying the accountability mandate.
//  Also hosts the profile / sign-out entry point since it's the natural
//  "about the team" surface.
//

import SwiftUI
import SwiftData

struct ActivityTabView: View {
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var events: [ActivityEvent]
    @EnvironmentObject private var backend: MockBackendService
    @State private var isPresentingProfile = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedByDay, id: \.key) { day, items in
                    Section(day) {
                        ForEach(items) { event in
                            ActivityRow(event: event)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingProfile = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $isPresentingProfile) { ProfileSheet() }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView("No activity yet", systemImage: "waveform.path.ecg",
                                           description: Text("Team contributions will appear here in real time."))
                }
            }
        }
    }

    private var groupedByDay: [(key: String, value: [ActivityEvent])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let grouped = Dictionary(grouping: events) { formatter.string(from: $0.timestamp) }
        return grouped.sorted { lhs, rhs in
            (grouped[lhs.key]?.first?.timestamp ?? .distantPast) > (grouped[rhs.key]?.first?.timestamp ?? .distantPast)
        }
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                (Text(event.authorName).fontWeight(.semibold) + Text(" \(event.message)"))
                    .font(.subheadline)
                Text(event.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backend: MockBackendService

    var body: some View {
        NavigationStack {
            Form {
                if let user = backend.currentUser {
                    Section("Signed in as") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Role", value: user.role.rawValue)
                        LabeledContent("Team", value: "\(user.teamNumber)")
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        backend.signOut()
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
