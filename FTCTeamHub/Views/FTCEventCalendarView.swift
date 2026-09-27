import SwiftUI
import SwiftData

private struct FTCEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let date: Date
    let time: String
    let venue: String
    let address: String?
    let detail: String?
    let symbol: String
    let color: Color

    var notebookTag: String { "event:\(id)" }
    var notebookDisplayTag: String {
        "\(title) · \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    static let all: [FTCEvent] = {
        let calendar = Calendar(identifier: .gregorian)
        let definitions: [(String, Int, Int, Int, String, String, String, String?, String?, String, Color)] = [
            ("practice-2026-10-10", 2026, 10, 10, "Practice Event", "8:30 AM – 3:00 PM",
             "Rowan University", nil, "Practice event; does not impact league standings.",
             "figure.run", FTCBrand.cyan),
            ("league-2026-10-24", 2026, 10, 24, "1st League Meet", "8:30 AM – 4:30 PM",
             "Holmdel High School", "36 Crawfords Corner Rd, Holmdel, NJ 07733", nil,
             "trophy.fill", FTCBrand.blue),
            ("league-2026-11-15", 2026, 11, 15, "2nd League Meet", "8:30 AM – 4:30 PM",
             "Williamstown Middle School", "561 Clayton Rd, Williamstown, NJ", nil,
             "trophy.fill", FTCBrand.violet),
            ("league-2027-01-23", 2027, 1, 23, "3rd League Meet", "8:30 AM – 4:30 PM",
             "Howell High School", "405 Squankum Yellowbrook Rd, Farmingdale, NJ", nil,
             "trophy.fill", FTCBrand.blue),
            ("tournament-2027-02-27", 2027, 2, 27, "League Tournament", "8:30 AM – 4:30 PM",
             "North Burlington County Middle School", "160 Mansfield Rd East, Columbus, NJ 08022",
             "Championship day. Bring the robot, pit kit, charged batteries, and team notebook.",
             "trophy.fill", FTCBrand.orange)
        ]
        return definitions.compactMap { item in
            guard let date = calendar.date(from: DateComponents(year: item.1, month: item.2, day: item.3)) else {
                return nil
            }
            let kind = item.0.hasPrefix("practice") ? "PRACTICE"
                : item.0.hasPrefix("tournament") ? "TOURNAMENT" : "LEAGUE"
            return FTCEvent(id: item.0, title: item.4, kind: kind,
                            date: date, time: item.5, venue: item.6, address: item.7,
                            detail: item.8, symbol: item.9, color: item.10)
        }.sorted { $0.date < $1.date }
    }()
}

struct FTCEventCalendarView: View {
    @Environment(TabRouter.self) private var router
    @State private var displayedMonth = Self.initialMonth
    @State private var selectedDate = Self.initialDate
    @State private var selectedEvent: FTCEvent?

    private static var initialDate: Date {
        FTCEvent.all.first(where: { Calendar.current.startOfDay(for: $0.date) >= Calendar.current.startOfDay(for: .now) })?.date
            ?? FTCEvent.all.last?.date
            ?? .now
    }

