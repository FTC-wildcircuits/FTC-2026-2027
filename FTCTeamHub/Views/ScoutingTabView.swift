//
//  ScoutingTabView.swift
//  FTCTeamHub
//
//  Match-by-match scouting reports for opposing and alliance teams,
//  aggregated into per-team averages for alliance-selection strategy,
//  with CSV export.
//

import SwiftUI
import SwiftData
import UIKit

private struct ScoutTeamKey: Hashable {
    let teamNumber: Int
    let eventName: String
}

private struct ScoutTeamSummary: Identifiable {
    let teamNumber: Int
    let teamName: String
    let eventName: String
    let observations: Int
    let averageAuto: Double
    let averageTeleOp: Double
    let averageEndgame: Double

    var id: String { "\(teamNumber)-\(eventName)" }
    var averageTotal: Double { averageAuto + averageTeleOp + averageEndgame }
}

private struct ScoutingExport: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ScoutingTabView: View {
    @Environment(\.ftcScoutAPI) private var api
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @Query(sort: \ScoutingReport.observedAt, order: .reverse) private var reports: [ScoutingReport]

    @State private var events: [FTCEventSummary] = []
    @State private var isLoadingEvents = false
    @State private var eventError: String?
    @State private var searchText = ""
    @State private var isPresentingNewReport = false
    @State private var selectedEvent = "All events"
    @State private var export: ScoutingExport?
    @State private var exportError: String?

    private var season: Int { Calendar.current.component(.year, from: .now) }

