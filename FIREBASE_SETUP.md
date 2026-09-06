# Firebase Setup — Cross-Device Sync

This gets your team's Tasks and Activity Feed syncing live across every
phone the app is sideloaded onto, using Firebase Firestore's free tier.
Everything below is done in a browser — no Mac needed for this part.

## 1. Create a Firebase project

1. Go to [console.firebase.google.com](https://console.firebase.google.com) and sign in with any Google account.
2. Click **Add project**, name it something like `ftcteamhub-24211`, and finish the wizard (Google Analytics is optional — you can skip it).

## 2. Register your iOS app

1. In the project, click the iOS icon ("Add app").
2. For **iOS bundle ID**, enter exactly: `com.ftcteamhub.app` — this must match the `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
3. Skip the App Store ID field.
4. Click **Register app**.

## 3. Download the config file

1. Firebase will offer to download `GoogleService-Info.plist`. Download it.
2. Upload it to your GitHub repo at exactly: `FTCTeamHub/GoogleService-Info.plist` (same folder as your other source files).

## 4. Enable Firestore

1. In the Firebase console left sidebar, click **Build → Firestore Database**.
2. Click **Create database**.
3. Choose **Start in test mode** for now (this allows open read/write with no auth check — fine for an internal team tool during development; see the security note below before relying on it long-term).
4. Pick any region close to you and click **Enable**.

## 5. Confirm your repo has everything

Your repo should now include:
- `project.yml` (updated — already declares the Firebase Swift Package dependency)
- `FTCTeamHub/GoogleService-Info.plist` (the file you just downloaded)
- `FTCTeamHub/Services/FirebaseSyncService.swift`
- Updated `FTCTeamHub/App/FTCTeamHubApp.swift`

## 6. Re-run the build

Go to **Actions → Build Unsigned IPA → Run workflow**. The first build after adding a Swift Package dependency takes noticeably longer (5–10 min instead of 2–3) since GitHub Actions has to resolve and compile the entire Firebase SDK — this is normal, not a stall.

## Security note (read before your event)

"Test mode" Firestore rules allow **anyone with your project's API key** to read/write your database — fine while only your team's devices have the app, but not something to leave on indefinitely. Once things are working, go to **Firestore → Rules** and tighten this, e.g.:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true; // ⚠️ replace before wide distribution
    }
  }
}
```

For a small internal team tool that's never publicly distributed, test-mode rules are a reasonable tradeoff — just don't publish your `GoogleService-Info.plist` in a public GitHub repo (keep the repo **Private**, which you already set up earlier).

## Wiring sync into the rest of the app

`FirebaseSyncService` currently syncs **Tasks** and **Activity Feed** automatically once `start(modelContext:)` runs (already wired in `FTCTeamHubApp.swift`). To make new tasks push to Firestore immediately when created, add one line to `TasksTabView.swift`'s `NewTaskSheet.save()` function, right after `context.insert(task)`:

```swift
context.insert(task)
context.insert(ActivityEvent(...)) // existing line
// ADD THIS LINE:
syncService?.pushTask(task)
```

You'll also need to add `@Environment(\.syncService) private var syncService` near the top of `NewTaskSheet`, alongside its other `@Environment` properties. Do the same in the Kanban drag-and-drop handler and the swipe-to-done action in `TaskRow`/`KanbanCard` (call `syncService?.pushTask(task)` right after `task.status = ...`), so status changes sync too.

For `ActivityEvent`, every `context.insert(ActivityEvent(...))` across `TasksTabView.swift`, `TestingTabView.swift`, `NotebookTabView.swift`, and `IdeasTabView.swift` should get a matching `syncService?.pushActivity(event)` call right after it — same pattern, just store the event in a local `let event = ActivityEvent(...)` first so you have a reference to pass.
