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
    @Environment(\.ftcScoutAPI) private var api

    @Query private var allTasks: [TaskItem]
    @Query private var batteries: [Battery]
    @Query private var inventoryItems: [InventoryItem]
    @Query private var testRuns: [TestRunRecord]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var activity: [ActivityEvent]
    @Query(sort: \ChecklistRun.timestamp, order: .reverse) private var checklistRuns: [ChecklistRun]

    @State private var nextEvent: FTCEventSummary?
    @State private var daysUntilEvent: Int?
    @State private var isLoadingEvent = true
    @State private var eventLoadError: String?
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

    private var batteriesNeedingAttention: [Battery] {
        batteries.filter { $0.status == .dead || $0.cycleCount > 40 }
    }

    private var inventoryNeedingAttention: [InventoryItem] {
        inventoryItems.filter { $0.isLowStock || $0.needsMaintenance }
    }

    private var todaysChecklist: ChecklistRun? {
        checklistRuns.first { Calendar.current.isDateInToday($0.timestamp) }
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
            ReadinessFactor(label: "Open tasks on schedule", isGood: overdueTasks.isEmpty, isTracked: !myOpenTasks.isEmpty),
            ReadinessFactor(label: "Batteries healthy", isGood: batteriesNeedingAttention.isEmpty, isTracked: !batteries.isEmpty),
            ReadinessFactor(label: "Inventory in good shape", isGood: inventoryNeedingAttention.isEmpty, isTracked: !inventoryItems.isEmpty),
            ReadinessFactor(label: "Pre-flight checklist done today", isGood: todaysChecklist != nil, isTracked: true)
        ]
    }

    private var readinessScore: Double {
        let tracked = readinessFactors.filter { $0.isTracked }
        guard !tracked.isEmpty else { return 1 }
        return Double(tracked.filter { $0.isGood }.count) / Double(tracked.count)
    }

    private var readinessHeadline: String {
        switch readinessScore {
        case 1: return "Everything's dialed in."
        case 0.75...: return "In great shape — a couple of things to tidy up."
        case 0.5..<0.75: return "On track, but a few things need attention."
        default: return "Several things need the team's attention."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    readinessCard
                    nextEventCard
                    sectionHeading("TEAM SNAPSHOT", detail: "Your operation at a glance")
                    statGrid
                    sectionHeading("PIT STATUS", detail: "Items that may need a hand")
                    if !batteriesNeedingAttention.isEmpty { batteryAlertCard }
                    if !inventoryNeedingAttention.isEmpty { inventoryAlertCard }
                    if todaysChecklist == nil { checklistNudgeCard }
                    sectionHeading("PERFORMANCE", detail: "Signals from your own practice data")
                    insightsSection
                    sectionHeading("LATEST UPDATES", detail: "Recent work from your crew")
                    recentActivitySection
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { router.selection = .calendar } label: {
                        Image(systemName: "calendar")
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
                            isPresentingSearch = true
                        } label: {
                            Label("Search team records", systemImage: "magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(FTCBrand.orange, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .accessibilityLabel("Create or find team records")
                }
            }
            .sheet(isPresented: $isPresentingSearch) { GlobalSearchView() }
            .sheet(isPresented: $isPresentingQuickLog) { QuickPracticeLogSheet() }
            .task { await loadNextEvent() }
            .refreshable { await loadNextEvent() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(FTCBrand.orange).frame(width: 7, height: 7)
                Text("WILD CIRCUITS     /     2026—27")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if let user = authManager.currentUser {
                    Text(user.initials)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 31, height: 31)
                        .background(user.avatarColor.color, in: Circle())
                }
            }
            Text(greeting)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(.primary)
            Text("Team 24211  ·  \(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var readinessCard: some View {
        FTCBrandCard {
            HStack(alignment: .center, spacing: 18) {
                ReadinessRing(score: readinessScore)
                VStack(alignment: .leading, spacing: 6) {
                    Text("TEAM READINESS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    Text(readinessHeadline)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(readinessFactors.filter { !$0.isGood && $0.isTracked }.prefix(2), id: \.label) { factor in
                            Label(factor.label, systemImage: "circle.fill")
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
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(FTCBrand.accentText)
                Text(detail)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
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
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(FTCBrand.midnight, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    if isLoadingEvent {
                        Text("Checking upcoming events…").font(.subheadline).foregroundStyle(.secondary)
                    } else if let event = nextEvent, let days = daysUntilEvent {
                        Text(event.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let eventLoadError {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upcoming events unavailable").font(.subheadline.weight(.medium))
                            Text(eventLoadError).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } else {
                        Text("No upcoming events published").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    router.selection = .calendar
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FTCBrand.accentText)
                }
                .accessibilityLabel("Open season calendar")
            }
            .padding(14)
        }
        .groupBoxStyle(DashboardGroupBoxStyle())
    }

    private func loadNextEvent() async {
        isLoadingEvent = true
        eventLoadError = nil
        nextEvent = nil
        daysUntilEvent = nil
        do {
            let season = Calendar.current.component(.year, from: .now)
            let events = try await api.fetchEvents(season: season)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")

            let upcoming = events.compactMap { event -> (FTCEventSummary, Date)? in
                guard let date = formatter.date(from: String(event.start.prefix(10))) else { return nil }
                return (event, date)
            }
            .filter { $0.1 >= Calendar.current.startOfDay(for: .now) }
            .sorted { $0.1 < $1.1 }

            if !events.isEmpty && upcoming.isEmpty &&
                events.allSatisfy({ formatter.date(from: String($0.start.prefix(10))) == nil }) {
                eventLoadError = "FTCScout returned event dates in an unexpected format."
            }
            if let soonest = upcoming.first {
                nextEvent = soonest.0
                daysUntilEvent = Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: .now),
                    to: Calendar.current.startOfDay(for: soonest.1)
                ).day
            }
        } catch {
            eventLoadError = error.localizedDescription
        }
        isLoadingEvent = false
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DashboardStatCard(
                title: "My Open Tasks", value: "\(myOpenTasks.count)",
                subtitle: overdueTasks.isEmpty ? nil : "\(overdueTasks.count) overdue",
                subtitleColor: .red, icon: "checklist", tint: .blue
            ) { router.selection = .tasks }

            DashboardStatCard(
                title: "Batteries Tracked", value: "\(batteries.count)",
                subtitle: batteriesNeedingAttention.isEmpty ? nil : "\(batteriesNeedingAttention.count) need attention",
                subtitleColor: .orange, icon: "battery.75", tint: .green
            ) { router.selection = .pitOps }

            DashboardStatCard(
                title: "Notebook & Ideas", value: "\(activity.filter { $0.kind == .notebookEntry || $0.kind == .ideaPosted }.count)",
                subtitle: "this season", subtitleColor: .secondary, icon: "book.closed", tint: .purple
            ) { router.selection = .notebook }

            DashboardStatCard(
                title: "Scout & Events", value: "Open", subtitle: "FTCScout + reports", subtitleColor: .secondary,
                icon: "antenna.radiowaves.left.and.right", tint: .indigo
            ) { router.selection = .liveData }
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trends are calculated on this device from records entered by your team.")
                .font(.caption2).foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .foregroundStyle(color(for: insight.tint))
                            .frame(width: 20)
                        Text(insight.text)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
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
                router.selection = .pitOps
            } label: {
                HStack {
                    Image(systemName: "checklist").foregroundStyle(.blue)
                    Text("No pre-flight checklist completed today")
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
            Text("Recent Activity").font(.headline)

            if activity.isEmpty {
                Text("No activity yet.").font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activity.prefix(6).enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 10) {
                            Image(systemName: event.systemImage)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 20)
                            (Text(event.authorName).fontWeight(.semibold) + Text(" \(event.message)"))
                                .font(.footnote)
                                .lineLimit(2)
                            Spacer()
                            Text(event.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        if index < min(activity.count, 6) - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct ReadinessRing: View {
    let score: Double

    private var tint: Color {
        switch score {
        case 0.75...: return .green
        case 0.5..<0.75: return FTCBrand.orange
        default: return .red
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0.02, score))
                .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((score * 100).rounded()))%")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("ready")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .animation(.easeInOut(duration: 0.4), value: score)
    }
}

private struct ReadinessBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            configuration.icon.font(.system(size: 4))
            configuration.title
        }
    }
}

private extension LabelStyle where Self == ReadinessBulletLabelStyle {
    static var readinessBullet: ReadinessBulletLabelStyle { ReadinessBulletLabelStyle() }
}

private struct DashboardStatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let subtitleColor: Color
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 31, height: 31)
                        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(subtitleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .frame(minHeight: 136, alignment: .topLeading)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(height: 3)
                    .padding(.horizontal, 14)
                    .padding(.top, 0)
                    .offset(y: -1.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct DashboardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.content
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.045), lineWidth: 1)
            }
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
                    LabeledContent("DATE", value: Date.now.formatted(date: .complete, time: .omitted))
                    TextField("Log title", text: $title, prompt: Text("What did you work on?"))
                    Picker("Area", selection: $area) {
                        ForEach(areas, id: \.self) { Text($0).tag($0) }
                    }
                } header: {
                    Text("PRACTICE LOG")
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
