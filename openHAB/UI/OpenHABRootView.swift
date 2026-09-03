// Copyright (c) 2010-2026 Contributors to the openHAB project
//
// See the NOTICE file(s) distributed with this work for additional
// information.
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0
//
// SPDX-License-Identifier: EPL-2.0

import Combine
import OpenHABCore
import os.log
import SFSafeSymbols
import SwiftUI

/// Stromkreis shows exactly one surface: the member's openHAB MainUI in a web view.
/// The app is configured through the activation link / QR code, so there is no app
/// menu, no sitemaps, no tiles and no settings.
struct OpenHABRootView: View {
    @StateObject private var networkService = NetworkConnectionService()
    @StateObject private var webViewModel = OpenHABWebViewModel()
    @State private var navbarActionsPresented = false
    /// The MainUI route currently selected (nil = MainUI root). A reload always returns
    /// here rather than to an arbitrary route the user reached inside the SPA.
    @State private var currentPath: String?
    @State private var activeNetworkConnection: ConnectionInfo? = MainActorNetworkTracker.shared.activeConnection

    var body: some View {
        ZStack(alignment: .top) {
            OpenHABWebViewContainer(viewModel: webViewModel)
                .padding(.top, 44)
                .background(.clear)
            // Placeholder while a home is first loading. Sits above the (transparent)
            // web view but below the menu bar, so the bar stays reachable while connecting.
            if !webViewModel.hasLoadedContent {
                ConnectingPlaceholder()
                    .transition(.opacity)
            }
            menuBar
        }
        .animation(.easeInOut(duration: 0.25), value: webViewModel.hasLoadedContent)
        .onAppear {
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["UITestWebViewMode"] != nil,
               let encoded = env["UITestInjectHTML"],
               let data = Data(base64Encoded: encoded),
               let html = String(data: data, encoding: .utf8) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    webViewModel.loadHTMLString(html)
                }
            }
            if let json = env["UITestWebViewNavbarItems"],
               let data = json.data(using: .utf8),
               let raw = try? JSONDecoder().decode([[String: String]].self, from: data) {
                let items = raw.compactMap { d -> WebNavbarItem? in
                    guard let label = d["label"], let action = d["jsAction"] else { return nil }
                    return WebNavbarItem(label: label, jsAction: action, iconBase64: nil, isBack: false)
                }
                webViewModel.lockUITestContent()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    webViewModel.updateNavbarItems(items)
                }
            }
            #endif
            restoreSavedPath()
            webViewModel.onExitToApp = nil
            webViewModel.triggerAppMenuProbe()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("net.stromkreis.preferences.saved"))) { _ in
            webViewModel.reloadView()
        }
        .task {
            for await connection in MainActorNetworkTracker.shared.$activeConnection.values {
                activeNetworkConnection = connection
            }
        }
        .alert(
            networkService.certificateAlert?.title ?? "",
            isPresented: Binding(
                get: { networkService.certificateAlert != nil },
                set: { if !$0 { networkService.certificateAlert = nil } }
            )
        ) {
            Button("Always") { networkService.certificateAlertAction(.permitAlways) }
            Button("Once") { networkService.certificateAlertAction(.permitOnce) }
            Button("Deny", role: .cancel) { networkService.certificateAlertAction(.deny) }
        } message: {
            Text(networkService.certificateAlert?.message ?? "")
        }
        #if DEBUG
        .overlay {
            ForEach(Array(webViewModel.uiTestReports.keys.sorted()), id: \.self) { key in
                Text(webViewModel.uiTestReports[key] ?? "")
                    .accessibilityIdentifier("UITestReport-\(key)")
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
            Text(String(webViewModel.navbarItems.count))
                .accessibilityIdentifier("UITestReport-navbarItemCount")
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
        }
        #endif
    }

    // MARK: - Menu bar

    @ViewBuilder
    private var menuBar: some View {
        HStack {
            // Left side: proxied navbar items when available, otherwise the connection state.
            Group {
                if !webViewModel.navbarItems.isEmpty {
                    let backItem = webViewModel.navbarItems.first { $0.isBack }
                    let otherItems = webViewModel.navbarItems.filter { !$0.isBack }
                    HStack(spacing: 4) {
                        // Back button is always shown directly in the bar when present.
                        if let backItem {
                            navbarProxyButton(backItem)
                        }
                        // When a back button is present, remaining items always go in a
                        // popover — even a single item, which may be text-only and too wide
                        // to sit next to the back button. Without a back button, a single
                        // item is shown directly.
                        if !otherItems.isEmpty {
                            if backItem != nil || otherItems.count > 1 {
                                navbarActionsButton(otherItems)
                            } else if let single = otherItems.first {
                                navbarProxyButton(single)
                            }
                        }
                    }
                } else if activeNetworkConnection == nil {
                    HStack(spacing: 4) {
                        Image(systemSymbol: .wifiExclamationmark)
                        Text("Offline")
                            .font(.subheadline)
                        Button { reload() } label: {
                            Image(systemSymbol: .arrowClockwise)
                        }
                    }
                    .foregroundStyle(.secondary)
                } else if webViewModel.isLoading {
                    HStack(spacing: 4) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.leading)

            Spacer()

            Spacer().frame(width: 16)
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MainMenuBar")
        .overlay {
            if !webViewModel.navbarTitle.isEmpty {
                Text(webViewModel.navbarTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: 200)
                    .allowsHitTesting(false)
            }
        }
        .background(.bar, ignoresSafeAreaEdges: .top)
    }

    // MARK: - Navbar proxy helpers

    @ViewBuilder
    private func navbarProxyButton(_ item: WebNavbarItem) -> some View {
        Button {
            webViewModel.evaluateJS(item.jsAction)
        } label: {
            if let uiImg = item.iconImage {
                Image(uiImage: uiImg)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
            } else {
                Text(item.label)
            }
        }
        .accessibilityLabel(item.label)
        .accessibilityIdentifier("NavbarProxyButton-\(item.label)")
    }

    @ViewBuilder
    private func navbarActionsButton(_ items: [WebNavbarItem]) -> some View {
        Button {
            navbarActionsPresented = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
        }
        .accessibilityLabel("Actions")
        .accessibilityIdentifier("NavbarActionsMenu")
        .popover(isPresented: $navbarActionsPresented) {
            HStack(spacing: 20) {
                ForEach(items) { item in
                    Button {
                        webViewModel.evaluateJS(item.jsAction)
                        navbarActionsPresented = false
                    } label: {
                        if let uiImg = item.iconImage {
                            Image(uiImage: uiImg)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                        } else {
                            Text(item.label)
                        }
                    }
                    .accessibilityLabel(item.label)
                    .accessibilityIdentifier("NavbarProxyButton-\(item.label)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .presentationDetents([.height(72)])
            .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Navigation

    /// Selects the MainUI route persisted for the active home. The web view's actual load is
    /// driven by `syncActiveConnection`, so here only the destination is chosen.
    private func restoreSavedPath() {
        let path = Preferences.shared.currentHomePreferences.defaultMainUIPath
        currentPath = path.isEmpty ? nil : path
    }

    /// Reloads the destination currently selected — never the arbitrary route the user may have
    /// reached inside the SPA — so a reload always lands somewhere well defined.
    private func reload() {
        webViewModel.loadWebView(force: true, path: currentPath)
    }
}

// MARK: - Connecting placeholder

/// Shown centered over the (transparent) web view while a home is first loading. While the
/// tracker is still trying, the logo gently breathes above a spinner. Once an attempt has
/// failed it switches to a warning: a countdown to the next retry, or — when the tracker has
/// given up — a static "cannot connect" message.
private struct ConnectingPlaceholder: View {
    @ObservedObject private var networkTracker = MainActorNetworkTracker.shared

    private enum Phase: Equatable {
        case connecting
        case retrying(Date)
        case failed
        case noNetwork
    }

    private var phase: Phase {
        if !networkTracker.isNetworkAvailable {
            return .noNetwork
        }
        if let retry = networkTracker.nextRetryDate, retry.timeIntervalSinceNow > 0 {
            return .retrying(retry)
        }
        if networkTracker.status == .stopped {
            return .failed
        }
        return .connecting
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                switch phase {
                case .connecting:
                    PulsingLogo()
                    label(spinner: true) { Text("Connecting…") }
                case let .retrying(date):
                    statusIcon(.exclamationmarkTriangle)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = max(0, Int(date.timeIntervalSince(context.date).rounded(.up)))
                        label(spinner: false) { Text("Cannot connect — retrying in \(remaining)s") }
                    }
                case .failed:
                    statusIcon(.exclamationmarkTriangle)
                    label(spinner: false) { Text("Cannot connect to the server") }
                case .noNetwork:
                    statusIcon(.wifiSlash)
                    label(spinner: false) { Text("No network connection") }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: phase)
        }
    }

    private func statusIcon(_ symbol: SFSymbol) -> some View {
        Image(systemSymbol: symbol)
            .font(.system(size: 52))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
    }

    private func label(spinner: Bool, @ViewBuilder text: () -> some View) -> some View {
        HStack(spacing: 8) {
            if spinner {
                ProgressView().controlSize(.small)
            }
            text()
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// The app mark breathing (opacity + scale). Extracted so that each time the connecting
/// phase reappears a fresh instance restarts the repeating animation from its `onAppear`.
private struct PulsingLogo: View {
    @State private var animating = false

    var body: some View {
        Image("openHABIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .opacity(animating ? 1.0 : 0.55)
            .scaleEffect(animating ? 1.0 : 0.94)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: animating)
            .onAppear { animating = true }
    }
}
