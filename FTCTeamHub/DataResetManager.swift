//
//  DataResetManager.swift
//  FTCTeamHub
//
//  Clears this device's SwiftData, local app preferences, session token,
//  and notifications. Shared Firestore records are intentionally untouched.
//

import Foundation
import SwiftData
import SwiftUI

enum DataResetManager {

    /// Deletes all locally stored team records. The Firestore copy is not
    /// changed; keep sync disabled until the team is ready to restore it.
    @MainActor
    static func wipeAllLocalData(context: ModelContext, includeRoster: Bool) throws {
        try deleteAll(TaskItem.self, in: context)
        try deleteAll(NotebookEntry.self, in: context)
        try deleteAll(TestRunRecord.self, in: context)
        try deleteAll(Idea.self, in: context)
        try deleteAll(ActivityEvent.self, in: context)
        try deleteAll(Battery.self, in: context)
        try deleteAll(ChecklistRun.self, in: context)
        try deleteAll(InventoryItem.self, in: context)
        try deleteAll(ScoutingReport.self, in: context)
        try deleteAll(TrackedTeam.self, in: context)
        try deleteAll(TeamSettings.self, in: context)
        try deleteAll(Sponsor.self, in: context)
        try deleteAll(BudgetExpense.self, in: context)
        try deleteAll(ScoringElement.self, in: context)

        if includeRoster {
            try deleteAll(AppUser.self, in: context)
        }

        try context.save()
        UserDefaults.standard.set(AvatarColor.red.rawValue, forKey: "accentColorRaw")
        UserDefaults.standard.set(false, forKey: "cloudSyncEnabled")
        NotificationScheduler.cancelAllReminders()
        if includeRoster {
            KeychainService.delete("com.ftcteamhub.session.userID")
        }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<T>()
        let items = try context.fetch(descriptor)
        for item in items {
            context.delete(item)
        }
    }
}
