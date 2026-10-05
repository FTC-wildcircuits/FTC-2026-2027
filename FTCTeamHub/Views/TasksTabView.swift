//
//  TasksTabView.swift
//  FTCTeamHub
//
//  Team task board with list and week-agenda calendar views, grouped
//  by deadline.
//

import SwiftUI
import SwiftData
import UIKit

struct TasksTabView: View {
    @Query(sort: \TaskItem.dateCreated, order: .reverse) private var allTasks: [TaskItem]
    @Query(sort: \AppUser.name) private var users: [AppUser]
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewMode: ViewMode = .myTasks
    @State private var isPresentingNewTask = false
    @State private var filterTag: String?
    @State private var completedTask: CompletedTaskSnapshot?
    @State private var pendingTaskWrite: PendingTaskWrite?
    @State private var taskSaveError: String?
    @State private var taskCompletionFeedbackCount = 0

    private struct CompletedTaskSnapshot: Identifiable {
        let id: UUID
        let task: TaskItem
        let originalStatus: TaskStatus
        let originalLastModified: Date
        let completedLastModified: Date
    }

    private enum PendingTaskWrite {
        case completion(CompletedTaskSnapshot)
        case undo(CompletedTaskSnapshot)
    }

    enum ViewMode: String, CaseIterable, Identifiable {
        case myTasks = "My Tasks", board = "Team Board", calendar = "Calendar"
        var id: String { rawValue }
    }

    var myTasks: [TaskItem] {
        guard let uid = authManager.currentUser?.id else { return [] }
        let assignedTasks = allTasks.filter { task in
            task.assignedToID == uid && task.status != .done
        }
        return assignedTasks.sorted { firstTask, secondTask in
            let firstDeadline = firstTask.deadline ?? .distantFuture
            let secondDeadline = secondTask.deadline ?? .distantFuture
            return firstDeadline < secondDeadline
        }
    }

    var allTags: [String] {
        Array(Set(allTasks.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if viewMode == .board && !allTags.isEmpty {
                    TagFilterBar(tags: allTags, selected: $filterTag)
                }

                Divider().padding(.top, 8)

                switch viewMode {
                case .myTasks: MyTasksList(tasks: myTasks, onComplete: completeTask)
                case .board: KanbanBoard(tasks: filteredBoardTasks, onComplete: completeTask)
                case .calendar: TaskCalendarView(tasks: allTasks)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let completedTask {
                    HStack(spacing: FTCDesign.space12) {
                        Label("Task completed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                        Spacer(minLength: FTCDesign.space8)
                        Button("Undo") { undoCompletion() }
                            .fontWeight(.semibold)
                            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                    }
                    .padding(.horizontal, FTCDesign.space16)
                    .background(.regularMaterial)
                    .transition(.opacity)
                    .accessibilityLiveRegion(.polite)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewTask = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isPresentingNewTask) { NewTaskSheet(users: users) }
            .alert("Couldn't update this task", isPresented: Binding(
                get: { taskSaveError != nil },
                set: { if !$0 { taskSaveError = nil } }
            )) {
                Button("Retry", action: retryPendingTaskWrite)
                Button("Keep current status", role: .cancel) {
                    pendingTaskWrite = nil
                    taskSaveError = nil
                }
            } message: {
                Text(taskSaveError ?? "Please try again.")
            }
            .task(id: completedTask?.id) {
                guard let taskID = completedTask?.id else { return }
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
                if completedTask?.id == taskID {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
                        completedTask = nil
                    }
                }
            }
            .sensoryFeedback(.success, trigger: taskCompletionFeedbackCount)
        }
    }

    private func completeTask(_ task: TaskItem) {
        guard task.status != .done else { return }
        let snapshot = CompletedTaskSnapshot(
            id: UUID(),
            task: task,
            originalStatus: task.status,
            originalLastModified: task.lastModified,
            completedLastModified: .now
        )
        persistCompletion(snapshot)
    }

    private func persistCompletion(_ snapshot: CompletedTaskSnapshot) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
            snapshot.task.status = .done
            snapshot.task.lastModified = snapshot.completedLastModified
        }
        do {
            try context.save()
        } catch {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
                snapshot.task.status = snapshot.originalStatus
                snapshot.task.lastModified = snapshot.originalLastModified
            }
            pendingTaskWrite = .completion(snapshot)
            taskSaveError = error.localizedDescription
            return
        }
        syncService?.pushTask(snapshot.task)
        NotificationScheduler.cancelReminder(for: snapshot.task)
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
            completedTask = snapshot
        }
        taskCompletionFeedbackCount += 1
    }

    private func undoCompletion() {
        guard let completedTask else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
            completedTask.task.status = completedTask.originalStatus
            completedTask.task.lastModified = completedTask.originalLastModified
        }
        do {
            try context.save()
        } catch {
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
                completedTask.task.status = .done
                completedTask.task.lastModified = completedTask.completedLastModified
            }
            pendingTaskWrite = .undo(completedTask)
            taskSaveError = error.localizedDescription
            return
        }
        syncService?.pushTask(completedTask.task)
        NotificationScheduler.scheduleDeadlineReminder(for: completedTask.task)
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.24)) {
            self.completedTask = nil
        }
    }

    private func retryPendingTaskWrite() {
        guard let pendingTaskWrite else { return }
        taskSaveError = nil
        self.pendingTaskWrite = nil
        switch pendingTaskWrite {
        case .completion(let snapshot):
            persistCompletion(snapshot)
        case .undo(let snapshot):
            completedTask = snapshot
            undoCompletion()
        }
    }

    private var filteredBoardTasks: [TaskItem] {
        guard let tag = filterTag else { return allTasks }
        return allTasks.filter { $0.tags.contains(tag) }
    }
}

