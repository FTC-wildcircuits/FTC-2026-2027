//
//  FTCTeamHubApp.swift
//  FTCTeamHub
//
//  App entry point. `syncService` is `lazy` so it's only constructed the
//  first time it's actually touched (in `.onAppear`), which is guaranteed
//  to be after `FirebaseApp.configure()` has already run in `init()` —
//  this is a second layer of protection on top of the `lazy var db` fix
//  inside FirebaseSyncService.swift itself, so this exact class of crash
//  (Firestore touched before Firebase is configured) can't recur even if
//  this file is edited again later.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct FTCTeamHubApp: App {

    let container: ModelContainer = {
        let schema = Schema([
            AppUser.self, TaskItem.self, NotebookEntry.self,
            TestRunRecord.self, Idea.self, ActivityEvent.self, TrackedTeam.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private let scoutAPI: FTCScoutAPIServicing = LiveFTCScoutAPIClient()
    private lazy var syncService = FirebaseSyncService()

    init() {
        // Must run before anything touches Firestore/Firebase — see the
        // header comment above and in FirebaseSyncService.swift for why
        // this ordering previously caused a launch-time crash.
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.ftcScoutAPI, scoutAPI)
                .environment(\.syncService, syncService)
                .onAppear {
                    syncService.start(modelContext: container.mainContext)
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

extension EnvironmentValues {
    var ftcScoutAPI: FTCScoutAPIServicing {
        get { self[FTCScoutAPIKey.self] }
        set { self[FTCScoutAPIKey.self] = newValue }
    }
    var syncService: FirebaseSyncService? {
        get { self[SyncServiceKey.self] }
        set { self[SyncServiceKey.self] = newValue }
    }
}

// MARK: - Root router

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
                authManager = AuthenticationManager(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Main TabView — six modules

struct MainTabView: View {
    var body: some View {
        TabView {
            RosterTabView()
                .tabItem { Label("Roster", systemImage: "person.3.fill") }

            TestingTabView()
                .tabItem { Label("Testing", systemImage: "gauge.with.dots.needle.67percent") }

            TasksTabView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            NotebookTabView()
                .tabItem { Label("Notebook", systemImage: "book.closed.fill") }

            IdeasTabView()
                .tabItem { Label("Ideas", systemImage: "lightbulb.fill") }

            LiveDataTabView()
                .tabItem { Label("Live Data", systemImage: "antenna.radiowaves.left.and.right") }
        }
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
