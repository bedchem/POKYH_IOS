import SwiftUI
import AVFoundation
import UIKit
import Vision
import VisionKit
import PokyhCore
import PokyhDesign

extension AppState {
    /// The computer waiting for a scanned code. Nil: the code ran out or was used already.
    func webSignInInfo(code: String) async throws -> BackendClient.QrLoginInfo? {
        guard let token = session?.apiToken else { throw AppError.sessionExpired }
        return try await BackendClient.shared.qrLoginInfo(code: code, token: token)
    }

    /// Signs the computer in: it takes over the app's WebUntis session, so it needs no
    /// authenticator code, and the saved password or app key renews it later. Only what this
    /// unlock already covers; never a Face ID sheet of its own. False: the code ran out meanwhile.
    func approveWebSignIn(code: String) async throws -> Bool {
        guard let s = session, let token = s.apiToken else { throw AppError.sessionExpired }
        let saved = CredentialStore.shared.password(for: s.username, context: UnlockSession.context)
        let isKey = saved.map(AppKey.isKey) ?? false
        let credential = BackendClient.QrCredential(
            username: s.username,
            password: isKey ? nil : saved,
            key: isKey ? saved.map { String($0.dropFirst(AppKey.prefix.count)) } : nil,
            sessionId: s.hasUntis ? s.sessionId : nil,
            school: s.hasUntis ? s.schoolRef : nil)
        return try await BackendClient.shared.approveQrLogin(code: code, credential: credential, token: token)
    }
}

/// The scanner has no Android text to come from: Android's own names Google Play.
private struct QrText {
    let unavailable: String

    static func of(_ lang: Lang) -> QrText {
        switch lang {
        case .de: QrText(unavailable: "Dieses Gerät kann keine QR-Codes scannen. Melde dich auf dem Computer direkt mit deinem Passwort an.")
        case .it: QrText(unavailable: "Questo dispositivo non può scansionare codici QR. Accedi direttamente sul computer con la tua password.")
        case .en: QrText(unavailable: "This device can’t scan QR codes. Sign in on the computer with your password instead.")
        }
    }
}

/// "Am Computer anmelden": scans the code pokyh.com shows, says which computer asks and where it
/// is, and once confirmed signs it in as this account. Hangs off the settings' row.
struct WebSignInHost: ViewModifier {
    @Binding var scanning: Bool
    @Binding var working: Bool
    /// The app shell's copy answers codes opened from the camera; the settings' one scans.
    var takesLinks = false
    @EnvironmentObject var app: AppState
    @Environment(\.strings) private var s
    @State private var scanned: String?
    @State private var confirm: Confirmation?
    @State private var done = false
    @State private var failure: Failure?

    private struct Confirmation: Equatable {
        let code: String
        let info: BackendClient.QrLoginInfo
    }

    private struct Failure: Equatable {
        let message: String
        let scanAgain: Bool
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: app.pendingWebSignIn, initial: true) { _, code in
                guard takesLinks, let code else { return }
                app.pendingWebSignIn = nil
                Task { await lookUp(code) }
            }
            .fullScreenCover(isPresented: $scanning, onDismiss: handleScan) {
                QrScannerScreen { text in
                    scanned = text
                    scanning = false
                }
            }
            .alert(s.settings.webSignInConfirmTitle, isPresented: isUp($confirm)) {
                Button(s.settings.webSignInConfirm) {
                    if let code = confirm?.code { Task { await approve(code) } }
                }
                Button(s.common.cancel, role: .cancel) {}
            } message: {
                Text(confirmBody)
            }
            .alert(s.settings.webSignInDoneTitle, isPresented: $done) {
                Button(s.common.ok, role: .cancel) {}
            } message: {
                Text(s.settings.webSignInDoneBody)
            }
            .alert(s.settings.webSignIn, isPresented: isUp($failure)) {
                if failure?.scanAgain == true {
                    Button(s.settings.webSignInScanAgain) { scanAgain() }
                    Button(s.common.cancel, role: .cancel) {}
                } else {
                    Button(s.common.ok, role: .cancel) {}
                }
            } message: {
                Text(failure?.message ?? "")
            }
    }

    private func isUp<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }

    private var confirmBody: String {
        guard let info = confirm?.info else { return "" }
        let label = info.label.trimmingCharacters(in: .whitespaces)
        let place = [info.place, info.ip ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        var lines = [label.isEmpty ? s.settings.webSignInUnknownDevice : label]
        if !place.isEmpty { lines.append(place) }
        return lines.joined(separator: "\n") + "\n\n" + s.settings.webSignInConfirmHint
    }

    private func handleScan() {
        guard let text = scanned else { return }
        scanned = nil
        guard let code = WebSignInCode.of(text, host: AppConfig.current.websiteURL.host()) else {
            failure = Failure(message: s.settings.webSignInNotPokyh, scanAgain: true)
            return
        }
        Task { await lookUp(code) }
    }

    /// The alert has to be gone first, or the cover doesn't come up.
    private func scanAgain() {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            scanning = true
        }
    }

    private func lookUp(_ code: String) async {
        working = true
        defer { working = false }
        do {
            if let info = try await app.webSignInInfo(code: code) {
                confirm = Confirmation(code: code, info: info)
            } else {
                failure = Failure(message: s.settings.webSignInGone, scanAgain: true)
            }
        } catch {
            failure = Failure(message: readable(error), scanAgain: false)
        }
    }

    private func approve(_ code: String) async {
        working = true
        defer { working = false }
        do {
            if try await app.approveWebSignIn(code: code) {
                done = true
            } else {
                failure = Failure(message: s.settings.webSignInGone, scanAgain: true)
            }
        } catch {
            failure = Failure(message: readable(error), scanAgain: false)
        }
    }

    private func readable(_ error: Error) -> String {
        guard let error = error as? AppError else {
            return error is URLError ? s.common.noConnection : s.common.unknownError
        }
        return error.isSessionExpired ? s.common.sessionExpired : error.message
    }
}

