// ios/PetHomepage/Features/Pairing/PairDeviceView.swift
import Observation
import SwiftUI
import VisionKit

enum PairState: Equatable {
    case idle
    case claiming
    case paired
    case failed(String)
}

/// Drives "Pair a device": take a code (from a scanned QR or typed in), claim it, and on
/// success hand the minted token + push endpoint back to the caller (Settings) to store.
@Observable
final class PairDeviceViewModel {
    var state: PairState = .idle
    var manualCode = ""

    private let service: PairingService
    private let onPaired: (_ token: String, _ endpoint: String) -> Void

    init(service: PairingService, onPaired: @escaping (String, String) -> Void) {
        self.service = service
        self.onPaired = onPaired
    }

    /// Claim from a scanned QR payload — our JSON `{"e": <site origin>, "c": <code>}`.
    func claimScanned(_ payload: String) async {
        guard state == .idle || isFailed else { return }
        let parsed = Self.parseQR(payload)
        await claim(code: parsed.code, endpoint: parsed.endpoint)
    }

    /// Claim from a typed code, using the build-time default endpoint.
    func claimManual() async {
        let code = manualCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        await claim(code: code, endpoint: PairingDefaults.pairEndpoint)
    }

    private var isFailed: Bool { if case .failed = state { return true } else { return false } }

    private func claim(code: String, endpoint: URL) async {
        state = .claiming
        do {
            let result = try await service.pair(code: code, endpoint: endpoint)
            onPaired(result.token, result.pushEndpoint)
            state = .paired
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Parse the QR JSON. Falls back to treating the whole payload as a bare code.
    static func parseQR(_ payload: String) -> (code: String, endpoint: URL) {
        if let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["c"] as? String {
            let origin = (obj["e"] as? String) ?? ""
            let endpoint = URL(string: origin + "/mirror/pair") ?? PairingDefaults.pairEndpoint
            return (code, endpoint)
        }
        return (payload, PairingDefaults.pairEndpoint)
    }

    static func message(for error: Error) -> String {
        switch error {
        case PairingError.badStatus(401):
            return "That code is invalid or expired. Generate a new one on the dashboard."
        case PairingError.badStatus(let code):
            return "Pairing failed (HTTP \(code))."
        case PairingError.badResponse:
            return "Unexpected response from the server."
        default:
            return "Couldn’t reach the server. Check your connection and try again."
        }
    }
}

struct PairDeviceView: View {
    @State private var model: PairDeviceViewModel
    @Environment(\.dismiss) private var dismiss

    init(service: PairingService, onPaired: @escaping (String, String) -> Void) {
        _model = State(initialValue: PairDeviceViewModel(service: service, onPaired: onPaired))
    }

    private var scannerSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.state {
                case .paired:
                    Section {
                        Label("Paired! Your phone will now mirror to the dashboard.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.ok)
                        Button("Done") { dismiss() }
                    }

                default:
                    if scannerSupported {
                        Section("Scan the QR on your dashboard") {
                            QRScannerView { payload in
                                Task { await model.claimScanned(payload) }
                            }
                            .frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .listRowInsets(EdgeInsets())
                        }
                    }

                    Section(scannerSupported ? "Or enter the code" : "Enter the code from your dashboard") {
                        TextField("e.g. K7P2 9QX4", text: $model.manualCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(.title3, design: .monospaced))
                        Button {
                            Task { await model.claimManual() }
                        } label: {
                            Text("Pair").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowBackground(Color.clear)
                        .disabled(model.manualCode.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if model.state == .claiming {
                        Section { HStack { ProgressView(); Text("Pairing…").foregroundStyle(Theme.inkSoft) } }
                    }
                    if case .failed(let message) = model.state {
                        Section {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
            .navigationTitle("Pair a device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.primary)
            .presentationDragIndicator(.visible)
        }
    }
}

/// Wraps VisionKit's live QR scanner. Reports the first QR payload it recognizes.
private struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var fired = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !fired else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item, let payload = barcode.payloadStringValue {
                    fired = true
                    onScan(payload)
                    return
                }
            }
        }
    }
}
