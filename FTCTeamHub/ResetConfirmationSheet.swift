//
//  ResetConfirmationSheet.swift
//  FTCTeamHub
//
//  Explicitly confirmed local-data reset flow.
//

import SwiftUI
import SwiftData

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
    private let expectedPhrase = "reset"

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
                    Button("Cancel") { dismiss() }
                        .frame(maxWidth: .infinity)
                }

                Section {
                    Toggle("Delete team accounts and sign everyone out", isOn: $includeRoster)
                } footer: {
                    Text("Turn this off only if you want to keep the current account on this device.")
                }

                Section("Type reset to confirm") {
                    TextField("reset", text: $confirmationText)
                        .textInputAutocapitalization(.never)
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
                            Text("Reset local data").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(confirmationText != expectedPhrase || isWiping)
                }
            }
            .navigationTitle("Reset App Data")
        }
        .interactiveDismissDisabled(isWiping)
        .sensoryFeedback(.success, trigger: resultMessage)
        .sensoryFeedback(.error, trigger: resetError)
    }

    private func performWipe() {
        isWiping = true
        do {
            cloudSyncEnabled = false
            syncService?.stop()
            try DataResetManager.wipeAllLocalData(context: context, includeRoster: includeRoster)
            resultMessage = "Done. Local data is cleared; shared Firestore data was not changed."
            if includeRoster {
                authManager.signOut()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
        } catch {
            resetError = "Reset failed: \(error.localizedDescription)"
            isWiping = false
        }
    }
}

#Preview("Reset confirmation · Light") {
    let container = makePreviewContainer()
    ResetConfirmationSheet()
        .modelContainer(container)
        .environment(AuthenticationManager(modelContext: container.mainContext))
        .preferredColorScheme(.light)
}

#Preview("Reset confirmation · Dark") {
    let container = makePreviewContainer()
    ResetConfirmationSheet()
        .modelContainer(container)
        .environment(AuthenticationManager(modelContext: container.mainContext))
        .preferredColorScheme(.dark)
}

#Preview("Reset confirmation · Accessibility") {
    let container = makePreviewContainer()
    ResetConfirmationSheet()
        .modelContainer(container)
        .environment(AuthenticationManager(modelContext: container.mainContext))
        .dynamicTypeSize(.accessibility5)
}