// MARK: - My Tasks

private struct MyTasksList: View {
    let tasks: [TaskItem]
    let onComplete: (TaskItem) -> Void

    var body: some View {
        if tasks.isEmpty {
            EmptyStateView(icon: "checkmark.circle", title: "All caught up",
                           subtitle: "No open tasks assigned to you.", tint: .accentColor)
        } else {
            List {
                ForEach(tasks) { task in
                    TaskRow(task: task, onComplete: { onComplete(task) })
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct TaskRow: View {
    @Bindable var task: TaskItem
    let onComplete: () -> Void
    @Environment(\.syncService) private var syncService

    private var priorityColor: Color {
        switch task.priority {
        case .low, .medium: return .secondary
        case .high: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.body.weight(.medium))
                Label(task.priority.rawValue, systemImage: task.priority == .critical ? "exclamationmark.circle.fill" : "flag")
                    .font(.subheadline)
                    .foregroundStyle(priorityColor)
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    if !task.tags.isEmpty {
                        Text(task.tags.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    if let deadline = task.deadline {
                        if deadline < .now {
                            Label("Overdue · \(deadline.formatted(date: .abbreviated, time: .omitted))",
                                  systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        } else {
                            Text(deadline, style: .date)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: FTCDesign.minimumHitTarget)
        .swipeActions(edge: .trailing) {
            Button {
                onComplete()
            } label: { Label("Done", systemImage: "checkmark") }
            .tint(.green)
        }
        .contextMenu {
            Button {
                task.status = .inProgress
                task.lastModified = .now
                syncService?.pushTask(task)
            } label: {
                Label("Mark in progress", systemImage: "clock.arrow.circlepath")
            }
            Button(action: onComplete) {
                Label("Complete task", systemImage: "checkmark")
            }
            .disabled(task.status == .done)
        }
    }
}

// MARK: - Kanban board

private struct KanbanBoard: View {
    let tasks: [TaskItem]
    let onComplete: (TaskItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.allCases) { status in
                    KanbanColumn(status: status, tasks: tasks.filter { $0.status == status }, onComplete: onComplete)
                }
            }
            .padding()
        }
    }
}

private struct KanbanColumn: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let onComplete: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.rawValue).font(.subheadline.weight(.semibold))
                Text("\(tasks.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    KanbanCard(task: task, onComplete: onComplete)
                }
            }
        }
        .frame(width: 220)
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let uuid = UUID(uuidString: idString) else { return false }
            NotificationCenter.default.post(name: .taskDroppedOnColumn, object: nil,
                                             userInfo: ["id": uuid, "status": status])
            return true
        }
    }
}

