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

import Foundation
import os.log

/// Cloud login for a member's Stromkreis gateway, as handed out by the Stromkreis platform.
public struct StromkreisCloudCredentials: Codable, Equatable, Sendable {
    public var cloudUrl: String
    public var username: String
    public var password: String
    public var siteName: String?

    public init(cloudUrl: String = StromkreisSetup.defaultCloudURL, username: String, password: String, siteName: String? = nil) {
        self.cloudUrl = cloudUrl
        self.username = username
        self.password = password
        self.siteName = siteName
    }
}

/// What a scanned QR code or an opened link asks the app to do.
public enum StromkreisSetupLink: Equatable, Sendable {
    /// A one-time token that must be redeemed at the Stromkreis platform (`origin`) for credentials.
    case token(String, origin: URL)
    /// Credentials embedded directly in the code (offline QR codes).
    case credentials(StromkreisCloudCredentials)
}

public enum StromkreisSetupError: Error, Equatable {
    case unrecognizedPayload
    /// The platform rejected the token; carries the HTTP status and the server's `error` text, if any.
    case tokenRejected(status: Int, message: String?)
    case invalidResponse
    case network(String)
}

/// Parses Stromkreis setup links / QR payloads and redeems one-time tokens.
///
/// Accepted payloads:
/// - `https://stromkreis.net/app/setup/<token>` (also `?token=<token>`) — universal link, printed as QR code
/// - `stromkreis://setup?token=<token>[&origin=https://stromkreis.net]` — custom scheme fallback
/// - `stromkreis://setup?cloudUrl=…&username=…&password=…[&siteName=…]` — inline credentials
/// - JSON `{"v":1,"username":"…","password":"…"[,"cloudUrl":"…","siteName":"…"]}` — inline credentials
///
/// Redeeming: `POST <origin>/api/app/setup/v1` with body `{"token":"…"}` returns
/// `{"cloudUrl":"…","username":"…","password":"…","siteName":"…"}` (`cloudUrl` and `siteName` optional).
/// Any non-2xx reply may carry `{"error":"human readable reason"}`.
public enum StromkreisSetup {
    public static let defaultCloudURL = "https://hac.stromkreis.net"
    public static let platformOrigin = URL(string: "https://stromkreis.net")!
    public static let urlScheme = "stromkreis"
    public static let setupPathPrefix = "/app/setup"
    public static let redeemPath = "/api/app/setup/v1"
    public static let trustedDomain = "stromkreis.net"

