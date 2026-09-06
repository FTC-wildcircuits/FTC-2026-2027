//
//  ScoutingTabView.swift
//  FTCTeamHub
//
//  TAB 1 — Scouting & Data. Three sub-screens via a segmented NavigationStack:
//  live FTCScout event/OPR lookup, one-handed match entry, and the alliance
//  selection picklist. Strict MVVM: the View only renders `@Observable`
//  ScoutingViewModel state and forwards intents.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - ViewModel

@MainActor
@Observable
final class ScoutingViewModel {
    var searchTeamNumber: String = ""
    var lookedUpTeam: FTCTeamOPR?
    var isLoadingTeam = false
    var apiErrorMessage: String?

    private let api: FTCScoutAPIServicing

    init(api: FTCScoutAPIServicing) {
        self.api = api
    }

    func lookUpTeam(season: Int = 2025) async {
        guard let number = Int(searchTeamNumber) else {
            apiErrorMessage = "Enter a numeric team number."
            return
        }
        isLoadingTeam = true
        apiErrorMessage = nil
        do {
            lookedUpTeam = try await api.fetchTeamOPR(teamNumber: number, season: season)
        } catch {
            apiErrorMessage = error.localizedDescription
        }
        isLoadingTeam = false
    }
}

// MARK: - Root view

struct ScoutingTabView: View {
    @Environment(\.ftcScoutAPI) private var api
    @State private var viewModel: ScoutingViewModel?
    @State private var section: Section = .liveData

    enum Section: String, CaseIterable, Identifiable {
        case liveData = "Live Data", entry = "Match Entry", picklist = "Picklist"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Divider().padding(.top, 8)

                switch section {
                case .liveData: LiveDataView(viewModel: viewModel!)
                case .entry: ScoutingEntryView()
                case .picklist: PicklistView()
                }
            }
            .navigationTitle("Scouting")
        }
        .onAppear {
            if viewModel == nil { viewModel = ScoutingViewModel(api: api) }
        }
    }
}

// MARK: - Live FTCScout data lookup

private struct LiveDataView: View {
    @Bindable var viewModel: ScoutingViewModel

    var body: some View {
        List {
            Section("FTCScout Team Lookup") {
                HStack {
                    TextField("Team number, e.g. 24211", text: $viewModel.searchTeamNumber)
                        .keyboardType(.numberPad)
                    Button("Search") {
                        Task { await viewModel.lookUpTeam() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoadingTeam)
                }

                if viewModel.isLoadingTeam {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let error = viewModel.apiErrorMessage {
                    Text(error).font(.footnote).foregroundStyle(.red)
                } else if let team = viewModel.lookedUpTeam {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(team.name).font(.headline)
                        HStack {
                            OPRStat(label: "Auto", value: team.autoOPR)
                            OPRStat(label: "TeleOp", value: team.teleOpOPR)
                            OPRStat(label: "Endgame", value: team.endgameOPR)
                            OPRStat(label: "Total", value: team.totalOPR, bold: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Text("Data sourced live from api.ftcscout.org/graphql.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct OPRStat: View {
    let label: String
    let value: Double
    var bold: Bool = false

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(1)))
                .font(bold ? .headline.monospacedDigit() : .subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - High-speed, one-handed match entry

private struct ScoutingEntryView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var backend: MockBackendService

    @State private var matchNumber = 1
    @State private var teamScouted = ""
    @State private var autoSamples = 0
    @State private var teleopCycles = 0
    @State private var driverRating = 3
    @State private var notes = ""

    private let haptics = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Form {
            Section("Match") {
                Stepper("Match #\(matchNumber)", value: $matchNumber, in: 1...200)
                TextField("Team scouted", text: $teamScouted)
                    .keyboardType(.numberPad)
            }

            Section("Autonomous") {
                LargeStepperRow(label: "Samples / Specimens", value: $autoSamples, haptics: haptics)
            }

            Section("TeleOp") {
                LargeStepperRow(label: "Cycles", value: $teleopCycles, haptics: haptics)
            }

            Section("Driver Rating") {
                Picker("Rating", selection: $driverRating) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 80)
            }

            Section {
                Button {
                    submit()
                } label: {
                    Text("Submit Scouting Record")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(teamScouted.isEmpty)
            }
        }
    }

    private func submit() {
        guard let teamNum = Int(teamScouted), let user = backend.currentUser else { return }
        let record = ScoutingRecord(
            matchNumber: matchNumber, teamScouted: teamNum, authorID: user.id, authorName: user.name,
            autoSamplesOrSpecimens: autoSamples, teleopCycles: teleopCycles, driverRating: driverRating, notes: notes
        )
        context.insert(record)
        let event = ActivityEvent(authorID: user.id, authorName: user.name, kind: .scoutingSubmitted,
                                   message: "submitted scouting data for Match \(matchNumber)")
        context.insert(event)
        Task { await backend.broadcastActivity(event) }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        teamScouted = ""; autoSamples = 0; teleopCycles = 0; driverRating = 3; notes = ""
        matchNumber += 1
    }
}

/// Large, thumb-reachable stepper for one-handed pit/stand scouting.
private struct LargeStepperRow: View {
    let label: String
    @Binding var value: Int
    let haptics: UIImpactFeedbackGenerator

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button { decrement() } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .disabled(value == 0)

            Text("\(value)")
                .font(.title2.monospacedDigit().bold())
                .frame(minWidth: 36)

            Button { increment() } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 30))
            }
            .buttonStyle(.plain)
        }
    }

    private func increment() { haptics.impactOccurred(); value += 1 }
    private func decrement() { haptics.impactOccurred(); value = max(0, value - 1) }
}

// MARK: - Alliance selection picklist

private struct PicklistView: View {
    @Query(sort: \PicklistEntry.tier) private var entries: [PicklistEntry]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var backend: MockBackendService

    var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView("No teams tiered yet", systemImage: "list.number",
                                       description: Text("Add teams from Live Data to start building your picklist."))
            }
            ForEach(entries) { entry in
                HStack {
                    Text("Tier \(entry.tier)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.tertiary, in: Capsule())
                    VStack(alignment: .leading) {
                        Text(entry.teamName).font(.headline)
                        Text("Team \(entry.teamNumber) · OPR \(entry.averageOPR, specifier: "%.1f")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onMove(perform: moveEntries)

            Section {
                Button {
                    addSampleEntry()
                } label: {
                    Label("Add Team to Picklist", systemImage: "plus")
                }
            }
        }
        .toolbar { EditButton() }
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        var reordered = entries
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, entry) in reordered.enumerated() { entry.tier = index + 1 }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func addSampleEntry() {
        guard let user = backend.currentUser else { return }
        let entry = PicklistEntry(teamNumber: Int.random(in: 1000...30000), teamName: "New Scouted Team",
                                   tier: entries.count + 1, averageOPR: Double.random(in: 10...60),
                                   lastEditedBy: user.id)
        context.insert(entry)
    }
}