    private var eventChoices: [String] {
        ["All events"] + Array(Set(reports.map(\.eventName)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var visibleReports: [ScoutingReport] {
        return reports.filter {
            let matchesEvent = selectedEvent == "All events" || $0.eventName == selectedEvent
            let matchesSearch = searchText.isEmpty ||
                String($0.teamNumber).localizedCaseInsensitiveContains(searchText) ||
                $0.teamName.localizedCaseInsensitiveContains(searchText) ||
                $0.eventName.localizedCaseInsensitiveContains(searchText) ||
                $0.matchNumber.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText) ||
                $0.capabilities.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesEvent && matchesSearch
        }
    }

    private var teamSummaries: [ScoutTeamSummary] {
        let groups = Dictionary(grouping: visibleReports) {
            ScoutTeamKey(teamNumber: $0.teamNumber, eventName: $0.eventName)
        }
        return groups.map { key, observations in
            let divisor = Double(observations.count)
            let first = observations[0]
            return ScoutTeamSummary(
                teamNumber: key.teamNumber,
                teamName: observations.first(where: { !$0.teamName.isEmpty })?.teamName ?? first.teamName,
                eventName: key.eventName,
                observations: observations.count,
                averageAuto: Double(observations.reduce(0) { $0 + $1.autonomousScore }) / divisor,
                averageTeleOp: Double(observations.reduce(0) { $0 + $1.teleOpScore }) / divisor,
                averageEndgame: Double(observations.reduce(0) { $0 + $1.endgameScore }) / divisor
            )
        }
        .sorted {
            if $0.averageTotal == $1.averageTotal { return $0.teamNumber < $1.teamNumber }
            return $0.averageTotal > $1.averageTotal
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Label("\(reports.count)", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                    Text("match observations saved")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        isPresentingNewReport = true
                    } label: {
                        Label("Scout", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }

            Section("Performance snapshot") {
                Picker("Event", selection: $selectedEvent) {
                    ForEach(eventChoices, id: \.self) { event in
                        Text(event).tag(event)
                    }
                }
                if teamSummaries.isEmpty {
                    Text("Team averages appear after you record match observations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(teamSummaries.prefix(8)) { summary in
                        ScoutTeamSummaryRow(summary: summary)
                    }
                }
                Text("Average observed score per match; compare teams within an event and verify your sample size.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let exportError {
                Section {
                    Label(exportError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let eventError {
                Section("Live event schedule") {
                    Label(eventError, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry event list") { Task { await loadEvents() } }
                }
            } else if isLoadingEvents {
                Section("Live event schedule") {
                    ProgressView("Loading FTCScout events…")
                }
            } else if !events.isEmpty {
                Section("Live event schedule") {
                    Text("\(events.count) events listed by FTCScout for \(season). Match scores are entered as team observations below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if visibleReports.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No scouting reports yet" : "No matching reports",
                    systemImage: searchText.isEmpty ? "binoculars" : "magnifyingglass",
                    description: Text(searchText.isEmpty
                        ? "Record observed match performance and robot capabilities. Reports stay on this device and sync through your configured Firebase project."
                        : "Try another team, event, or capability.")
                )
                .listRowSeparator(.hidden)
            } else {
                Section("Match observations · \(visibleReports.count)") {
                    ForEach(visibleReports) { report in
                        ScoutingReportRow(report: report)
                    }
                    .onDelete(perform: deleteReports)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Team, event, match, capability")
        .navigationTitle("Match Scouting")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    exportCSV()
                } label: {
                    Label("Export scouting CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(reports.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNewReport = true } label: {
                    Label("Record observation", systemImage: "plus")
                }
            }
        }
        .refreshable { await loadEvents() }
        .sheet(isPresented: $isPresentingNewReport) {
            NewScoutingReportSheet(events: events)
        }
        .sheet(item: $export) { file in
            ScoutingShareSheet(activityItems: [file.url])
                .ignoresSafeArea()
        }
        .task { await loadEvents() }
    }

    private func loadEvents() async {
        isLoadingEvents = true
        eventError = nil
        do {
            events = try await api.fetchEvents(season: season)
                .sorted { $0.start < $1.start }
        } catch {
            eventError = error.localizedDescription
        }
        isLoadingEvents = false
    }

    private func deleteReports(at offsets: IndexSet) {
        for index in offsets {
            let report = visibleReports[index]
            syncService?.deleteScoutingReport(id: report.id)
            context.delete(report)
        }
    }

    private func exportCSV() {
        do {
            export = ScoutingExport(url: try ScoutingCSVExporter.export(reports))
            exportError = nil
        } catch {
            exportError = "Could not export scouting reports: \(error.localizedDescription)"
        }
    }
}

private struct ScoutTeamSummaryRow: View {
    let summary: ScoutTeamSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(summary.teamName.isEmpty ? "Team #\(summary.teamNumber)" : "#\(summary.teamNumber) \(summary.teamName)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(summary.averageTotal, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                Text("avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(summary.eventName)
                Spacer()
                Text("\(summary.observations) observation\(summary.observations == 1 ? "" : "s")")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text("Auto \(summary.averageAuto, format: .number.precision(.fractionLength(1))) · TeleOp \(summary.averageTeleOp, format: .number.precision(.fractionLength(1))) · Endgame \(summary.averageEndgame, format: .number.precision(.fractionLength(1)))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

private enum ScoutingCSVExporter {
    static func export(_ reports: [ScoutingReport]) throws -> URL {
        let header = [
            "Team Number", "Team Name", "Event", "Match", "Autonomous Score",
            "TeleOp Score", "Endgame Score", "Total Observed Score",
            "Capabilities", "Notes", "Recorded By", "Observed At"
        ]
        let rows = reports.sorted { $0.observedAt < $1.observedAt }.map { report in
            [
                String(report.teamNumber), report.teamName, report.eventName, report.matchNumber,
                String(report.autonomousScore), String(report.teleOpScore), String(report.endgameScore),
                String(report.totalScore), report.capabilities.joined(separator: "; "),
                report.notes, report.recordedByName,
                report.observedAt.formatted(.iso8601)
            ].map(escape).joined(separator: ",")
        }
        let contents = ([header.joined(separator: ",")] + rows).joined(separator: "\r\n") + "\r\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ftc-scouting-\(UUID().uuidString).csv")
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    private static func escape(_ field: String) -> String {
        "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct ScoutingShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct ScoutingReportRow: View {
    let report: ScoutingReport

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.teamName.isEmpty ? "Team #\(report.teamNumber)" : "#\(report.teamNumber) \(report.teamName)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(report.totalScore) pts")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Text("\(report.eventName) · \(report.matchNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.capabilities.isEmpty {
                Text(report.capabilities.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
            }
            HStack {
                Text("Auto \(report.autonomousScore)  ·  TeleOp \(report.teleOpScore)  ·  Endgame \(report.endgameScore)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(report.observedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !report.notes.isEmpty {
                Text(report.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct NewScoutingReportSheet: View {
    let events: [FTCEventSummary]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    @State private var teamNumber = ""
    @State private var teamName = ""
    @State private var eventName = ""
    @State private var customEventName = ""
    @State private var matchNumber = ""
    @State private var autoScore = ""
    @State private var teleOpScore = ""
    @State private var endgameScore = ""
    @State private var capabilitiesInput = ""
    @State private var notes = ""

    private var parsedTeamNumber: Int? { Int(teamNumber) }
    private let customEventOption = "Enter event manually…"
    private var resolvedEventName: String {
        eventName == customEventOption ? customEventName : eventName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("Team number", text: $teamNumber)
                        .keyboardType(.numberPad)
                    TextField("Team name (optional)", text: $teamName)
                    if events.isEmpty {
                        TextField("Event name", text: $eventName)
                    } else {
                        Picker("Event", selection: $eventName) {
                            Text("Select event").tag("")
                            ForEach(events) { event in
                                Text(event.name).tag(event.name)
                            }
                            Text(customEventOption).tag(customEventOption)
                        }
                        if eventName == customEventOption {
                            TextField("Event name", text: $customEventName)
                        }
                    }
                    TextField("Match number (e.g. Q12)", text: $matchNumber)
                        .textInputAutocapitalization(.characters)
                }

                Section("Observed score") {
                    scoreField("Autonomous", value: $autoScore)
                    scoreField("TeleOp", value: $teleOpScore)
                    scoreField("Endgame", value: $endgameScore)
                    Text("Enter each observed phase score explicitly; use 0 only when you observed no points. Scores are not fetched from FTCScout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Robot observations") {
                    TextField("Capabilities (comma-separated)", text: $capabilitiesInput, axis: .vertical)
                    TextField("Notes, reliability, or strategy", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Scout Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!(parsedTeamNumber.map { $0 > 0 } ?? false) ||
                                  resolvedEventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  matchNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  !scoresAreValid)
                }
            }
        }
    }

    private var scoresAreValid: Bool {
        [autoScore, teleOpScore, endgameScore].allSatisfy(isNonNegativeInteger)
    }

    private func isNonNegativeInteger(_ value: String) -> Bool {
        guard let score = Int(value) else { return false }
        return score >= 0
    }

    private func scoreField(_ title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func save() {
        guard let user = authManager.currentUser, let number = parsedTeamNumber, scoresAreValid else { return }
        let capabilities = capabilitiesInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let report = ScoutingReport(
            teamNumber: number,
            teamName: teamName.trimmingCharacters(in: .whitespacesAndNewlines),
            eventName: resolvedEventName.trimmingCharacters(in: .whitespacesAndNewlines),
            matchNumber: matchNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            autonomousScore: Int(autoScore) ?? 0,
            teleOpScore: Int(teleOpScore) ?? 0,
            endgameScore: Int(endgameScore) ?? 0,
            capabilities: capabilities,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            recordedByID: user.id,
            recordedByName: user.name
        )
        context.insert(report)
        syncService?.pushScoutingReport(report)
        dismiss()
    }
}