private struct KanbanCard: View {
    @Bindable var task: TaskItem
    let onComplete: (TaskItem) -> Void
    @Environment(\.syncService) private var syncService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title).font(.body.weight(.medium)).lineLimit(2)
            HStack {
                Label(task.priority.rawValue, systemImage: task.priority == .critical ? "exclamationmark.circle.fill" : "flag")
                    .font(.subheadline)
                    .foregroundStyle(task.priority == .critical ? .red : task.priority == .high ? .orange : .secondary)
                Spacer()
                Text(task.assignedToName).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(FTCDesign.space12)
        .background(FTCDesign.secondarySurface,
                    in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous))
        .draggable(task.id.uuidString)
        .onReceive(NotificationCenter.default.publisher(for: .taskDroppedOnColumn)) { note in
            guard let id = note.userInfo?["id"] as? UUID, id == task.id,
                  let newStatus = note.userInfo?["status"] as? TaskStatus else { return }
            if newStatus == .done {
                onComplete(task)
                return
            }
            task.status = newStatus
            task.lastModified = .now
            syncService?.pushTask(task)
        }
        .contextMenu {
            Button {
                task.status = .inProgress
                task.lastModified = .now
                syncService?.pushTask(task)
            } label: {
                Label("Mark in progress", systemImage: "clock.arrow.circlepath")
            }
            Button {
                onComplete(task)
            } label: {
                Label("Complete task", systemImage: "checkmark")
            }
            .disabled(task.status == .done)
        }
    }
}

extension Notification.Name {
    static let taskDroppedOnColumn = Notification.Name("taskDroppedOnColumn")
}

// MARK: - Calendar (week-strip agenda)

private struct TaskCalendarView: View {
    let tasks: [TaskItem]
    @State private var weekStart: Date = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func tasksOn(_ date: Date) -> [TaskItem] {
        tasks.filter { task in
            guard let deadline = task.deadline else { return false }
            return Calendar.current.isDate(deadline, inSameDayAs: date)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { changeWeek(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(weekRangeLabel).font(.subheadline.weight(.medium))
                Spacer()
                Button { changeWeek(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    DayButton(date: day, isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                              hasTasks: !tasksOn(day).isEmpty) {
                        selectedDate = day
                    }
                }
            }
            .padding(.horizontal)

            Divider()

            let dayTasks = tasksOn(selectedDate)
            if dayTasks.isEmpty {
                EmptyStateView(icon: "calendar", title: "Nothing due",
                               subtitle: "No task deadlines on this day.", tint: .accentColor)
            } else {
                List {
                    ForEach(dayTasks) { task in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.body.weight(.medium))
                            Text("\(task.assignedToName) · \(task.priority.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func changeWeek(by delta: Int) {
        if let newStart = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: weekStart) {
            weekStart = newStart
        }
    }

    private var weekRangeLabel: String {
        guard let last = weekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: last))"
    }
}

private struct DayButton: View {
    let date: Date
    let isSelected: Bool
    let hasTasks: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.day())).font(.subheadline.weight(.semibold))
                if hasTasks {
                    Image(systemName: "checklist")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Color.clear.frame(width: FTCDesign.space12, height: FTCDesign.space12)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: FTCDesign.minimumHitTarget)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted) + (hasTasks ? ", tasks due" : ""))
    }
}

// MARK: - Tag filter bar

