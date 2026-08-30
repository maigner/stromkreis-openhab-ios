// Copyright (c) 2026 Stromkreis contributors
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
            if let token = query["token"] {
                let origin = query["origin"].flatMap(URL.init(string:)).flatMap(originOnly) ?? platformOrigin
                return .token(token, origin: origin)
            }
            return nil
        }

        // https://<platform>/app/setup/<token>. Only stromkreis.net arrives as a universal link,
        // but a scanned QR code may point at a self-hosted platform, so any host is accepted.
        guard let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.host != nil,
              let origin = originOnly(url) else { return nil }
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
        return StromkreisCloudCredentials(
            cloudUrl: query["cloudUrl"] ?? defaultCloudURL,
            username: username,
            password: password,
            siteName: query["siteName"]
        )
    }

    private static func parseJSON(_ data: Data) -> StromkreisCloudCredentials? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let username = object["username"] as? String, !username.isEmpty,
              let password = object["password"] as? String, !password.isEmpty else { return nil }
        return StromkreisCloudCredentials(
            cloudUrl: (object["cloudUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? defaultCloudURL,
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
            return creds
        case let .token(token, origin):
            return try await redeem(token: token, origin: origin, session: session)
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
    @MainActor
    public static func apply(_ creds: StromkreisCloudCredentials) {
        Preferences.shared.modifyActiveHome { home in
            home.remoteConnectionConfig = ConnectionConfiguration(
                url: creds.cloudUrl,
                username: creds.username,
                password: creds.password,
                alwaysSendBasicAuth: false,
                ignoreSSL: false,
                supportsNotifications: true,
                priority: 1
            )
            if let name = creds.siteName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                home.homeName = name
            } else if home.homeName == "Home#1" {
                home.homeName = "Stromkreis"
            }
            home.defaultView = "web"
        }
        Logger.preferences.info("Stromkreis setup: cloud connection configured for \(creds.username, privacy: .private)")
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
