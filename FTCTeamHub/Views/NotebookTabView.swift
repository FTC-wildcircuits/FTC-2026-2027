//
//  NotebookTabView.swift
//  FTCTeamHub
//
//  TAB 4 — Engineering Notebook. Markdown entries with FTC-specific
//  structured templates, author stamping from the active session, and a
//  one-tap PDF export suitable for handing to Inspire Award judges.
//
//  Syntax notes carried over from a previous CI failure and deliberately
//  avoided here: every `@State` gets its own line (a property wrapper
//  cannot attach to a comma-separated variable list), and no `specifier:`
//  interpolation is used outside of `Text(_:)` — `String(format:)` is used
//  wherever a plain String is required (e.g. LabeledContent values, PDF text).
//

import SwiftUI
import SwiftData
import UIKit

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
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView("No notebook entries yet", systemImage: "book.closed",
                                           description: Text("Tap the pencil icon to add your first entry."))
                }
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

// MARK: - Detail (rendered Markdown + structured payloads + PDF export)

private struct NotebookEntryDetailView: View {
    let entry: NotebookEntry
    @State private var pdfURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.title).font(.title2.bold())
                Text("By \(entry.authorName) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                Text(.init(entry.content))

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    pdfURL = NotebookPDFExporter.export(entry: entry)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: Binding(get: { pdfURL.map(IdentifiableURL.init) }, set: { pdfURL = $0?.url })) { wrapped in
            ShareSheet(activityItems: [wrapped.url])
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Thin UIKit bridge for the system share sheet — SwiftUI's own `ShareLink`
/// works for simple cases, but wrapping `UIActivityViewController` directly
/// keeps this reusable for the freshly-generated PDF file URL.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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

// MARK: - PDF export (for Inspire Award judges)

enum NotebookPDFExporter {
    static func export(entry: NotebookEntry) -> URL? {
        let pageWidth: CGFloat = 612   // US Letter, 72 dpi
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 48
        let contentWidth = pageWidth - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let fileName = "notebook_\(entry.id.uuidString).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()

                var cursorY: CGFloat = margin

                let titleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 22)
                ]
                let title = entry.title as NSString
                title.draw(at: CGPoint(x: margin, y: cursorY), withAttributes: titleAttrs)
                cursorY += 32

                let metaAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.darkGray
                ]
                let meta = "By \(entry.authorName) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))" as NSString
                meta.draw(at: CGPoint(x: margin, y: cursorY), withAttributes: metaAttrs)
                cursorY += 28

                let bodyAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13)
                ]
                let bodyRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: pageHeight - cursorY - margin - 100)
                (entry.content as NSString).draw(in: bodyRect, withAttributes: bodyAttrs)
                cursorY += bodyRect.height + 16

                if let auto = entry.autonomousLog {
                    let text = "Autonomous Test — \(auto.routineName)\nStarting position: \(auto.startingPosition)\nScored: \(auto.samplesOrSpecimensScored)\nCycle time: \(String(format: "%.2f", auto.cycleTimeSeconds))s\nSuccess rate: \(String(format: "%.0f", auto.successRatePercent))%"
                    (text as NSString).draw(in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 100), withAttributes: bodyAttrs)
                }

                if let imu = entry.imuLog {
                    let text = "IMU Tuning — \(imu.chip)\nLogo facing: \(imu.logoFacingDirection)\nUSB facing: \(imu.usbFacingDirection)\nYaw offset: \(String(format: "%.2f", imu.yawOffsetDegrees))°"
                    (text as NSString).draw(in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 100), withAttributes: bodyAttrs)
                }
            }
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - New entry sheet, template-aware

private struct NewNotebookEntrySheet: View {
    let template: NotebookTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthenticationManager.self) private var authManager

    @State private var title = ""
    @State private var content = ""
    @State private var tagsInput = ""

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
        guard let currentUser = authManager.currentUser else { return }
        let tags = tagsInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let entry = NotebookEntry(authorID: currentUser.id, authorName: currentUser.name,
                                   title: title, content: content, tags: tags)

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
        context.insert(ActivityEvent(authorID: currentUser.id, authorName: currentUser.name, kind: .notebookEntry,
                                      message: "added notebook entry: \(title)"))
        dismiss()
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return NotebookTabView()
        .modelContainer(container)
        .environment(authManager)
}
