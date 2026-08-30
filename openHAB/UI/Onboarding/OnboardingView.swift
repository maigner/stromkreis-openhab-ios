// Copyright (c) 2026 Stromkreis contributors
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0
//
// SPDX-License-Identifier: EPL-2.0

import OpenHABCore
import SFSafeSymbols
import SwiftUI

/// First-run screen: scan the one-time QR code from the member's Stromkreis page (or paste
/// the setup link) to configure the Stromkreis Cloud connection.
struct OnboardingView: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var pastedLink = ""
    @State private var scannerMessage: String?
    @State private var scannerID = UUID()
    @FocusState private var linkFieldFocused: Bool

    private var canDismiss: Bool { StromkreisSetup.isActiveHomeConfigured }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0x1d / 255, green: 0x47 / 255, blue: 0x16 / 255),
                         Color(red: 0x3f / 255, green: 0x8a / 255, blue: 0x26 / 255),
                         Color(red: 0x63 / 255, green: 0xb5 / 255, blue: 0x3b / 255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    switch coordinator.phase {
                    case .working:
                        statusCard {
                            ProgressView().tint(.white)
                            Text("Setting up your Stromkreis connection…")
                        }
                    case let .succeeded(name):
                        statusCard {
                            Image(systemSymbol: .checkmarkCircleFill).font(.system(size: 44)).foregroundStyle(.white)
                            Text("Connected to \(name)")
                                .font(.headline)
                            Text("Your Stromkreis app is ready.")
                            Button("Continue") { coordinator.dismiss() }
                                .buttonStyle(.borderedProminent)
                                .tint(.white)
                                .foregroundStyle(Color(red: 0x1d / 255, green: 0x47 / 255, blue: 0x16 / 255))
                        }
                    case let .failed(message):
                        statusCard {
                            Image(systemSymbol: .exclamationmarkTriangleFill).font(.system(size: 44)).foregroundStyle(.yellow)
                            Text(message).multilineTextAlignment(.center)
                            Button("Try again") {
                                coordinator.reset()
                                scannerID = UUID()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(Color(red: 0x1d / 255, green: 0x47 / 255, blue: 0x16 / 255))
                        }
                    case .idle:
                        if let notice = coordinator.notice {
                            statusCard {
                                Image(systemSymbol: .exclamationmarkTriangleFill).font(.system(size: 44)).foregroundStyle(.yellow)
                                Text(notice).multilineTextAlignment(.center)
                            }
                            .accessibilityIdentifier("OnboardingNotice")
                        }
                        scannerCard
                        pasteCard
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(.white)
        .overlay(alignment: .topTrailing) {
            if canDismiss, coordinator.phase != .working {
                Button {
                    coordinator.dismiss()
                } label: {
                    Image(systemSymbol: .xmarkCircleFill)
                        .font(.title)
                        .foregroundStyle(.white.opacity(0.85))
                        .padding()
                }
                .accessibilityLabel(Text("Close"))
            }
        }
        .interactiveDismissDisabled(!canDismiss)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image("openHABIcon")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color(red: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255))
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .padding(.top, 24)
            Text("Welcome to Stromkreis")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Scan the one-time QR code from your Stromkreis page to connect the app to your energy community's gateway.")
                .font(.body)
                .multilineTextAlignment(.center)
                .opacity(0.9)
        }
    }

    private var scannerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                QRScannerView(
                    onCode: { coordinator.handle(text: $0) },
                    onUnavailable: { scannerMessage = $0 }
                )
                .id(scannerID)
                if let scannerMessage {
                    Text(scannerMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                }
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(red: 0xf5 / 255, green: 0x9e / 255, blue: 0x0b / 255), lineWidth: 3)
                    .padding(28)
                    .allowsHitTesting(false)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            Text("Point the camera at the QR code")
                .font(.footnote)
                .opacity(0.85)
        }
        .padding(12)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("OnboardingScanner")
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Received a setup link instead?")
                .font(.headline)
            Text("Opening the link on this phone sets the app up automatically. You can also paste it here.")
                .font(.footnote)
                .opacity(0.85)
            HStack {
                TextField("https://stromkreis.net/app/setup/…", text: $pastedLink)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($linkFieldFocused)
                    .foregroundStyle(Color.primary)
                    .onSubmit(submitPasted)
                    .accessibilityIdentifier("OnboardingLinkField")
                Button {
                    submitPasted()
                } label: {
                    Image(systemSymbol: .arrowRightCircleFill).font(.title)
                }
                .disabled(pastedLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(Text("Connect"))
            }
        }
        .padding(16)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) { content() }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
    }

    private func submitPasted() {
        linkFieldFocused = false
        coordinator.handle(text: pastedLink)
    }
}

#Preview {
    OnboardingView(coordinator: OnboardingCoordinator())
}
