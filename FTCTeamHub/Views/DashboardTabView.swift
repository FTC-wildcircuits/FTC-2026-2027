//
//  DashboardTabView.swift
//  FTCTeamHub
//
//  The team's home screen: next event, snapshot stats, pit alerts,
//  performance insights, and recent activity.
//

import SwiftUI
import SwiftData

struct DashboardTabView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(TabRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var allTasks: [TaskItem]
    @Query private var batteries: [Battery]
    @Query private var inventoryItems: [InventoryItem]
    @Query private var testRuns: [TestRunRecord]
    @Query private var scoutingReports: [ScoutingReport]
    @Query private var notebookEntries: [NotebookEntry]
    @Query private var ideas: [Idea]
    @Query private var teamSettingsList: [TeamSettings]
    @Query(sort: \TeamEventRecord.startsAt) private var teamEvents: [TeamEventRecord]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var activity: [ActivityEvent]
    @Query(sort: \ChecklistRun.timestamp, order: .reverse) private var checklistRuns: [ChecklistRun]

    @State private var isPresentingSearch = false
    @State private var isPresentingQuickLog = false

    private var myOpenTasks: [TaskItem] {
        guard let uid = authManager.currentUser?.id else { return [] }
        return allTasks.filter { $0.assignedToID == uid && $0.status != .done }
    }

    private var inventoryAlertCard: some View {
        GroupBox {
            Button {
                router.selection = .inventory
            } label: {
                HStack {
                    Image(systemName: "shippingbox.fill").foregroundStyle(.orange)
                    Text("\(inventoryNeedingAttention.count) inventory item\(inventoryNeedingAttention.count == 1 ? "" : "s") low or needing maintenance")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var overdueTasks: [TaskItem] {
        myOpenTasks.filter { ($0.deadline ?? .distantFuture) < .now }
    }

    private var hasOverdueTeamTasks: Bool {
        allTasks.contains {
            $0.status != .done && ($0.deadline ?? .distantFuture) < .now
        }
    }

    private var batteriesNeedingAttention: [Battery] {
        batteries.filter { $0.status == .dead || $0.cycleCount > 40 }
    }

    private var inventoryNeedingAttention: [InventoryItem] {
        inventoryItems.filter { $0.isLowStock || $0.needsMaintenance }
    }

    private var todaysPreFlightChecklist: ChecklistRun? {
        checklistRuns.first {
            $0.type == .preFlight && Calendar.current.isDateInToday($0.timestamp)
        }
    }

    private var hasTrackedPreFlightChecklist: Bool {
        checklistRuns.contains { $0.type == .preFlight }
    }

    private var nextTeamEvent: TeamEventRecord? {
        let today = Calendar.current.startOfDay(for: .now)
        return teamEvents.first { Calendar.current.startOfDay(for: $0.startsAt) >= today }
    }

    private var nextEventCountdown: String? {
        guard let nextTeamEvent,
              let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: .now),
                to: Calendar.current.startOfDay(for: nextTeamEvent.startsAt)
              ).day else { return nil }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days) days"
    }

    private var teamName: String {
        let name = teamSettingsList.first?.teamName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name
    }

    private var insights: [Insight] {
        InsightsEngine.generate(testRuns: testRuns, batteries: batteries, tasks: allTasks)
    }

    // MARK: - Readiness

    private struct ReadinessFactor {
        let label: String
        let isGood: Bool
        let isTracked: Bool
    }

    private var readinessFactors: [ReadinessFactor] {
        [
            ReadinessFactor(label: "Open tasks on schedule", isGood: !hasOverdueTeamTasks, isTracked: !allTasks.isEmpty),
            ReadinessFactor(label: "Batteries healthy", isGood: batteriesNeedingAttention.isEmpty, isTracked: !batteries.isEmpty),
            ReadinessFactor(label: "Inventory in good shape", isGood: inventoryNeedingAttention.isEmpty, isTracked: !inventoryItems.isEmpty),
            ReadinessFactor(label: "Pre-flight checklist done today",
                            isGood: todaysPreFlightChecklist?.allChecked == true,
                            isTracked: hasTrackedPreFlightChecklist)
        ]
    }

    private var readinessScore: Double? {
        let tracked = readinessFactors.filter { $0.isTracked }
        guard !tracked.isEmpty else { return nil }
        return Double(tracked.filter { $0.isGood }.count) / Double(tracked.count)
    }

    private var readinessHeadline: String {
        guard let readinessScore else {
            return "Add your first team task or checklist to track readiness."
        }
        switch readinessScore {
        case 1: return "All tracked checks are clear."
        case 0.75...: return "Most checks are clear."
        case 0.5..<0.75: return "Some checks need a review."
        default: return "Several tracked checks need attention."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    readinessCard
                    nextEventCard
                    sectionHeading("Team snapshot", detail: "At a glance")
                    statGrid
                    sectionHeading("Needs attention", detail: "Equipment and preparation")
                    if !batteriesNeedingAttention.isEmpty { batteryAlertCard }
                    if !inventoryNeedingAttention.isEmpty { inventoryAlertCard }
                    if todaysPreFlightChecklist?.allChecked != true { checklistNudgeCard }
                    sectionHeading("Practice insights", detail: "Based on your recorded data")
                    insightsSection
                    sectionHeading("Recent activity", detail: "Latest team updates")
                    recentActivitySection
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { router.selection = .calendar } label: {
                        Image(systemName: "calendar")
                            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                    }
                    .accessibilityLabel("Season calendar")
                    Menu {
                        Button {
                            isPresentingQuickLog = true
                        } label: {
                            Label("New practice log", systemImage: "square.and.pencil")
                        }
                        Button {
                            router.selection = .notebook
                        } label: {
                            Label("Open engineering notebook", systemImage: "book.closed")
                        }
                        Button {
                            router.selection = .scoutingReports
                        } label: {
                            Label("Record match observation", systemImage: "scope")
                        }
                        Button {
                            router.selection = .tasks
                        } label: {
                            Label("Open team tasks", systemImage: "checklist")
                        }
                        Button {
                            router.selection = .inventory
                        } label: {
                            Label("Open pit inventory", systemImage: "shippingbox")
                        }
                        Button {
                            router.selection = .checklists
                        } label: {
                            Label("Run a pit checklist", systemImage: "checklist")
                        }
                        Button {
                            isPresentingSearch = true
                        } label: {
                            Label("Search team records", systemImage: "magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(RoundedRectangle(cornerRadius: FTCDesign.controlRadius, style: .continuous))
                    .accessibilityLabel("Create or find team records")
                }
            }
            .sheet(isPresented: $isPresentingSearch) { GlobalSearchView() }
            .sheet(isPresented: $isPresentingQuickLog) { QuickPracticeLogSheet() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !teamName.isEmpty {
                Text(teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if let user = authManager.currentUser {
                    Text(user.initials)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: FTCDesign.minimumHitTarget, height: FTCDesign.minimumHitTarget)
                        .background(user.avatarColor.color.opacity(0.18), in: Circle())
                }
            }
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            if let settings = teamSettingsList.first {
                Text("FTC \(settings.seasonName) · Team \(settings.teamNumber) · \(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readinessCard: some View {
        FTCBrandCard {
            HStack(alignment: .center, spacing: 18) {
                ReadinessRing(score: readinessScore)
                VStack(alignment: .leading, spacing: 6) {
                    Text(readinessScore == nil ? "Readiness not tracked" : "Team readiness")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(readinessHeadline)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(readinessFactors.filter { !$0.isGood && $0.isTracked }.prefix(2), id: \.label) { factor in
                            Label(factor.label, systemImage: "exclamationmark.circle")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .labelStyle(.readinessBullet)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = authManager.currentUser?.name.split(separator: " ").first.map(String.init) ?? "there"
        switch hour {
        case 0..<12: return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
    }

    // MARK: - Next event

    @ViewBuilder
    private var nextEventCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: FTCDesign.space8) {
                Label("Next event", systemImage: "calendar")
                    .font(.headline)
                if let event = nextTeamEvent {
                    Text(event.title)
                        .font(.body.weight(.semibold))
                    LabeledContent("Date", value: event.startsAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    LabeledContent("Time", value: event.timeDescription)
                    LabeledContent("Location", value: event.venue)
                    if let countdown = nextEventCountdown {
                        Text(countdown)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if teamEvents.isEmpty {
                    ContentUnavailableView("No team events", systemImage: "calendar",
                                           description: Text("The season calendar is empty."))
                } else {
                    Text("No upcoming events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .groupBoxStyle(DashboardGroupBoxStyle())
        .contentShape(Rectangle())
        .onTapGesture { router.selection = .calendar }
        .accessibilityHint("Opens the season calendar")
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        VStack(spacing: 0) {
            dashboardMetric("My open tasks", count: myOpenTasks.count,
                            detail: overdueTasks.isEmpty ? nil : "\(overdueTasks.count) overdue",
                            symbol: "checklist", tab: .tasks, tint: overdueTasks.isEmpty ? .secondary : .red)
            Divider()
            dashboardMetric("Batteries", count: batteries.count,
                            detail: batteriesNeedingAttention.isEmpty ? nil : "\(batteriesNeedingAttention.count) need attention",
                            symbol: "battery.75", tab: .pitOps,
                            tint: batteriesNeedingAttention.isEmpty ? .secondary : .orange)
            Divider()
            dashboardMetric("Notebook entries", count: notebookEntries.count,
                            detail: "\(ideas.count) ideas", symbol: "book.closed",
                            tab: .workHome, tint: .secondary)
            Divider()
            dashboardMetric("Match reports", count: scoutingReports.count,
                            detail: "Team observations", symbol: "scope",
                            tab: .scoutingReports, tint: .secondary)
        }
        .padding(.horizontal, FTCDesign.space16)
        .background(FTCDesign.secondarySurface,
                    in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous))
    }

    private func dashboardMetric(
        _ title: String,
        count: Int,
        detail: String?,
        symbol: String,
        tab: AppTab,
        tint: Color
    ) -> some View {
        Button {
            router.selection = tab
        } label: {
            HStack(spacing: FTCDesign.space12) {
                Label(title, systemImage: symbol)
                    .font(.body)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(FTCDesign.label)
                Spacer(minLength: FTCDesign.space8)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                }
                Text(count, format: .number)
                    .font(.body.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(FTCDesign.label)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FTCDesign.tertiaryLabel)
            }
            .frame(minHeight: FTCDesign.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title.lowercased())")
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: FTCDesign.space8) {
            Text("Trends are calculated on this device from records entered by your team.")
                .font(.caption2).foregroundStyle(.tertiary)

            VStack(spacing: 0) {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .foregroundStyle(color(for: insight.tint))
                        Text(insight.text)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, FTCDesign.space12)
                    if insight.id != insights.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, FTCDesign.space16)
            .background(FTCDesign.secondarySurface,
                        in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous))
        }
    }

    private func color(for tint: InsightTint) -> Color {
        switch tint {
        case .positive: return .green
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    // MARK: - Alerts

    private var batteryAlertCard: some View {
        GroupBox {
            Button {
                router.selection = .pitOps
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(batteriesNeedingAttention.count) battery\(batteriesNeedingAttention.count == 1 ? "" : "ies") need attention")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var checklistNudgeCard: some View {
        GroupBox {
            Button {
                router.selection = .checklists
            } label: {
                HStack {
                    Image(systemName: "checklist").foregroundStyle(Color.accentColor)
                    Text(todaysPreFlightChecklist == nil
                         ? "No pre-flight checklist completed today"
                         : "Finish all pre-flight checks before practice")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recent activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent activity").font(.headline)

            if activity.isEmpty {
                Text("No activity yet.").font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activity.prefix(6).enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 10) {
                            Image(systemName: event.systemImage)
                                .foregroundStyle(Color.accentColor)
                            (Text(event.authorName).fontWeight(.semibold) + Text(" \(event.message)"))
                                .font(.footnote)
                                .lineLimit(2)
                            Spacer()
                            Text(event.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, FTCDesign.space12)
                        if index < min(activity.count, 6) - 1 { Divider() }
                    }
                }
                .padding(.horizontal, FTCDesign.space16)
                .background(FTCDesign.secondarySurface,
                            in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous))
            }
        }
    }
}

private struct ReadinessRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let score: Double?

    private var tint: Color {
        guard let score else { return .secondary }
        switch score {
        case 0.75...: return .green
        case 0.5..<0.75: return .orange
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 9)
            if let score {
                Circle()
                    .trim(from: 0, to: max(0.02, score))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(score.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.headline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                Text("ready")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28),
            value: score
        )
    }
}

private struct ReadinessBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.font(.caption2)
            configuration.title
        }
    }
}

private extension LabelStyle where Self == ReadinessBulletLabelStyle {
    static var readinessBullet: ReadinessBulletLabelStyle { ReadinessBulletLabelStyle() }
}

private struct DashboardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .padding(FTCDesign.space16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                FTCDesign.secondarySurface,
                in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous)
            )
    }
}

private struct QuickPracticeLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    @State private var title = ""
    @State private var area = "Robot"
    @State private var observation = ""
    @State private var followUp = ""
    @State private var saveError: String?

    private let areas = ["Robot", "Software", "Autonomous", "Drive practice", "Pit"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Date", value: Date.now.formatted(date: .complete, time: .omitted))
                    TextField("Log title", text: $title, prompt: Text("What did you work on?"))
                    Picker("Area", selection: $area) {
                        ForEach(areas, id: \.self) { Text($0).tag($0) }
                    }
                } footer: {
                    Text("Saved to the engineering notebook and tagged for search.")
                }

                Section("Observation / result") {
                    TextEditor(text: $observation)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if observation.isEmpty {
                                Text("What happened? Record measurements, behavior, or decisions.")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                Section("Next test") {
                    TextEditor(text: $followUp)
                        .frame(minHeight: 85)
                        .overlay(alignment: .topLeading) {
                            if followUp.isEmpty {
                                Text("What will the team try next?")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Practice Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard let author = authManager.currentUser else {
            saveError = "Sign in to save a practice log."
            return
        }
        var content = "## Observation / result\n\(observation.trimmingCharacters(in: .whitespacesAndNewlines))"
        if !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content += "\n\n## Next test\n\(followUp.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        let entry = NotebookEntry(
            authorID: author.id,
            authorName: author.name,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            tags: ["Practice Log", area]
        )
        context.insert(entry)
        let activity = ActivityEvent(
            authorID: author.id,
            authorName: author.name,
            kind: .notebookEntry,
            message: "added a \(area.lowercased()) practice log: \(entry.title)"
        )
        context.insert(activity)
        do {
            try context.save()
            syncService?.pushNotebookEntry(entry)
            syncService?.pushActivity(activity)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    let router = TabRouter()
    return DashboardTabView()
        .modelContainer(container)
        .environment(authManager)
        .environment(router)
        .environment(\.ftcScoutAPI, LiveFTCScoutAPIClient())
}