    private static var initialMonth: Date {
        Calendar.current.dateInterval(of: .month, for: initialDate)?.start ?? initialDate
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthStart: Date {
        Calendar.current.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var monthTitle: String {
        monthStart.formatted(.dateTime.month(.wide).year())
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

    private var eventsOnSelectedDate: [FTCEvent] {
        FTCEvent.all.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var upcomingEvents: [FTCEvent] {
        FTCEvent.all.filter {
            Calendar.current.startOfDay(for: $0.date) >= Calendar.current.startOfDay(for: .now)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    seasonHeader
                    monthCalendar
                    selectedDaySection
                    upcomingSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 32)
            }
            .background(FTCBrand.background.ignoresSafeArea())
            .navigationTitle("Season Calendar")
            .navigationBarTitleDisplayMode(.inline)
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
    }

    private var seasonHeader: some View {
        FTCBrandCard {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WILD CIRCUITS  ·  FTC 2026–27")
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(FTCBrand.cyan)
                    Text("Show up.\nBuild together.")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(upcomingEvents.count) upcoming team events")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                FTCBrandMark(size: 66)
            }
        }
    }

    private var monthCalendar: some View {
        FTCBrandCard {
            VStack(spacing: 18) {
                HStack {
                    Button {
                        shiftMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Previous month")
                    Spacer()
                    Text(monthTitle)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    Button {
                        shiftMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 36, height: 36)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Next month")
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol.uppercased())
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white.opacity(0.48))
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                        if let day {
                            calendarDay(day)
                        } else {
                            Color.clear.frame(height: 42)
                        }
                    }
                }
                HStack(spacing: 7) {
                    Circle().fill(FTCBrand.orange).frame(width: 7, height: 7)
                    Text("Team event")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    Text("Tap a date to see the agenda")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    private func calendarDay(_ day: Date) -> some View {
        let event = FTCEvent.all.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
        let isSelected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDateInToday(day)
        return Button {
            selectedDate = day
            if let event { selectedEvent = event }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(.subheadline, design: .rounded, weight: isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(isSelected ? FTCBrand.midnight : .white)
                Circle()
                    .fill(event?.color ?? .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13).fill(FTCBrand.cyan)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 13).stroke(FTCBrand.cyan.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (event.map { ", \($0.title)" } ?? ""))
    }

    @ViewBuilder
    private var selectedDaySection: some View {
        if !eventsOnSelectedDate.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("Selected day", caption: selectedDate.formatted(date: .complete, time: .omitted))
                ForEach(eventsOnSelectedDate) { event in
                    eventCard(event, highlight: true)
                }
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Coming up", caption: "Make every meet count")
            if upcomingEvents.isEmpty {
                FTCBrandCard {
                    Label("The 2026–27 schedule is complete.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(FTCBrand.cyan)
                }
            } else {
                ForEach(upcomingEvents) { event in
                    eventCard(event, highlight: event == upcomingEvents.first)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.title2, design: .rounded, weight: .bold))
            Text(caption).font(.subheadline).foregroundStyle(.white.opacity(0.56))
        }
    }

    private func eventCard(_ event: FTCEvent, highlight: Bool) -> some View {
        Button {
            selectedEvent = event
        } label: {
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text(event.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(.caption2, design: .rounded, weight: .black))
                        .tracking(0.7)
                    Text(event.date.formatted(.dateTime.day()))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                }
                .foregroundStyle(event.color)
                .frame(width: 54, height: 58)
                .background(event.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(event.kind)
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(event.color)
                        if highlight && event == upcomingEvents.first {
                            Text("NEXT")
                                .font(.system(.caption2, design: .rounded, weight: .black))
                                .foregroundStyle(FTCBrand.midnight)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(FTCBrand.cyan, in: Capsule())
                        }
                    }
                    Text(event.title).font(.headline).foregroundStyle(.white)
                    Label(event.venue, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(highlight ? event.color.opacity(0.42) : .white.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(by amount: Int) {
        guard let candidate = Calendar.current.date(byAdding: .month, value: amount, to: monthStart),
              let first = FTCEvent.all.first,
              let last = FTCEvent.all.last,
              let firstMonth = Calendar.current.dateInterval(of: .month, for: first.date)?.start,
              let lastMonth = Calendar.current.dateInterval(of: .month, for: last.date)?.start,
              candidate >= firstMonth, candidate <= lastMonth else { return }
        displayedMonth = candidate
        if let firstDay = Calendar.current.dateInterval(of: .month, for: candidate)?.start {
            selectedDate = firstDay
        }
    }
}

private struct FTCEventDetailSheet: View {
    let event: FTCEvent
    @Query(sort: \NotebookEntry.timestamp, order: .reverse) private var allEntries: [NotebookEntry]
    @State private var isCreatingNote = false
    @State private var entryToEdit: NotebookEntry?

    private var eventNotes: [NotebookEntry] {
        allEntries.filter { $0.tags.contains(event.notebookTag) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    eventHero
                    locationCard
                    EventReadinessBoard(event: event)
                    meetingNotebook
                }
                .padding(18)
            }
            .background(FTCBrand.background.ignoresSafeArea())
            .navigationTitle("Event details")
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

    private var eventHero: some View {
        FTCBrandCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(event.kind, systemImage: event.symbol)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(event.color)
                    Spacer()
                    Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(.title3, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                }
                Text(event.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Label(event.date.formatted(.dateTime.weekday(.wide).year()), systemImage: "calendar")
                    .foregroundStyle(.white.opacity(0.78))
                Label(event.time, systemImage: "clock")
                    .foregroundStyle(.white.opacity(0.78))
                if let detail = event.detail {
                    Label(detail, systemImage: "info.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(FTCBrand.cyan)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var locationCard: some View {
        FTCBrandCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("VENUE", systemImage: "mappin.and.ellipse")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(FTCBrand.cyan)
                Text(event.venue).font(.headline).foregroundStyle(.white)
                if let address = event.address {
                    Text(address).font(.subheadline).foregroundStyle(.white.opacity(0.66))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var meetingNotebook: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Meeting notebook")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Design decisions, tests, results & next steps")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Button {
                    isCreatingNote = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(FTCBrand.midnight)
                        .frame(width: 38, height: 38)
                        .background(FTCBrand.cyan, in: Circle())
                }
                .accessibilityLabel("Add meeting note")
            }

            if eventNotes.isEmpty {
                FTCBrandCard {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 30))
                            .foregroundStyle(FTCBrand.cyan)
                        Text("A clean page for this meet")
                            .font(.headline)
                        Text("No notes yet. Start the engineering record when your team is ready.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.62))
                            .multilineTextAlignment(.center)
                        Button("Start meeting notebook") { isCreatingNote = true }
                            .buttonStyle(.borderedProminent)
                            .tint(FTCBrand.blue)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(eventNotes) { entry in
                    Button {
                        entryToEdit = entry
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(entry.title).font(.headline).foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "pencil").font(.caption).foregroundStyle(FTCBrand.cyan)
                            }
                            Text(entry.content.isEmpty ? "Tap to add your meeting record." : entry.content)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(3)
                            Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    isCreatingNote = true
                } label: {
                    Label("Add another entry", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FTCBrand.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct EventReadinessBoard: View {
    let event: FTCEvent
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
        FTCBrandCard {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("EVENT READY", systemImage: "checkmark.shield.fill")
                            .font(.system(.caption2, design: .rounded, weight: .black))
                            .tracking(1)
                            .foregroundStyle(FTCBrand.cyan)
                        Text("Pit crew checklist")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text("\(completedCount)/\(tasks.count)")
                        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(completedCount == tasks.count ? FTCBrand.cyan : .white.opacity(0.72))
                        .contentTransition(.numericText())
                }

                ProgressView(value: progress)
                    .tint(completedCount == tasks.count ? FTCBrand.cyan : FTCBrand.blue)
                    .animation(.spring(response: 0.35), value: completedCount)

                VStack(spacing: 2) {
                    ForEach(tasks, id: \.self) { task in
                        readinessRow(task)
                    }
                }

                if completedCount == tasks.count {
                    Label("Pit-ready. Go make it count.", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FTCBrand.cyan)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 3)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: completedCount == tasks.count)
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
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isComplete ? FTCBrand.cyan : .white.opacity(0.34))
                    .contentTransition(.symbolEffect(.replace))
                Text(task)
                    .font(.subheadline)
                    .foregroundStyle(isComplete ? .white.opacity(0.48) : .white.opacity(0.88))
                    .strikethrough(isComplete, color: .white.opacity(0.34))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task)
        .accessibilityAddTraits(isComplete ? .isSelected : [])
        .accessibilityHint(isComplete ? "Mark as not done" : "Mark as done")
    }
}

private struct MeetingNoteEditor: View {
    let event: FTCEvent
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

    init(event: FTCEvent, existingEntry: NotebookEntry? = nil) {
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
            .scrollContentBackground(.hidden)
            .background(FTCBrand.background)
            .navigationTitle(existingEntry == nil ? "New Meeting Note" : "Edit Meeting Note")
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
            .alert("Couldn’t save meeting notes", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
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
            existingEntry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            existingEntry.content = content
            existingEntry.timestamp = .now
            if !existingEntry.tags.contains(event.notebookTag) {
                existingEntry.tags.append(event.notebookTag)
            }
            if !existingEntry.tags.contains(event.notebookDisplayTag) {
                existingEntry.tags.append(event.notebookDisplayTag)
            }
            entry = existingEntry
        } else {
            entry = NotebookEntry(authorID: author.id, authorName: author.name,
                                  title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                  content: content,
                                  tags: ["Meeting Notes", event.notebookDisplayTag, event.notebookTag])
            context.insert(entry)
        }
        do {
            try context.save()
            syncService?.pushNotebookEntry(entry)
        } catch {
            saveError = error.localizedDescription
            return
        }
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
