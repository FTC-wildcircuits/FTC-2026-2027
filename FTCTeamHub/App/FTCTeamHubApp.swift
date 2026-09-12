//
//  FTCTeamHubApp.swift
//  FTCTeamHub
//
//  NEW: schema includes ScoringElement (backing the Scoring Simulator).
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct FTCTeamHubApp: App {

    let container: ModelContainer = {
        let schema = Schema([
            AppUser.self, TaskItem.self, NotebookEntry.self,
            TestRunRecord.self, Idea.self, ActivityEvent.self, TrackedTeam.self,
            Battery.self, ChecklistRun.self, InventoryItem.self,
            TeamSettings.self, Sponsor.self, BudgetExpense.self,
            ScoringElement.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private let scoutAPI: FTCScoutAPIServicing = LiveFTCScoutAPIClient()
    private let syncService = FirebaseSyncService()
    private let chatService = ChatService()

    @AppStorage("accentColorRaw") private var accentColorRaw: String = AvatarColor.blue.rawValue

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.ftcScoutAPI, scoutAPI)
                .environment(\.syncService, syncService)
                .environment(\.chatService, chatService)
                .tint((AvatarColor(rawValue: accentColorRaw) ?? .blue).color)
                .onAppear {
                    syncService.start(modelContext: container.mainContext)
                    chatService.start()
                    NotificationScheduler.requestAuthorizationIfNeeded()
                    seedDefaultScoringElementsIfNeeded()
                }
        }
        .modelContainer(container)
    }

    /// Seeds a starter set of placeholder scoring elements (0 points each)
    /// so the Scoring Simulator isn't empty on first launch — the team
    /// edits the point values once the real Game Manual is released.
    private func seedDefaultScoringElementsIfNeeded() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ScoringElement>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }

        let defaults: [(String, ScoringPhase, Int)] = [
            ("Leave / Depart Start", .autonomous, 0),
            ("Score Game Element (Auto)", .autonomous, 0),
            ("Score Game Element (TeleOp)", .teleop, 0),
            ("Cycle Bonus", .teleop, 0),
            ("Park", .endgame, 0),
            ("Climb / Hang", .endgame, 0)
        ]
        for (index, entry) in defaults.enumerated() {
            context.insert(ScoringElement(name: entry.0, phase: entry.1, pointValue: entry.2, sortOrder: index))
        }
        try? context.save()
    }
}

// MARK: - Environment keys

private struct FTCScoutAPIKey: EnvironmentKey {
    static let defaultValue: FTCScoutAPIServicing = LiveFTCScoutAPIClient()
}

private struct SyncServiceKey: EnvironmentKey {
    static let defaultValue: FirebaseSyncService? = nil
}

private struct ChatServiceKey: EnvironmentKey {
    static let defaultValue: ChatService? = nil
}

extension EnvironmentValues {
    var ftcScoutAPI: FTCScoutAPIServicing {
        get { self[FTCScoutAPIKey.self] }
        set { self[FTCScoutAPIKey.self] = newValue }
    }
    var syncService: FirebaseSyncService? {
        get { self[SyncServiceKey.self] }
        set { self[SyncServiceKey.self] = newValue }
    }
    var chatService: ChatService? {
        get { self[ChatServiceKey.self] }
        set { self[ChatServiceKey.self] = newValue }
    }
}

// MARK: - Root router

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncService) private var syncService
    @State private var authManager: AuthenticationManager?

    var body: some View {
        Group {
            if let authManager {
                if authManager.currentUser != nil {
                    MainTabView()
                        .environment(authManager)
                        .transition(.opacity)
                } else {
                    LoginView()
                        .environment(authManager)
                        .transition(.opacity)
                }
            } else {
                ProgressView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authManager?.currentUser?.id)
        .onAppear {
            if authManager == nil {
                authManager = AuthenticationManager(modelContext: modelContext, syncService: syncService)
            }
        }
    }
}

// MARK: - Main TabView — ten modules, Dashboard first

struct MainTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        TabView(selection: Binding(get: { router.selection }, set: { router.selection = $0 })) {
            DashboardTabView()
                .tag(AppTab.dashboard)
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            RosterTabView()
                .tag(AppTab.roster)
                .tabItem { Label("Roster", systemImage: "person.3.fill") }

            TestingTabView()
                .tag(AppTab.testing)
                .tabItem { Label("Testing", systemImage: "gauge.with.dots.needle.67percent") }

            TasksTabView()
                .tag(AppTab.tasks)
                .tabItem { Label("Tasks", systemImage: "checklist") }

            NotebookTabView()
                .tag(AppTab.notebook)
                .tabItem { Label("Notebook", systemImage: "book.closed.fill") }

            IdeasTabView()
                .tag(AppTab.ideas)
                .tabItem { Label("Ideas", systemImage: "lightbulb.fill") }

            PitOpsTabView()
                .tag(AppTab.pitOps)
                .tabItem { Label("Pit Ops", systemImage: "wrench.and.screwdriver.fill") }

            ChatTabView()
                .tag(AppTab.chat)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right.fill") }

            LiveDataTabView()
                .tag(AppTab.liveData)
                .tabItem { Label("Live Data", systemImage: "antenna.radiowaves.left.and.right") }

            TeamTabView()
                .tag(AppTab.team)
                .tabItem { Label("Team", systemImage: "gearshape.fill") }
        }
        .environment(router)
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    MainTabView()
        .modelContainer(container)
        .environment(authManager)
        .environment(\.ftcScoutAPI, LiveFTCScoutAPIClient())
}
