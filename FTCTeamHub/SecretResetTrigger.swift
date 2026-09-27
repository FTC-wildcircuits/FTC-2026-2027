//
//  SecretResetTrigger.swift
//  FTCTeamHub
//
//  A hidden gesture that reveals the "Reset App Data" flow after seven
//  taps within three seconds. Wired to the version label in the About
//  screen (TeamTabView.swift).
//

import SwiftUI
import SwiftData
import UIKit

struct SecretResetTrigger<Content: View>: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthenticationManager.self) private var authManager

    @ViewBuilder let content: () -> Content

    @State private var tapCount = 0
    @State private var lastTapTime: Date = .distantPast
    @State private var isPresentingResetSheet = false

    private let requiredTaps = 7
    private let tapWindowSeconds: TimeInterval = 3

    var body: some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                registerTap()
            }
            .sheet(isPresented: $isPresentingResetSheet) {
                ResetConfirmationSheet()
            }
    }

    private func registerTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) > tapWindowSeconds {
            tapCount = 0
        }
        lastTapTime = now
        tapCount += 1

        if tapCount >= requiredTaps {
            tapCount = 0
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            isPresentingResetSheet = true
        } else if tapCount >= requiredTaps - 2 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

struct ResetConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @AppStorage("cloudSyncEnabled") private var cloudSyncEnabled = false

    @State private var confirmationText = ""
    @State private var includeRoster = true
    @State private var isWiping = false
    @State private var resultMessage: String?
    @State private var resetError: String?
    private let expectedPhrase = "RESET"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.headline)
                    Text("This permanently deletes all team records and accounts stored on this device. Shared Firestore records are not deleted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Delete team accounts and sign everyone out", isOn: $includeRoster)
                } footer: {
                    Text("Turn this off only if you want to keep the current account on this device.")
                }

                Section("Type RESET to confirm") {
                    TextField("RESET", text: $confirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage).font(.footnote).foregroundStyle(.green)
                    }
                }
                if let resetError {
                    Section {
                        Text(resetError).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        performWipe()
                    } label: {
                        if isWiping {
                            ProgressView()
                        } else {
                            Text("Wipe All Data").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(confirmationText != expectedPhrase || isWiping)
                }
            }
            .navigationTitle("Reset App Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(isWiping)
    }

    private func performWipe() {
        isWiping = true
        do {
            cloudSyncEnabled = false
            syncService?.stop()
            try DataResetManager.wipeAllLocalData(context: context, includeRoster: includeRoster)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            resultMessage = "Done. Local data is cleared; shared Firestore data was not changed."
            if includeRoster {
                authManager.signOut()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            resetError = "Reset failed: \(error.localizedDescription)"
            isWiping = false
        }
    }
}

#Preview {
    SecretResetTrigger {
        Text("FTC Team Hub v1.0")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}
