//
//  NotebookTabView.swift
//  FTCTeamHub
//
//  TAB 3 — Engineering Notebook. Markdown-editable entries with FTC-specific
//  structured templates (autonomous test logs, Control Hub config, BHI260AP
//  IMU tuning) and image attachments.
//
//  FIX LOG (from CI build failures):
//  1. Removed `extension NotebookTemplate: Identifiable {}` — the enum
//     already declares Identifiable conformance in Models.swift, so this
//     was a redundant/duplicate conformance error.
//  2. Split every comma-joined `@State private var a = "", b = ""` line
//     into one `@State` declaration per line — a property wrapper can only
//     attach to a single variable, not a comma list. The old grouped form
//     silently broke Swift's memberwise-init synthesis for the sheet too,
//     which is what caused the separate "initializer is inaccessible"
//     error.
//  3. Replaced `"\(value, specifier: "%.2f")"` string interpolation (which
//     only works inside SwiftUI's `Text(_:)`, not in a plain String passed
//     to `LabeledContent`) with `String(format:)`.
//

import SwiftUI
import SwiftData
import PhotosUI

struct NotebookTabView: View {
    @Query(sort: \NotebookEntry.timestamp, order: .reverse) private var entries: [NotebookEntry]
    @State private var isPresentingTemplatePicker = false
    @State private var selectedTemplate: NotebookTemplate?

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { entry in
                    NavigationLink(value: entry) {
                        NotebookRow(entry: entry)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notebook")
            .navigationDestination(for: NotebookEntry.self) { entry in
                NotebookEntryDetailView(entry: entry)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingTemplatePicker = true } label: { Image(systemName: "square.and.pencil") }
                }
            }
            .confirmationDialog("New Entry", isPresented: $isPresentingTemplatePicker, titleVisibility: .visible) {
                ForEach(NotebookTemplate.allCases) { template in
                    Button(template.rawValue) { selectedTemplate = template }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                NewNotebookEntrySheet(template: template)
            }
        }
    }
}

private struct NotebookRow: View {
    let entry: NotebookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title).font(.body.weight(.medium))
            Text(entry.content)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(entry.authorName).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Text(entry.timestamp, style: .date).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// NOTE: no `extension NotebookTemplate: Identifiable {}` here — the enum
// in Models.swift already declares `Identifiable` conformance directly.

// MARK: - Detail (rendered Markdown + structured payloads)

