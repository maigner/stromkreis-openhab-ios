// Copyright (c) 2026 Stromkreis contributors
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0
//
// SPDX-License-Identifier: EPL-2.0

import Combine
import Foundation
import OpenHABCore
import os.log

extension Notification.Name {
    /// Posted when a server rejected the stored connection credentials (e.g. the
    /// Stromkreis Cloud password changed) so the QR/link setup can be shown again.
    static let stromkreisCredentialsRejected = Notification.Name("net.stromkreis.credentials.rejected")
}

/// Drives the first-run setup: shows the onboarding screen until the active home has a
/// Stromkreis Cloud login, and applies setup links that arrive via QR scan, paste, the
/// `stromkreis://` scheme or a `https://stromkreis.net/app/setup/…` universal link.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case working
        case failed(String)
        case succeeded(String)
    }

    @Published var isPresented: Bool
    @Published private(set) var phase: Phase = .idle
    /// Explains why setup reappeared (e.g. rejected credentials). Shown above the
    /// scanner until a new setup link succeeds.
    @Published private(set) var notice: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        isPresented = !StromkreisSetup.isActiveHomeConfigured
        Preferences.shared.currentHomePreferencesPublisher
            .map { StromkreisSetup.isConfigured($0) }
            .removeDuplicates()
            .sink { [weak self] configured in
                guard let self else { return }
                if !configured, phase == .idle {
                    isPresented = true
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .stromkreisCredentialsRejected)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                notice = String(localized: "Your access is no longer valid — for example because the password was changed. Scan the QR code from your Stromkreis page again or paste a new setup link.")
                if phase != .working {
                    phase = .idle
                }
                isPresented = true
            }
            .store(in: &cancellables)
    }

    /// Returns true when the URL was a Stromkreis setup link and has been taken over.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let link = StromkreisSetup.parse(url) else { return false }
        isPresented = true
        Task { await run(link) }
        return true
    }

    /// Handles scanned or pasted text. Reports an error when it is not a setup code.
    func handle(text: String) {
        guard let link = StromkreisSetup.parse(text) else {
            phase = .failed(String(localized: "This is not a Stromkreis setup code. Scan the QR code from your Stromkreis page or paste the setup link."))
            return
        }
        Task { await run(link) }
    }

    func reset() {
        phase = .idle
    }

    func dismiss() {
        phase = .idle
        isPresented = false
    }

    private func run(_ link: StromkreisSetupLink) async {
        guard phase != .working else { return }
        phase = .working
        do {
            let creds = try await StromkreisSetup.resolve(link)
            StromkreisSetup.apply(creds)
            NotificationCenter.default.post(name: NSNotification.Name("net.stromkreis.preferences.saved"), object: nil)
            let name = creds.siteName?.trimmingCharacters(in: .whitespacesAndNewlines)
            notice = nil
            phase = .succeeded(name?.isEmpty == false ? name! : creds.username)
        } catch let error as StromkreisSetupError {
            phase = .failed(Self.message(for: error))
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private static func message(for error: StromkreisSetupError) -> String {
        switch error {
        case .unrecognizedPayload:
            String(localized: "This is not a Stromkreis setup code. Scan the QR code from your Stromkreis page or paste the setup link.")
        case let .tokenRejected(status, message):
            if let message, !message.isEmpty {
                message
            } else if [401, 403, 404, 410].contains(status) {
                String(localized: "This setup code is invalid or has already been used. Ask your Stromkreis admin for a new one.")
            } else {
                String(localized: "The Stromkreis server rejected the setup code (HTTP \(status)).")
            }
        case .invalidResponse:
            String(localized: "The Stromkreis server sent an unexpected reply. Please try again later.")
        case let .network(detail):
            String(localized: "Could not reach the Stromkreis server. Check your internet connection and try again.") + "\n\(detail)"
        }
    }
}
