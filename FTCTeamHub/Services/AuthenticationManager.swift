//
//  AuthenticationManager.swift
//  FTCTeamHub
//
//  Robust, persistent authentication: real account creation, real sign-in
//  against stored credentials, and — critically — a session that survives
//  app relaunches via Keychain + SwiftData, fixing the "app kicks you out"
//  bug from the previous version.
//
//  Security note: password hashing here (SHA256, no per-user salt) is
//  appropriate for an internal small-team tool with no sensitive payment
//  or personal data — it is NOT bank-grade. If this app ever handles more
//  sensitive data, swap in a salted hash (e.g. PBKDF2/Argon2) here without
//  touching any View code, since every View talks only to this manager.
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
    private let sessionKey = "com.ftcteamhub.session.userID"

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        restoreSession()
    }

    /// Looks up a saved session id in the Keychain and, if a matching user
    /// still exists in SwiftData, signs them back in automatically. Called
    /// once at launch so users are never dropped back to the login screen
    /// just for reopening the app.
    func restoreSession() {
        guard let idString = KeychainService.read(sessionKey),
              let uuid = UUID(uuidString: idString) else { return }

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.id == uuid })
        if let user = try? modelContext.fetch(descriptor).first {
            currentUser = user
        }
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
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            errorMessage = "An account with that email already exists. Try signing in instead."
            return
        }

        let user = AppUser(email: normalizedEmail, name: trimmedName, role: role, avatarColor: avatarColor,
                            passwordHash: Self.hash(password), isLogged: true)
        modelContext.insert(user)
        try? modelContext.save()

        KeychainService.save(sessionKey, value: user.id.uuidString)
        currentUser = user
    }

    func signIn(email: String, password: String) {
        errorMessage = nil
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.email == normalizedEmail })
        guard let user = try? modelContext.fetch(descriptor).first else {
            errorMessage = "No account found with that email. Switch to Create Account to sign up."
            return
        }

        guard user.passwordHash == Self.hash(password) else {
            errorMessage = "Incorrect password."
            return
        }

        user.isLogged = true
        try? modelContext.save()
        KeychainService.save(sessionKey, value: user.id.uuidString)
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
