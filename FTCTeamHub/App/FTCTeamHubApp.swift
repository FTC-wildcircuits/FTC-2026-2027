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
            ScoringElement.self, ScoutingReport.self
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
                    NotificationScheduler.requestAuthorizationIfNeeded()
                }
        }
        .modelContainer(container)
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
    @State private var launchError: String?
    @AppStorage("com.ftcteamhub.clean-slate.2026-27") private var cleanSlateApplied = false
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false

    var body: some View {
        Group {
            if let launchError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(FTCBrand.orange)
                    Text("Clean start could not finish")
                        .font(.title2.bold())
                    Text(launchError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        self.launchError = nil
                        prepareWorkspace()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(28)
            } else if let authManager {
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
                FTCLoadingView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authManager?.currentUser?.id)
        .onAppear(perform: prepareWorkspace)
        .onChange(of: cloudSyncEnabled) { _, enabled in
            if enabled {
                syncService?.start(modelContext: modelContext)
                authManager?.setSyncService(syncService)
            } else {
                syncService?.stop()
                authManager?.setSyncService(nil)
            }
        }
    }

    private func prepareWorkspace() {
        guard authManager == nil else { return }
        do {
            if !cleanSlateApplied {
                cloudSyncEnabled = false
                try DataResetManager.wipeAllLocalData(context: modelContext, includeRoster: true)
                cleanSlateApplied = true
            }
            if cloudSyncEnabled {
                syncService?.start(modelContext: modelContext)
            }
            authManager = AuthenticationManager(
                modelContext: modelContext,
                syncService: cloudSyncEnabled ? syncService : nil
            )
        } catch {
            launchError = error.localizedDescription
        }
    }
}

// MARK: - Main TabView

struct MainTabView: View {
    @State private var router = TabRouter()

    var body: some View {
        TabView(selection: Binding(get: { router.rootSelection }, set: { router.selectRoot($0) })) {
            DashboardTabView()
                .tag(RootTab.dashboard)
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            WorkHubTabView()
                .tag(RootTab.work)
                .tabItem { Label("Build", systemImage: "hammer.fill") }

            PitOpsTabView()
                .tag(RootTab.pitOps)
                .tabItem { Label("Pit Ops", systemImage: "wrench.and.screwdriver.fill") }

            LiveDataTabView()
                .tag(RootTab.scouting)
                .tabItem { Label("Scout", systemImage: "antenna.radiowaves.left.and.right") }

            TeamHubTabView()
                .tag(RootTab.team)
                .tabItem { Label("Team", systemImage: "gearshape.fill") }
        }
        .environment(router)
        .preferredColorScheme(.dark)
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
