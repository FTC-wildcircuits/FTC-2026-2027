//
//  FTCTeamHubApp.swift
//  FTCTeamHub
//
//  App entry point: SwiftData schema, Firebase configuration, and the
//  root environment.
//

import SwiftUI
import SwiftData
import FirebaseCore
import OSLog

@main
struct FTCTeamHubApp: App {

    let container: ModelContainer
    private let persistenceWarning: String?

    private static let logger = Logger(subsystem: "com.ftcteamhub.app", category: "Persistence")

    private static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            AppUser.self, TaskItem.self, NotebookEntry.self,
            TestRunRecord.self, Idea.self, ActivityEvent.self, TrackedTeam.self,
            Battery.self, ChecklistRun.self, InventoryItem.self,
            TeamSettings.self, Sponsor.self, BudgetExpense.self,
            ScoringElement.self, ScoutingReport.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private let scoutAPI: FTCScoutAPIServicing = LiveFTCScoutAPIClient()
    private let syncService = FirebaseSyncService()
    private let chatService = ChatService()

    @AppStorage("accentColorRaw") private var accentColorRaw: String = AvatarColor.red.rawValue

    init() {
        FirebaseApp.configure()
        do {
            container = try Self.makeModelContainer()
            persistenceWarning = nil
        } catch {
            Self.logger.error("Persistent team storage could not be opened; using temporary in-memory storage.")
            do {
                container = try Self.makeModelContainer(inMemory: true)
                persistenceWarning = error.localizedDescription
            } catch {
                fatalError("Unable to create a SwiftData model container: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(persistenceWarning: persistenceWarning)
                .environment(\.ftcScoutAPI, scoutAPI)
                .environment(\.syncService, syncService)
                .environment(\.chatService, chatService)
                .tint((AvatarColor(rawValue: accentColorRaw) ?? .red).color)
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
    let persistenceWarning: String?

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
                    Text("Workspace setup could not finish")
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if let persistenceWarning {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Changes are temporary on this device")
                            .font(.subheadline.weight(.semibold))
                        Text("The existing database was left untouched. New changes are temporary. Check available storage or install a compatible app build before relying on local records. \(persistenceWarning)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .accessibilityElement(children: .combine)
            }
        }
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
            if persistenceWarning != nil {
                cloudSyncEnabled = false
            } else if !cleanSlateApplied {
                cloudSyncEnabled = false
                try DataResetManager.wipeAllLocalData(context: modelContext, includeRoster: true)
                cleanSlateApplied = true
            }
            if cloudSyncEnabled {
                syncService?.start(modelContext: modelContext)
                try syncService?.syncLocalRecords(in: modelContext)
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
                .tabItem { Label(RootTab.dashboard.title, systemImage: RootTab.dashboard.systemImage) }

            WorkHubTabView()
                .tag(RootTab.work)
                .tabItem { Label(RootTab.work.title, systemImage: RootTab.work.systemImage) }

            PitOpsTabView()
                .tag(RootTab.pitOps)
                .tabItem { Label(RootTab.pitOps.title, systemImage: RootTab.pitOps.systemImage) }

            LiveDataTabView()
                .tag(RootTab.scouting)
                .tabItem { Label(RootTab.scouting.title, systemImage: RootTab.scouting.systemImage) }

            TeamHubTabView()
                .tag(RootTab.team)
                .tabItem { Label(RootTab.team.title, systemImage: RootTab.team.systemImage) }
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
