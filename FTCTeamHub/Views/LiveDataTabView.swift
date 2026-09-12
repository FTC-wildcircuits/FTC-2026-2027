//
//  LiveDataTabView.swift
//  FTCTeamHub
//
//  NEW: added a "Scoring Sim" segment (ScoringSimulatorView) — fits here
//  thematically since it's directly used during alliance selection,
//  alongside the team-search and bookmarking tools already in this tab.
//

import SwiftUI
import SwiftData
import UIKit

struct LiveDataTabView: View {
    @Environment(\.ftcScoutAPI) private var api
    @State private var section: Section = .search

    enum Section: String, CaseIterable, Identifiable {
        case search = "Search", bookmarked = "Bookmarked", events = "Events", scoring = "Scoring Sim"
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
                case .scoring: ScoringSimulatorView()
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

                    NavigationLink {
                        TeamDashboardView(teamNumber: result.number, teamName: result.name, api: api)
                    } label: {
                        Label("View Full Team Dashboard", systemImage: "chart.xyaxis.line")
                    }

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
            result = try await api.fetchTeamOPR(teamNumber: number, season: 2026)
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

struct OPRBreakdownView: View {
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
                EmptyStateView(icon: "bookmark", title: "No tracked teams",
                               subtitle: "Search a team and tap \"Track This Team\" to save it here.",
                               tint: .blue)
            }
            ForEach(bookmarks) { team in
                NavigationLink {
                    TeamDashboardView(teamNumber: team.teamNumber, teamName: team.teamName, api: api)
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
                EmptyStateView(icon: "calendar", title: "No events found",
                               subtitle: "Try again later — the season schedule may not be published yet.",
                               tint: .orange)
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
                events = try await api.fetchEvents(season: 2026)
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
    LiveDataTabView()
        .modelContainer(container)
        .environment(authManager)
        .environment(\.ftcScoutAPI, LiveFTCScoutAPIClient())
}