private struct TagFilterBar: View {
    let tags: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        selected = (selected == tag) ? nil : tag
                    } label: {
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(
                                selected == tag ? Color.accentColor.opacity(0.12) : Color(uiColor: .tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: FTCDesign.controlRadius, style: .continuous)
                            )
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - New Task sheet

private struct NewTaskSheet: View {
    let users: [AppUser]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var pendingTask: TaskItem?
    @State private var pendingActivity: ActivityEvent?
    @State private var pendingSaveAction: PendingSaveAction?
    @State private var saveError: String?
    @State private var didSave = false
    @State private var isConfirmingDiscard = false

    private enum PendingSaveAction: Equatable {
        case save
        case discard
    }

    @State private var title = ""
    @State private var description = ""
    @State private var assigneeID: UUID?
    @State private var priority: TaskPriority = .medium
    @State private var deadline: Date = .now.addingTimeInterval(86400)
    @State private var hasDeadline = false
    @State private var tagsInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                }
                Section("Assignment") {
                    Picker("Assignee", selection: $assigneeID) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(users) { user in Text(user.name).tag(Optional(user.id)) }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Set deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                        Text("You'll get a reminder notification at 9 AM on this day.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Tags (comma-separated)") {
                    TextField("Chassis, Odometry, Outreach, Meeting, Portfolio", text: $tagsInput)
                }
            }
            .navigationTitle("New Task")
            .alert("Couldn't save task", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("Retry", action: retryPendingSave)
                Button("Continue editing", role: .cancel) {
                    if pendingSaveAction == .discard,
                       let pendingTask, let pendingActivity {
                        context.insert(pendingTask)
                        context.insert(pendingActivity)
                    }
                    pendingSaveAction = nil
                    saveError = nil
                }
            } message: {
                Text(saveError ?? "Please try again.")
            }
            .confirmationDialog("Discard this task?", isPresented: $isConfirmingDiscard) {
                Button("Discard task", role: .destructive, action: discardPendingTask)
                Button("Continue editing", role: .cancel) {}
            }
            .interactiveDismissDisabled(pendingTask != nil)
            .sensoryFeedback(.success, trigger: didSave)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if pendingTask == nil {
                            dismiss()
                        } else {
                            isConfirmingDiscard = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let currentUser = authManager.currentUser else {
            saveError = "Sign in to create a team task."
            return
        }
        if pendingTask != nil {
            if let task = pendingTask {
                task.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                task.taskDescription = description
                task.assignedToID = assigneeID
                task.assignedToName = users.first(where: { $0.id == assigneeID })?.name ?? "Unassigned"
                task.priority = priority
                task.deadline = hasDeadline ? deadline : nil
                task.tags = tagsInput.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                task.lastModified = .now
                pendingActivity?.message = "created task: \(task.title)"
            }
            persistPendingTask()
            return
        }
        let tags = tagsInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let assigneeName = users.first(where: { $0.id == assigneeID })?.name ?? "Unassigned"

        let task = TaskItem(title: title, taskDescription: description, assignedToID: assigneeID,
                             assignedToName: assigneeName, priority: priority,
                             deadline: hasDeadline ? deadline : nil, tags: tags,
                             authorID: currentUser.id, authorName: currentUser.name)
        context.insert(task)
        let event = ActivityEvent(authorID: currentUser.id, authorName: currentUser.name, kind: .taskCreated,
                                   message: "created task: \(title)")
        context.insert(event)
        pendingTask = task
        pendingActivity = event
        persistPendingTask()
    }

    private func persistPendingTask() {
        guard let task = pendingTask, let event = pendingActivity else { return }
        do {
            try context.save()
        } catch {
            pendingSaveAction = .save
            saveError = error.localizedDescription
            return
        }
        syncService?.pushTask(task)
        syncService?.pushActivity(event)
        if hasDeadline {
            NotificationScheduler.scheduleDeadlineReminder(for: task)
        }
        pendingTask = nil
        pendingActivity = nil
        pendingSaveAction = nil
        didSave = true
        dismiss()
    }

    private func retryPendingSave() {
        guard let pendingSaveAction else { return }
        saveError = nil
        self.pendingSaveAction = nil
        switch pendingSaveAction {
        case .save:
            persistPendingTask()
        case .discard:
            discardPendingTask()
        }
    }

    private func discardPendingTask() {
        guard let pendingTask, let pendingActivity else {
            dismiss()
            return
        }
        context.delete(pendingTask)
        context.delete(pendingActivity)
        do {
            try context.save()
        } catch {
            pendingSaveAction = .discard
            saveError = error.localizedDescription
            return
        }
        self.pendingTask = nil
        self.pendingActivity = nil
        pendingSaveAction = nil
        dismiss()
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return TasksTabView()
        .modelContainer(container)
        .environment(authManager)
}
