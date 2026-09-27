//
//  AuthenticationManager.swift
//  FTCTeamHub
//
//  Handles sign-in, sign-up, and session state, syncing new profiles to
//  Firestore so teammates appear in the Roster tab across every device.
//

import Foundation
import SwiftData
import CryptoKit
import Observation

@MainActor
@Observable
final class AuthenticationManager {

    private(set) var currentUser: AppUser?
    var errorMessage: String?

    private let modelContext: ModelContext
    private var syncService: FirebaseSyncService?
    private let sessionKey = "com.ftcteamhub.session.userID"

    init(modelContext: ModelContext, syncService: FirebaseSyncService? = nil) {
        self.modelContext = modelContext
        self.syncService = syncService
        restoreSession()
    }

    func restoreSession() {
        guard let idString = KeychainService.read(sessionKey),
              let uuid = UUID(uuidString: idString) else { return }

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.id == uuid })
        if let user = try? modelContext.fetch(descriptor).first {
            currentUser = user
        }
    }

    func setSyncService(_ service: FirebaseSyncService?) {
        syncService = service
    }

    func signUp(name: String, email: String, password: String, role: TeamRole, avatarColor: AvatarColor) {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        guard !trimmedName.isEmpty, !normalizedEmail.isEmpty, password.count >= 4 else {
            errorMessage = "Enter your name, email, and a password of at least 4 characters."
            return
        }

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.email == normalizedEmail })
        let existing: [AppUser]
        do {
            existing = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Couldn't check for an existing account: \(error.localizedDescription)"
            return
        }
        if !existing.isEmpty {
            errorMessage = "An account with that email already exists. Try signing in instead."
            return
        }

        let user = AppUser(email: normalizedEmail, name: trimmedName, role: role, avatarColor: avatarColor,
                            passwordHash: Self.hash(password), isLogged: true)
        modelContext.insert(user)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(user)
            errorMessage = "Couldn't save your account: \(error.localizedDescription)"
            return
        }

        // Push to Firestore so other devices see this team member and can
        // sign in as them once it syncs down.
        syncService?.pushUser(user)

        guard KeychainService.save(sessionKey, value: user.id.uuidString) else {
            user.isLogged = false
            do {
                try modelContext.save()
            } catch {
                errorMessage = "Account created, but this iPhone couldn't save the sign-in session: \(error.localizedDescription)"
                return
            }
            errorMessage = "Account created, but this iPhone couldn't save the sign-in session. Try signing in again."
            return
        }
        currentUser = user
    }

    func signIn(email: String, password: String) {
        errorMessage = nil
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.email == normalizedEmail })
        let user: AppUser?
        do {
            user = try modelContext.fetch(descriptor).first
        } catch {
            errorMessage = "Couldn't read team accounts: \(error.localizedDescription)"
            return
        }
        guard let user else {
            errorMessage = "No account found with that email on this device yet. If you signed up on another device, make sure both phones have been online recently so it can sync — then try again in a few seconds."
            return
        }

        guard user.passwordHash == Self.hash(password) else {
            errorMessage = "Incorrect password."
            return
        }

        user.isLogged = true
        do {
            try modelContext.save()
        } catch {
            user.isLogged = false
            errorMessage = "Couldn't save your sign-in: \(error.localizedDescription)"
            return
        }
        guard KeychainService.save(sessionKey, value: user.id.uuidString) else {
            user.isLogged = false
            do {
                try modelContext.save()
            } catch {
                errorMessage = "Couldn't save the sign-in session or restore the account state: \(error.localizedDescription)"
                return
            }
            errorMessage = "Couldn't save the sign-in session on this iPhone. Please try again."
            return
        }
        currentUser = user
    }

    func signOut() {
        currentUser?.isLogged = false
        try? modelContext.save()
        KeychainService.delete(sessionKey)
        currentUser = nil
    }

    private static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