    /// True for `https` URLs on `stromkreis.net` or one of its subdomains. The app never talks to anything else.
    public static func isTrusted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == trustedDomain || host.hasSuffix(".\(trustedDomain)")
    }

    /// For an `http` URL on the trusted domain, the same URL over `https`; `nil` for anything else.
    /// Used to upgrade redirects that a proxied server emits with the wrong scheme.
    public static func upgradedToHTTPS(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        if components.port == 80 { components.port = nil }
        guard let upgraded = components.url, isTrusted(upgraded) else { return nil }
        return upgraded
    }

    private static func isTrusted(_ urlString: String) -> Bool {
        URL(string: urlString).map(isTrusted) ?? false
    }

    // MARK: Parsing

    public static func parse(_ text: String) -> StromkreisSetupLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8), let creds = parseJSON(data) {
            return .credentials(creds)
        }
        guard let url = URL(string: trimmed) else { return nil }
        return parse(url)
    }

    public static func parse(_ url: URL) -> StromkreisSetupLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let query = Dictionary((components.queryItems ?? []).compactMap { item -> (String, String)? in
            guard let value = item.value, !value.isEmpty else { return nil }
            return (item.name, value)
        }, uniquingKeysWith: { first, _ in first })

        if components.scheme?.lowercased() == urlScheme {
            // stromkreis://setup?...  — host is "setup" (or the path when written as stromkreis:/setup)
            let action = (components.host ?? components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
            guard action == "setup" else { return nil }
            if let creds = credentials(from: query) {
                return .credentials(creds)
            }
            guard let token = query["token"] else { return nil }
            guard let originString = query["origin"] else { return .token(token, origin: platformOrigin) }
            guard let origin = URL(string: originString).flatMap(originOnly), isTrusted(origin) else { return nil }
            return .token(token, origin: origin)
        }

        // https://<platform>/app/setup/<token>, only on stromkreis.net.
        guard let origin = originOnly(url), isTrusted(origin) else { return nil }
        let path = components.path
        guard path.lowercased().hasPrefix(setupPathPrefix) else { return nil }
        if let token = query["token"] {
            return .token(token, origin: origin)
        }
        let rest = path.dropFirst(setupPathPrefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !rest.isEmpty, !rest.contains("/") {
            return .token(String(rest), origin: origin)
        }
        if let fragment = components.fragment, !fragment.isEmpty {
            return .token(fragment, origin: origin)
        }
        return nil
    }

    private static func originOnly(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    private static func credentials(from query: [String: String]) -> StromkreisCloudCredentials? {
        guard let username = query["username"], let password = query["password"] else { return nil }
        let cloudUrl = query["cloudUrl"] ?? defaultCloudURL
        guard isTrusted(cloudUrl) else { return nil }
        return StromkreisCloudCredentials(
            cloudUrl: cloudUrl,
            username: username,
            password: password,
            siteName: query["siteName"]
        )
    }

    private static func parseJSON(_ data: Data) -> StromkreisCloudCredentials? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let username = object["username"] as? String, !username.isEmpty,
              let password = object["password"] as? String, !password.isEmpty else { return nil }
        let cloudUrl = (object["cloudUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultCloudURL
        guard isTrusted(cloudUrl) else { return nil }
        return StromkreisCloudCredentials(
            cloudUrl: cloudUrl,
            username: username,
            password: password,
            siteName: object["siteName"] as? String
        )
    }

    // MARK: Redeeming

    /// Resolves a setup link to credentials, contacting the platform when the link carries a token.
    public static func resolve(_ link: StromkreisSetupLink, session: URLSession = .shared) async throws -> StromkreisCloudCredentials {
        switch link {
        case let .credentials(creds):
            creds
        case let .token(token, origin):
            try await redeem(token: token, origin: origin, session: session)
        }
    }

    public static func redeem(token: String, origin: URL, session: URLSession = .shared) async throws -> StromkreisCloudCredentials {
        var request = URLRequest(url: origin.appendingPathComponent(redeemPath))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(["token": token])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Logger.preferences.error("Stromkreis setup: redeem failed: \(error.localizedDescription)")
            throw StromkreisSetupError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw StromkreisSetupError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            Logger.preferences.error("Stromkreis setup: redeem rejected with HTTP \(http.statusCode)")
            throw StromkreisSetupError.tokenRejected(status: http.statusCode, message: message)
        }
        guard let creds = parseJSON(data) else { throw StromkreisSetupError.invalidResponse }
        return creds
    }

    // MARK: Applying

    /// Writes the credentials into the active home's remote (Stromkreis Cloud) connection.
    /// Returns whether the connection actually changed, so callers can skip a disruptive
    /// web view reload when re-redeeming a link for an already-active account.
    @MainActor
    @discardableResult
    public static func apply(_ creds: StromkreisCloudCredentials) -> Bool {
        var connectionChanged = false
        Preferences.shared.modifyActiveHome { home in
            let newConfig = ConnectionConfiguration(
                url: creds.cloudUrl,
                username: creds.username,
                password: creds.password,
                alwaysSendBasicAuth: false,
                supportsNotifications: true,
                priority: 1
            )
            connectionChanged = newConfig != home.remoteConnectionConfig
            home.remoteConnectionConfig = newConfig
            if let name = creds.siteName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                home.homeName = name
            } else if home.homeName == "Home#1" {
                home.homeName = "Stromkreis"
            }
            home.defaultView = "web"
        }
        Logger.preferences.info("Stromkreis setup: cloud connection configured for \(creds.username, privacy: .private)")
        return connectionChanged
    }

    /// True when the given home has a usable Stromkreis Cloud login.
    @MainActor
    public static func isConfigured(_ home: HomePreferences) -> Bool {
        !home.remoteConnectionConfig.url.isEmpty && !home.remoteConnectionConfig.username.isEmpty && !home.remoteConnectionConfig.password.isEmpty
    }

    /// True when the active home has a usable Stromkreis Cloud login.
    @MainActor
    public static var isActiveHomeConfigured: Bool {
        isConfigured(Preferences.shared.currentHomePreferences)
    }
}