// ── The scanner ──────────────────────────────────────────────────────────────

/// The camera full screen, dimmed around a square where the code goes, the prompt under it and a
/// way out. Asks for the camera the first time; refused, it says so and leads to the settings.
/// Simulators and devices without the scanner get a plain message instead of a black screen.
struct QrScannerScreen: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL
    @State private var camera = Camera.asking

    private enum Camera { case asking, ready, refused, unavailable }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera == .ready {
                DataScanner(onCode: onCode, onUnavailable: { camera = .unavailable })
                    .ignoresSafeArea()
                Viewfinder()
            }
            VStack(spacing: 0) {
                HStack(spacing: Spacing.xs) {
                    Button(role: .close) { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel(s.common.close)
                    Text(s.settings.webSignIn)
                        .textStyle(.headline)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                }
                .padding(Spacing.sm)
                Spacer(minLength: 0)
                VStack(spacing: Spacing.lg) {
                    if let message {
                        Text(message)
                            .textStyle(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    if camera == .refused, let url = URL(string: UIApplication.openSettingsURLString) {
                        Button(s.account.openSettings) { openURL(url) }
                            .buttonStyle(.primary)
                    }
                }
                .padding(.horizontal, Spacing.xxxl)
                .padding(.vertical, Spacing.huge)
            }
        }
        .environment(\.colorScheme, .dark)
        .task { camera = await Self.cameraState() }
    }

    private var message: String? {
        switch camera {
        case .asking: nil
        case .ready: s.account.scanPrompt
        case .refused: s.account.cameraNeeded
        case .unavailable: QrText.of(s.lang).unavailable
        }
    }

    /// The scanner first: on a device without one there's no point asking for the camera.
    private static func cameraState() async -> Camera {
        guard DataScannerViewController.isSupported else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .refused }
        default: return .refused
        }
        return DataScannerViewController.isAvailable ? .ready : .unavailable
    }
}

/// VisionKit's scanner, reading QR codes until the first one. It pauses by itself in the
/// background and is started again on the way back.
private struct DataScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onUnavailable: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.onUnavailable = onUnavailable
        guard scenePhase == .active, !scanner.isScanning, !context.coordinator.finished else { return }
        do {
            try scanner.startScanning()
        } catch {
            onUnavailable()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onUnavailable: onUnavailable)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        var onUnavailable: () -> Void
        private(set) var finished = false

        init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onCode = onCode
            self.onUnavailable = onUnavailable
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !finished else { return }
            for case .barcode(let code) in addedItems {
                guard let text = code.payloadStringValue else { continue }
                finished = true
                scanner.stopScanning()
                onCode(text)
                return
            }
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onUnavailable()
        }
    }
}

/// The picture dimmed around a square in the middle, its corners marked.
private struct Viewfinder: View {
    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) * 0.68
            let frame = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2 - size.height * 0.04, width: side, height: side)
            let radius: CGFloat = 28
            var hole = Path(CGRect(origin: .zero, size: size))
            hole.addRoundedRect(in: frame, cornerSize: CGSize(width: radius, height: radius), style: .circular)
            context.fill(hole, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
            context.stroke(Self.corners(of: frame, radius: radius, leg: side * 0.08), with: .color(.white),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func corners(of r: CGRect, radius: CGFloat, leg: CGFloat) -> Path {
        var path = Path()
        func corner(_ center: CGPoint, from start: Double, startPoint: CGPoint, endPoint: CGPoint) {
            path.move(to: startPoint)
            path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + 90), clockwise: false)
            path.addLine(to: endPoint)
        }
        let inset = radius
        corner(CGPoint(x: r.minX + inset, y: r.minY + inset), from: 180,
               startPoint: CGPoint(x: r.minX, y: r.minY + inset + leg), endPoint: CGPoint(x: r.minX + inset + leg, y: r.minY))
        corner(CGPoint(x: r.maxX - inset, y: r.minY + inset), from: 270,
               startPoint: CGPoint(x: r.maxX - inset - leg, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.minY + inset + leg))
        corner(CGPoint(x: r.maxX - inset, y: r.maxY - inset), from: 0,
               startPoint: CGPoint(x: r.maxX, y: r.maxY - inset - leg), endPoint: CGPoint(x: r.maxX - inset - leg, y: r.maxY))
        corner(CGPoint(x: r.minX + inset, y: r.maxY - inset), from: 90,
               startPoint: CGPoint(x: r.minX + inset + leg, y: r.maxY), endPoint: CGPoint(x: r.minX, y: r.maxY - inset - leg))
        return path
    }
}

#Preview("Scanner") {
    QrScannerScreen { _ in }
}

#Preview("Viewfinder") {
    ZStack {
        Color.gray
        Viewfinder()
    }
}