private struct NotebookEntryDetailView: View {
    let entry: NotebookEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.title).font(.title2.bold())
                Text("By \(entry.authorName) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                Text(.init(entry.content)) // Renders Markdown via AttributedString

                if let auto = entry.autonomousLog { AutonomousLogCard(log: auto) }
                if let hub = entry.hubConfigLog { HubConfigCard(log: hub) }
                if let imu = entry.imuLog { IMULogCard(log: imu) }

                if !entry.tags.isEmpty {
                    HStack {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag).font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AutonomousLogCard: View {
    let log: AutonomousTestLog
    var body: some View {
        GroupBox("Autonomous Test — \(log.routineName)") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Starting position", value: log.startingPosition)
                LabeledContent("Scored", value: "\(log.samplesOrSpecimensScored)")
                LabeledContent("Cycle time", value: String(format: "%.2fs", log.cycleTimeSeconds))
                LabeledContent("Success rate", value: String(format: "%.0f%%", log.successRatePercent))
                if !log.failureNotes.isEmpty {
                    Text(log.failureNotes).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HubConfigCard: View {
    let log: ControlHubConfigLog
    var body: some View {
        GroupBox("Control Hub Configuration") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Control Hub OS", value: log.controlHubOSVersion)
                LabeledContent("SDK version", value: log.sdkVersion)
                LabeledContent("Expansion Hubs", value: "\(log.expansionHubCount)")
                ForEach(log.motorPortMap.sorted(by: { $0.key < $1.key }), id: \.key) { port, name in
                    LabeledContent("Motor \(port)", value: name)
                }
            }
        }
    }
}

private struct IMULogCard: View {
    let log: IMUTuningLog
    var body: some View {
        GroupBox("IMU Tuning — \(log.chip)") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Logo facing", value: log.logoFacingDirection)
                LabeledContent("USB facing", value: log.usbFacingDirection)
                LabeledContent("Yaw offset", value: String(format: "%.2f°", log.yawOffsetDegrees))
                LabeledContent("10-min drift", value: String(format: "%.2f°", log.driftOverTenMinDegrees))
                if !log.calibrationNotes.isEmpty {
                    Text(log.calibrationNotes).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - New entry sheet, template-aware

private struct NewNotebookEntrySheet: View {
    let template: NotebookTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var backend: MockBackendService

    @State private var title = ""
    @State private var content = ""
    @State private var tagsInput = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []

    // Template-specific structured fields — each @State on its own line.
    // (A property wrapper can only ever apply to ONE variable per line;
    // comma-separated grouping like `@State var a = "", b = ""` is invalid
    // Swift and was the root cause of the earlier CI build failure.)
    @State private var routineName = ""
    @State private var startingPosition = ""
    @State private var samplesScored = 0
    @State private var cycleTime = 0.0
    @State private var successRate = 0.0
    @State private var failureNotes = ""

    @State private var hubOS = "1.1.3"
    @State private var sdkVersion = "10.1"
    @State private var expansionHubs = 0

    @State private var imuChip = "BHI260AP"
    @State private var logoFacing = "UP"
    @State private var usbFacing = "FORWARD"
    @State private var yawOffset = 0.0
    @State private var drift = 0.0
    @State private var calibrationNotes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    TextField("Title", text: $title)
                    TextEditor(text: $content).frame(minHeight: 120)
                    TextField("Tags (comma-separated)", text: $tagsInput)
                }

                templateSpecificSection

                Section("Attachments") {
                    PhotosPicker("Attach CAD / wiring / whiteboard photos", selection: $selectedPhotos, matching: .images)
                    if !selectedPhotos.isEmpty {
                        Text("\(selectedPhotos.count) photo(s) selected").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(template.rawValue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var templateSpecificSection: some View {
        switch template {
        case .autonomousTest:
            Section("Autonomous Routine") {
                TextField("Routine name", text: $routineName)
                TextField("Starting position", text: $startingPosition)
                Stepper("Scored: \(samplesScored)", value: $samplesScored, in: 0...20)
                HStack { Text("Cycle time (s)"); Spacer(); TextField("0.0", value: $cycleTime, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Success rate (%)"); Spacer(); TextField("0", value: $successRate, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                TextField("Failure notes", text: $failureNotes, axis: .vertical)
            }
        case .controlHubConfig:
            Section("Control Hub Config") {
                TextField("Control Hub OS version", text: $hubOS)
                TextField("SDK version", text: $sdkVersion)
                Stepper("Expansion Hubs: \(expansionHubs)", value: $expansionHubs, in: 0...4)
            }
        case .imuTuning:
            Section("IMU Tuning") {
                Picker("Chip", selection: $imuChip) {
                    Text("BHI260AP").tag("BHI260AP")
                    Text("BNO055").tag("BNO055")
                }
                TextField("Logo facing direction", text: $logoFacing)
                TextField("USB facing direction", text: $usbFacing)
                HStack { Text("Yaw offset (°)"); Spacer(); TextField("0.0", value: $yawOffset, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("10-min drift (°)"); Spacer(); TextField("0.0", value: $drift, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                TextField("Calibration notes", text: $calibrationNotes, axis: .vertical)
            }
        case .softwareLog, .hardwareLog, .blank:
            EmptyView()
        }
    }

    private func save() {
        guard let user = backend.currentUser else { return }
        let tags = tagsInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let entry = NotebookEntry(authorID: user.id, authorName: user.name, title: title, content: content, tags: tags)

        switch template {
        case .autonomousTest:
            entry.autonomousLog = AutonomousTestLog(routineName: routineName, startingPosition: startingPosition,
                                                     samplesOrSpecimensScored: samplesScored, cycleTimeSeconds: cycleTime,
                                                     successRatePercent: successRate, failureNotes: failureNotes)
        case .controlHubConfig:
            entry.hubConfigLog = ControlHubConfigLog(controlHubOSVersion: hubOS, sdkVersion: sdkVersion,
                                                      expansionHubCount: expansionHubs, motorPortMap: [:], servoPortMap: [:])
        case .imuTuning:
            entry.imuLog = IMUTuningLog(chip: imuChip, logoFacingDirection: logoFacing, usbFacingDirection: usbFacing,
                                         yawOffsetDegrees: yawOffset, driftOverTenMinDegrees: drift,
                                         calibrationNotes: calibrationNotes)
        case .softwareLog, .hardwareLog, .blank:
            break
        }

        context.insert(entry)
        context.insert(ActivityEvent(authorID: user.id, authorName: user.name, kind: .notebookEntry,
                                      message: "added notebook entry: \(title)"))
        dismiss()
    }
}
