//
//  QRScannerView.swift
//  FTCTeamHub
//
//  Camera-based check-in/check-out flow: scan an inventory item's
//  printed QR label to toggle its checked-out state, logged to the
//  activity feed. Built on VisionKit's DataScannerViewController.
//

import SwiftUI
import VisionKit
import SwiftData
import UIKit

/// Thin UIKit bridge around VisionKit's live QR scanner.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onStartError: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        do {
            try controller.startScanning()
        } catch {
            onStartError(error.localizedDescription)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    onScan(payload)
                }
            }
        }
    }
}

struct QRCheckInOutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @Query private var items: [InventoryItem]

    @State private var scannedItem: InventoryItem?
    @State private var scanErrorMessage: String?

    private var isCameraAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        ZStack {
            if isCameraAvailable {
                DataScannerRepresentable(onScan: handleScan) { error in
                    scanErrorMessage = "The scanner could not start: \(error)"
                }
                    .ignoresSafeArea()
            } else {
                FTCDesign.groupedBackground.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(DataScannerViewController.isSupported
                         ? "Camera access is unavailable. Check camera permissions in Settings."
                         : "This device doesn't support live camera scanning.")
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                            .padding(FTCDesign.space8)
                            .background(.regularMaterial, in: Circle())
                            .frame(minWidth: FTCDesign.minimumHitTarget, minHeight: FTCDesign.minimumHitTarget)
                    }
                    Spacer()
                }
                .padding()
                Spacer()

                if let scanErrorMessage {
                    Text(scanErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: FTCDesign.controlRadius))
                        .padding(.bottom, 8)
                }
            }

            if let item = scannedItem {
                VStack(spacing: 12) {
                    Text(item.name).font(.headline)
                    Text("\(item.category) · Bin \(item.binLocation)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.needsMaintenance ? "Needs maintenance" :
                         item.quantity == 0 ? "Out of stock" :
                         item.isCheckedOut ? "Currently checked out" : "Currently in storage")
                        .font(.caption2)
                        .foregroundStyle(item.needsMaintenance || item.quantity == 0 ? .red :
                                         item.isCheckedOut ? .orange : .green)

                    Button {
                        toggleCheckout(item)
                    } label: {
                        Label(item.isCheckedOut ? "Check In" : "Check Out",
                              systemImage: item.isCheckedOut ? "arrow.uturn.down" : "arrow.up.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!item.isCheckedOut && (item.quantity == 0 || item.needsMaintenance))

                    Button("Scan Another") { scannedItem = nil }
                        .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: 320)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: FTCDesign.cardRadius, style: .continuous))
                .padding(.bottom, 40)
            }
        }
        .sensoryFeedback(.success, trigger: scannedItem?.id)
        .sensoryFeedback(.error, trigger: scanErrorMessage)
    }

    private func handleScan(_ payload: String) {
        guard scannedItem == nil else { return }

        guard payload.hasPrefix("ftcteamhub:item:"),
              let idString = payload.split(separator: ":").last,
              let id = UUID(uuidString: String(idString)),
              let item = items.first(where: { $0.id == id }) else {
            scanErrorMessage = "That QR code isn't a recognized FTC Team Hub item label."
            return
        }
        scanErrorMessage = nil
        scannedItem = item
    }

    private func toggleCheckout(_ item: InventoryItem) {
        guard let user = authManager.currentUser else { return }
        guard item.isCheckedOut || (item.quantity > 0 && !item.needsMaintenance) else { return }
        item.isCheckedOut.toggle()
        item.checkedOutByName = item.isCheckedOut ? user.name : ""
        syncService?.pushInventoryItem(item)

        let event = ActivityEvent(
            authorID: user.id, authorName: user.name, kind: .inventoryUpdated,
            message: (item.isCheckedOut ? "checked out via QR scan: " : "returned via QR scan: ") + item.name
        )
        context.insert(event)
        syncService?.pushActivity(event)

        scannedItem = nil
    }
}
