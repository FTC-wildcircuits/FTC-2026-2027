//
//  FTCTeamHubApp.swift
//  FTCTeamHub
//
//  App entry point. Wires the SwiftData ModelContainer and the backend
//  services into the environment so every child view gets dependency
//  injection for free via @Environment / @EnvironmentObject — no
//  singleton reach-through from Views.
//

import SwiftUI
import SwiftData

@main
struct FTCTeamHubApp: App {

    let container: ModelContainer = {
        let schema = Schema([
            AppUser.self, TaskItem.self, NotebookEntry.self,
            ScoutingRecord.self, PicklistEntry.self, Idea.self, ActivityEvent.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    @StateObject private var backend = MockBackendService.shared
    private let scoutAPI: FTCScoutAPIServicing = LiveFTCScoutAPIClient()

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .environmentObject(backend)
                .environment(\.ftcScoutAPI, scoutAPI)
        }
        .modelContainer(container)
    }
}

// MARK: - Environment key for the API client (protocol-typed, swappable in previews)

private struct FTCScoutAPIKey: EnvironmentKey {
    static let defaultValue: FTCScoutAPIServicing = LiveFTCScoutAPIClient()
}

extension EnvironmentValues {
    var ftcScoutAPI: FTCScoutAPIServicing {
        get { self[FTCScoutAPIKey.self] }
        set { self[FTCScoutAPIKey.self] = newValue }
    }
}

// MARK: - Root: gates the whole app behind sign-in, then shows the TabView

struct RootContainerView: View {
    @EnvironmentObject private var backend: MockBackendService

    var body: some View {
        Group {
            if backend.currentUser != nil {
                MainTabView()
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: backend.currentUser != nil)
    }
}

// MARK: - Sign-in (stand-in for Firebase/Supabase/CloudKit auth UI)

struct SignInView: View {
    @EnvironmentObject private var backend: MockBackendService
    @State private var name = ""
    @State private var role: TeamRole = .software
    @State private var teamNumber = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Identity") {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                    Picker("Role", selection: $role) {
                        ForEach(TeamRole.allCases) { r in
                            Label(r.rawValue, systemImage: r.systemImage).tag(r)
                        }
                    }
                    TextField("Team number", text: $teamNumber)
                        .keyboardType(.numberPad)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Sign In")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        signIn()
                    } label: {
                        if isSigningIn { ProgressView() } else { Text("Continue") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || teamNumber.isEmpty || isSigningIn)
                }
            }
        }
    }

    private func signIn() {
        guard let teamNum = Int(teamNumber) else {
            errorMessage = "Team number must be numeric."
            return
        }
        isSigningIn = true
        Task {
            do {
                _ = try await backend.signIn(name: name, role: role, teamNumber: teamNum)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }
}

// MARK: - Main TabView (mandate #3: five core modules)

struct MainTabView: View {
    var body: some View {
        TabView {
            ScoutingTabView()
                .tabItem { Label("Scouting", systemImage: "chart.bar.xaxis") }

            TasksTabView()
                .tabItem { Label("Tasks", systemImage: "checklist") }

            NotebookTabView()
                .tabItem { Label("Notebook", systemImage: "book.closed") }

            IdeasTabView()
                .tabItem { Label("Ideas", systemImage: "lightbulb") }

            ActivityTabView()
                .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }
        }
        // Native tint — no custom brand color forced over system accent,
        // per the "no forced dark/light / native aesthetic" mandate.
    }
}

#Preview {
    RootContainerView()
        .environmentObject(MockBackendService.shared)
}
