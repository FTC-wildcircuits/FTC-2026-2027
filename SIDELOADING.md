# Build and sideload FTC Team Hub

GitHub Actions can build the iOS app on a macOS runner and publish a
downloadable, **unsigned** IPA plus a ZIP of the exact source used for that
build. This repository contains the XcodeGen project specification, app code,
assets, launch screen, Firebase configuration, and the build workflow.

## Run a build on GitHub

1. Push the intended source branch to GitHub.
2. Open **Actions → Build unsigned iOS IPA → Run workflow**. Choose the
   branch, then start the workflow. Pull requests to `main` and pushes to
   `main` also start builds automatically.
3. Open a successful workflow run and download
   `FTCTeamHub-release-<run number>`. Unzip it to get:
   - `FTCTeamHub-unsigned.ipa`
   - `FTC-2026-2027-main.zip` (source matching the built commit)
   - `BUILD-INFO.txt`
   - `SHA256SUMS.txt`

GitHub workflow artifacts expire after 30 days. For longer-term downloads,
push a version tag such as `v1.2.0`. The workflow creates a **draft GitHub
release** with the IPA, source ZIP, build info, and checksums; review and
publish the draft when ready.

Before upload, the workflow checks Firebase configuration without printing
its values, generates the Xcode project, resolves Firebase packages, builds
for a physical iOS device, verifies the app bundle and bundle ID, tests both
archives, and generates SHA-256 checksums. A failing check prevents a
successful artifact upload. Package dependencies are cached to reduce repeat
build time.

## Install on an iPhone or iPad

An unsigned IPA cannot be installed just by downloading it from GitHub. It
must first be signed with an Apple development certificate and provisioning
profile. For personal sideloading, choose a trusted tool and follow its
current official instructions:

- **AltStore Classic:** install AltServer on a Mac or Windows PC; import the
  IPA from AltStore's **My Apps → +** screen.
- **SideStore:** complete SideStore's official device setup, then import the
  IPA in SideStore.
- **Sideloadly:** install it from its official source, connect the device,
  select the IPA, and follow its signing prompts.

The tool signs the IPA with your Apple ID before installing it. Free personal
Apple accounts commonly require refreshing the installation about every
seven days. This workflow does not request or store Apple signing credentials.
App Store distribution requires a paid Apple Developer account, managed
signing assets, and a separately configured signed-release workflow.

## Firebase and team data

The build stops if `FTCTeamHub/GoogleService-Info.plist` is absent or does not
match bundle ID `com.ftcteamhub.app`. **This GitHub repository is public**, so
the existing plist and Firebase API key are public client configuration. Do
not put passwords, service-account JSON, or private keys in the repository or
IPA. Restrict the API key to the needed services where practical; this is not
a replacement for Firestore access control.

The app's email/password login is local, not Firebase Authentication. Open
Firestore test rules can expose data to anyone, while rules requiring Firebase
sign-in reject the app's current Firestore requests. Do not use open rules
with real team information or distribute a build connected to an unprotected
database. Use an authenticated backend and restrictive rules before sharing
team data.

## Included features

The app includes five primary navigation areas and hubs for dashboard, roster,
task board, robot testing, engineering notebook/PDF export, ideas, batteries,
checklists, searchable and editable inventory with QR check-in/out, match
scouting with event filters/team averages/CSV export, FTCScout team and event
data, scoring simulator, real-time chat, team settings, and budget/sponsor
tracking. The clean-slate build clears local team records once on first
launch, starts with cloud sync off, and includes an in-app 2026–27 calendar
for the five supplied events with a linked engineering notebook and
persistent robot/pit readiness checklist for each. The login screen has a
restrained Wild Circuits / Team 24211 identity, clear sign-in and account
creation, and accessible password visibility controls. Native adaptive text
colors keep member and event names legible in both iOS appearance modes, with
a restrained red team accent. The app uses a custom five-section navigation
dock, a team status dashboard, and a quick practice log form that records an
observation, follow-up test, work area, and author directly in the searchable
engineering notebook.
Enabling cloud sync is optional and may download existing shared records;
it also uploads local records from this device. The reset does not delete
Firestore data. FTCScout match scores are not fabricated: scores in scouting
reports are observations entered by the team.
