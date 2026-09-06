//
//  LiveDataTabView.swift
//  FTCTeamHub
//
//  TAB 6 — Live FTC Data. Pulls real, public competition data from
//  api.ftcscout.org/graphql: search any team's official OPR breakdown,
//  browse season events, and bookmark teams of interest (e.g. upcoming
//  opponents) for quick access before an event. Fully separate from your
//  internal Roster — this tracks OTHER teams' public stats, not your own
//  members.
//
//  Design: matches the rest of the app — plain List/Form/GroupBox
//  components, no custom chrome, native segmented control for switching
//  sub-sections, same typography and spacing rhythm as the other five tabs.
//

import SwiftUI
import SwiftData
import UIKit

struct LiveDataTabView: View {
    @Environment(\.ftcScoutAPI) private var api
    @State private var section: Section = .search

    enum Section: String, CaseIterable, Identifiable {
        case search = "Search", bookmarked = "Bookmarked", events = "Events"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch section {
                case .search: TeamSearchView(api: api)
                case .bookmarked: BookmarkedTeamsView(api: api)
                case .events: EventsBrowserView(api: api)
                }
            }
            .navigationTitle("Live FTC Data")
        }
    }
}

// MARK: - Team search

private struct TeamSearchView: View {
    let api: FTCScoutAPIServicing
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.modelContext) private var context
    @Query private var bookmarks: [TrackedTeam]

    @State private var teamNumberInput = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var result: FTCTeamOPR?

    private var isBookmarked: Bool {
        guard let result else { return false }
        return bookmarks.contains { $0.teamNumber == result.number }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Team number, e.g. 24211", text: $teamNumberInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await search() }
                    } label: {
                        if isLoading { ProgressView() } else { Text("Search") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(teamNumberInput.isEmpty || isLoading)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            if let result {
                Section("\(result.name) · #\(result.number)") {
                    OPRBreakdownView(team: result)
                    Button {
                        bookmark(result)
                    } label: {
                        Label(isBookmarked ? "Bookmarked" : "Track This Team", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                    .disabled(isBookmarked)
                }
            }

            Section {
                Text("Live data sourced from api.ftcscout.org/graphql.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func search() async {
        guard let number = Int(teamNumberInput) else {
            errorMessage = "Enter a numeric team number."
            return
        }
        isLoading = true
        errorMessage = nil
        result = nil
        do {
            result = try await api.fetchTeamOPR(teamNumber: number, season: 2025)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func bookmark(_ team: FTCTeamOPR) {
        guard let currentUser = authManager.currentUser else { return }
        let tracked = TrackedTeam(teamNumber: team.number, teamName: team.name,
                                   addedByID: currentUser.id, addedByName: currentUser.name)
        context.insert(tracked)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - OPR breakdown (shared visual component)

private struct OPRBreakdownView: View {
    let team: FTCTeamOPR

    private var maxOPR: Double {
        max(team.autoOPR, team.teleOpOPR, team.endgameOPR, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OPRBar(label: "Auto", value: team.autoOPR, maxValue: maxOPR, color: .blue)
            OPRBar(label: "TeleOp", value: team.teleOpOPR, maxValue: maxOPR, color: .orange)
            OPRBar(label: "Endgame", value: team.endgameOPR, maxValue: maxOPR, color: .purple)
            Divider()
            HStack {
                Text("Total OPR").font(.subheadline.weight(.semibold))
                Spacer()
                Text(team.totalOPR, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct OPRBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.caption.monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * min(value / maxValue, 1), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Bookmarked teams

private struct BookmarkedTeamsView: View {
    let api: FTCScoutAPIServicing
    @Query(sort: \TrackedTeam.addedAt, order: .reverse) private var bookmarks: [TrackedTeam]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            if bookmarks.isEmpty {
                ContentUnavailableView("No tracked teams", systemImage: "bookmark",
                                       description: Text("Search a team and tap \"Track This Team\" to save it here."))
            }
            ForEach(bookmarks) { team in
                NavigationLink {
                    TrackedTeamDetailView(team: team, api: api)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.teamName).font(.body.weight(.medium))
                        Text("Team \(team.teamNumber) · added by \(team.addedByName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .toolbar { EditButton() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(bookmarks[index]) }
    }
}

private struct TrackedTeamDetailView: View {
    let team: TrackedTeam
    let api: FTCScoutAPIServicing
    @State private var result: FTCTeamOPR?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Team \(team.teamNumber)") {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                } else if let result {
                    OPRBreakdownView(team: result)
                }
            }
            if !team.note.isEmpty {
                Section("Notes") { Text(team.note) }
            }
        }
        .navigationTitle(team.teamName)
        .task {
            do {
                result = try await api.fetchTeamOPR(teamNumber: team.teamNumber, season: 2025)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Events browser

private struct EventsBrowserView: View {
    let api: FTCScoutAPIServicing
    @State private var events: [FTCEventSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            } else if events.isEmpty {
                ContentUnavailableView("No events found", systemImage: "calendar",
                                       description: Text("Try again later — the season schedule may not be published yet."))
            } else {
                ForEach(events) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name).font(.body.weight(.medium))
                        Text("\(event.start) – \(event.end)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .task {
            do {
                events = try await api.fetchEvents(season: 2025)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return LiveDataTabView()
        .modelContainer(container)
        .environment(authManager)
        .environment(\.ftcScoutAPI, LiveFTCScoutAPIClient())
}
