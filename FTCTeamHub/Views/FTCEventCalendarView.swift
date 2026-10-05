import SwiftUI
import SwiftData

private extension TeamEventRecord {
    var date: Date { startsAt }
    var kind: String { category }
    var time: String { timeDescription }
    var addressText: String? { address.isEmpty ? nil : address }
    var detail: String? { details.isEmpty ? nil : details }
    var symbol: String { category == "Practice" ? "figure.run" : "trophy" }
    var labelColor: Color { .accentColor }
    var notebookTag: String { "event:\(id)" }
    var notebookDisplayTag: String {
        "\(title) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }
}

struct FTCEventCalendarView: View {
    @Environment(TabRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \TeamEventRecord.startsAt) private var events: [TeamEventRecord]
    @Query private var teamSettingsList: [TeamSettings]
    @State private var displayedMonth: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedEvent: TeamEventRecord?

    private let columns = Array(repeating: GridItem(.flexible(minimum: FTCDesign.minimumHitTarget), spacing: 0), count: 7)

    private var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.month(.wide).year())
    }

    private var teamName: String {
        let name = teamSettingsList.first?.teamName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name
    }

    private var monthDays: [Date?] {
        guard let range = Calendar.current.range(of: .day, in: .month, for: monthStart) else { return [] }
        let firstWeekday = Calendar.current.component(.weekday, from: monthStart)
        let offset = (firstWeekday - Calendar.current.firstWeekday + 7) % 7
        let leading = Array<Date?>(repeating: nil, count: offset)
        let days = range.compactMap { Calendar.current.date(byAdding: .day, value: $0 - 1, to: monthStart) }
            .map(Optional.some)
        return leading + days
    }

    private var weekdaySymbols: [String] {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        let start = Calendar.current.firstWeekday - 1
        return (0..<symbols.count).map { symbols[(start + $0) % symbols.count] }
    }

    private var eventsOnSelectedDate: [TeamEventRecord] {
        events.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var upcomingEvents: [TeamEventRecord] {
        events.filter {
            Calendar.current.startOfDay(for: $0.date) >= Calendar.current.startOfDay(for: .now)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FTCDesign.space24) {
                    seasonHeader
                    monthCalendar
                    selectedDaySection
                    upcomingSection
                }
                .padding(.horizontal, FTCDesign.space16)
                .padding(.top, FTCDesign.space8)
                .padding(.bottom, FTCDesign.space24)
            }
            .background(FTCDesign.groupedBackground.ignoresSafeArea())
            .navigationTitle("Season Calendar")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.selection = .notebook
                    } label: {
                        Image(systemName: "book.closed.fill")
                    }
                    .accessibilityLabel("Open engineering notebook")
                }
            }
            .sheet(item: $selectedEvent) { event in
                FTCEventDetailSheet(event: event)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            if let next = upcomingEvents.first {
                selectedDate = Calendar.current.startOfDay(for: next.date)
                displayedMonth = Calendar.current.dateInterval(of: .month, for: next.date)?.start ?? next.date
            }
        }
    }

    private var seasonHeader: some View {
        VStack(alignment: .leading, spacing: FTCDesign.space4) {
            Text(teamName.isEmpty ? "Season calendar" : teamName)
                .font(.largeTitle.weight(.bold))
            if let seasonName = teamSettingsList.first?.seasonName {
                Text(seasonName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(upcomingEvents.count) upcoming events")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var monthCalendar: some View {
        FTCBrandCard {
            VStack(spacing: FTCDesign.space16) {
                HStack {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                    }
                    .accessibilityLabel("Previous month")
                    Spacer()
                    Text(monthTitle)
                        .font(.headline)
                    Spacer()
                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                    }
                    .accessibilityLabel("Next month")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: FTCDesign.space4) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                    }
                    ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            calendarDay(day)
                        } else {
                            Color.clear
                                .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                        }
                    }
                    }
                    .frame(minWidth: FTCDesign.minimumHitTarget * 7)
                }
                HStack(spacing: FTCDesign.space8) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                    Text("Scheduled event")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Select a date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func calendarDay(_ day: Date) -> some View {
        let event = events.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            selectedDate = day
            if let event { selectedEvent = event }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                if event != nil {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Color.clear.frame(width: FTCDesign.space12, height: FTCDesign.space12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: FTCDesign.controlRadius)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                } else if isToday {
                    RoundedRectangle(cornerRadius: FTCDesign.controlRadius).stroke(Color.accentColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (event.map { ", \($0.title)" } ?? ""))
    }

    @ViewBuilder
    private var selectedDaySection: some View {
        if !eventsOnSelectedDate.isEmpty {
            VStack(alignment: .leading, spacing: FTCDesign.space12) {
                sectionTitle("Selected day", caption: selectedDate.formatted(date: .complete, time: .omitted))
                ForEach(Array(eventsOnSelectedDate.enumerated()), id: \.element.id) { index, event in
                    eventRow(event, highlight: true)
                    if index < eventsOnSelectedDate.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: FTCDesign.space12) {
            sectionTitle("Coming up", caption: "Upcoming events")
            if upcomingEvents.isEmpty {
                ContentUnavailableView("No upcoming events", systemImage: "calendar",
                                       description: Text("The saved event schedule has no future dates."))
            } else {
                ForEach(Array(upcomingEvents.enumerated()), id: \.element.id) { index, event in
                    eventRow(event, highlight: event == upcomingEvents.first)
                    if index < upcomingEvents.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: FTCDesign.space4) {
            Text(title).font(.title2.weight(.semibold))
            Text(caption).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func eventRow(_ event: TeamEventRecord, highlight: Bool) -> some View {
        Button {
            selectedEvent = event
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(event.date.formatted(.dateTime.month(.abbreviated)))
                        .font(.caption.weight(.semibold))
                    Text(event.date.formatted(.dateTime.day()))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(Color.accentColor)
                .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(event.kind)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(event.labelColor)
                        if highlight && event == upcomingEvents.first {
                            Text("Next")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(event.title).font(.headline).foregroundStyle(.primary)
                    Label(event.venue, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, FTCDesign.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: FTCDesign.minimumHitTarget)
        .contextMenu {
            Button {
                selectedEvent = event
            } label: {
                Label("View event", systemImage: "calendar")
            }
        }
    }

    private func shiftMonth(by amount: Int) {
        guard let candidate = Calendar.current.date(byAdding: .month, value: amount, to: monthStart) else { return }
        displayedMonth = candidate
        if !Calendar.current.isDate(selectedDate, equalTo: candidate, toGranularity: .month),
           let firstDay = Calendar.current.dateInterval(of: .month, for: candidate)?.start {
            selectedDate = firstDay
        }
    }
}

private struct FTCEventDetailSheet: View {
    let event: TeamEventRecord
    @Query(sort: \NotebookEntry.timestamp, order: .reverse) private var allEntries: [NotebookEntry]
    @State private var isCreatingNote = false
    @State private var entryToEdit: NotebookEntry?

    private var eventNotes: [NotebookEntry] {
        allEntries.filter { $0.tags.contains(event.notebookTag) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Event") {
                    LabeledContent("Category", value: event.category)
                    LabeledContent("Date", value: event.date.formatted(date: .complete, time: .omitted))
                    LabeledContent("Time", value: event.time)
                    if !event.details.isEmpty {
                        Text(event.details)
                    }
                }
                Section("Location") {
                    Label(event.venue, systemImage: "mappin.and.ellipse")
                    if let address = event.addressText {
                        Text(address)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Event readiness") {
                    EventReadinessBoard(event: event)
                }
                Section("Meeting notebook") {
                    if eventNotes.isEmpty {
                        ContentUnavailableView("No meeting notes", systemImage: "book.closed",
                                               description: Text("Add design decisions, test results, and next steps."))
                    } else {
                        ForEach(eventNotes) { entry in
                            Button {
                                entryToEdit = entry
                            } label: {
                                VStack(alignment: .leading, spacing: FTCDesign.space4) {
                                    Text(entry.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if !entry.content.isEmpty {
                                        Text(entry.content)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    entryToEdit = entry
                                } label: {
                                    Label("Edit note", systemImage: "pencil")
                                }
                            }
                        }
                    }
                    Button {
                        isCreatingNote = true
                    } label: {
                        Label("Add meeting note", systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isCreatingNote) {
                MeetingNoteEditor(event: event)
                    .presentationDetents([.large])
            }
            .sheet(item: $entryToEdit) { entry in
                MeetingNoteEditor(event: event, existingEntry: entry)
                    .presentationDetents([.large])
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

private struct EventReadinessBoard: View {
    let event: TeamEventRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("eventReadiness.completedItems") private var completedRaw = ""

    private let tasks = [
        "Confirm team attendance & rides",
        "Run a full robot inspection",
        "Test robot code and driver controls",
        "Charge and label all batteries",
        "Pack tools, pit kit, and spare parts",
        "Pack Driver Hub, Control Hub, and chargers",
        "Bring engineering notebook and inspection docs",
        "Save a backup of the competition code"
    ]

    private var completedItems: Set<String> {
        Set(completedRaw.split(separator: "\n").map(String.init))
    }

    private var eventItems: [String] {
        tasks.map { "\(event.id)::\($0)" }
    }

    private var completedCount: Int {
        eventItems.filter { completedItems.contains($0) }.count
    }

    private var progress: Double {
        Double(completedCount) / Double(tasks.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FTCDesign.space16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: FTCDesign.space4) {
                    Label("Event checklist", systemImage: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Pit crew checklist")
                        .font(.headline)
                }
                Spacer()
                Text("\(completedCount)/\(tasks.count)")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(completedCount == tasks.count ? .green : .primary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }

            ProgressView(value: progress)
                .tint(completedCount == tasks.count ? .green : Color.accentColor)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28),
                    value: completedCount
                )

            VStack(spacing: FTCDesign.space4) {
                ForEach(tasks, id: \.self) { task in
                    readinessRow(task)
                }
            }

            if completedCount == tasks.count {
                Label("All checklist items are complete", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, FTCDesign.space4)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, FTCDesign.space8)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28),
            value: completedCount == tasks.count
        )
        .sensoryFeedback(.selection, trigger: completedCount)
    }

    private func readinessRow(_ task: String) -> some View {
        let key = "\(event.id)::\(task)"
        let isComplete = completedItems.contains(key)
        return Button {
            var updated = completedItems
            if isComplete {
                updated.remove(key)
            } else {
                updated.insert(key)
            }
            completedRaw = updated.sorted().joined(separator: "\n")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isComplete ? .green : .secondary)
                Text(task)
                    .font(.subheadline)
                    .foregroundStyle(isComplete ? .secondary : .primary)
                    .strikethrough(isComplete)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: FTCDesign.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task)
        .accessibilityAddTraits(isComplete ? .isSelected : [])
        .accessibilityHint(isComplete ? "Mark as not done" : "Mark as done")
    }
}

private struct MeetingNoteEditor: View {
    let event: TeamEventRecord
    var existingEntry: NotebookEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var title: String
    @State private var objective = ""
    @State private var workCompleted = ""
    @State private var results = ""
    @State private var nextSteps = ""
    @State private var saveError: String?
    @State private var pendingEntry: NotebookEntry?
    @State private var isConfirmingDiscard = false

    init(event: TeamEventRecord, existingEntry: NotebookEntry? = nil) {
        self.event = event
        self.existingEntry = existingEntry
        _title = State(initialValue: existingEntry?.title ?? "\(event.title) — Engineering Notes")
        let sections = Self.parse(existingEntry?.content ?? "")
        _objective = State(initialValue: sections["Objective"] ?? "")
        _workCompleted = State(initialValue: sections["Work completed"] ?? "")
        _results = State(initialValue: sections["Results & observations"] ?? "")
        _nextSteps = State(initialValue: sections["Next steps"] ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meeting") {
                    LabeledContent("Event", value: event.title)
                    LabeledContent("Date", value: event.date.formatted(date: .complete, time: .omitted))
                    TextField("Entry title", text: $title)
                }
                noteSection("Objective", prompt: "What did the team plan to accomplish?", text: $objective)
                noteSection("Work completed", prompt: "Build changes, tests, decisions, and contributors…", text: $workCompleted)
                noteSection("Results & observations", prompt: "What worked? Record measurements and evidence…", text: $results)
                noteSection("Next steps", prompt: "Action items, owners, and follow-up tests…", text: $nextSteps)
            }
            .navigationTitle(existingEntry == nil ? "New Meeting Note" : "Edit Meeting Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if pendingEntry == nil {
                            dismiss()
                        } else {
                            isConfirmingDiscard = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog("Discard this meeting note?", isPresented: $isConfirmingDiscard) {
                Button("Discard note", role: .destructive, action: discardPendingEntry)
                Button("Continue editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(pendingEntry != nil)
            .alert("Couldn’t save meeting notes", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("Retry", action: save)
                Button("Continue editing", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "Please try again.")
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (existingEntry != nil || [objective, workCompleted, results, nextSteps]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func noteSection(_ heading: String, prompt: String, text: Binding<String>) -> some View {
        Section(heading) {
            TextEditor(text: text)
                .frame(minHeight: 95)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(prompt)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private func save() {
        guard let author = authManager.currentUser else {
            saveError = "Sign in to save meeting notes."
            return
        }
        let sections = [
            ("Objective", objective),
            ("Work completed", workCompleted),
            ("Results & observations", results),
            ("Next steps", nextSteps)
        ]
        let content = sections
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "## \($0.0)\n\($0.1.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n\n")

        let entry: NotebookEntry
        if let existingEntry {
            entry = existingEntry
        } else if let pendingEntry {
            entry = pendingEntry
        } else {
            entry = NotebookEntry(authorID: author.id, authorName: author.name, title: "", content: "")
            context.insert(entry)
            pendingEntry = entry
        }
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.content = content
        entry.timestamp = .now
        if !entry.tags.contains("Meeting Notes") {
            entry.tags.append("Meeting Notes")
        }
        if !entry.tags.contains(event.notebookTag) {
            entry.tags.append(event.notebookTag)
        }
        if !entry.tags.contains(event.notebookDisplayTag) {
            entry.tags.append(event.notebookDisplayTag)
        }
        do {
            try context.save()
            syncService?.pushNotebookEntry(entry)
        } catch {
            saveError = error.localizedDescription
            return
        }
        pendingEntry = nil
        dismiss()
    }

    private func discardPendingEntry() {
        guard let pendingEntry else {
            dismiss()
            return
        }
        context.delete(pendingEntry)
        self.pendingEntry = nil
        dismiss()
    }

    private static func parse(_ content: String) -> [String: String] {
        let headings = ["Objective", "Work completed", "Results & observations", "Next steps"]
        var result: [String: String] = [:]
        for (index, heading) in headings.enumerated() {
            let marker = "## \(heading)\n"
            guard let start = content.range(of: marker)?.upperBound else { continue }
            let tail = content[start...]
            let end = headings.dropFirst(index + 1)
                .compactMap { tail.range(of: "\n\n## \($0)")?.lowerBound }
                .first
            result[heading] = String(end.map { tail[..<$0] } ?? tail[...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}

#Preview("Season calendar · Light") {
    let container = makePreviewContainer()
    return FTCEventCalendarView()
        .modelContainer(container)
        .environment(TabRouter())
        .preferredColorScheme(.light)
}

#Preview("Season calendar · Dark") {
    let container = makePreviewContainer()
    return FTCEventCalendarView()
        .modelContainer(container)
        .environment(TabRouter())
        .preferredColorScheme(.dark)
}

#Preview("Season calendar · Accessibility") {
    let container = makePreviewContainer()
    return FTCEventCalendarView()
        .modelContainer(container)
        .environment(TabRouter())
        .dynamicTypeSize(.accessibility5)
}
