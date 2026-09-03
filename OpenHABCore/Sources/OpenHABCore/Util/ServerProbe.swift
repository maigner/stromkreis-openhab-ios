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

/// Errors raised while probing an openHAB server's REST root.
public enum ServerProbeError: Error, Sendable {
    /// The server answered 401: the stored credentials were rejected.
    case unauthorized
    /// Any other unexpected HTTP status.
    case httpStatus(Int)
    /// The root document could not be parsed.
    case invalidResponse
}

/// Minimal reachability check for an openHAB server: fetches `/rest/` and reports
/// the API version. This is all the MainUI-only app needs from the REST API.
public protocol ServerProbe: AnyObject, Sendable {
    func getRootVersion() async throws -> Int
}

/// `ServerProbe` implemented with a plain `URLSession` GET of `<url>/rest/`, using the
/// same TLS/certificate handling and basic-auth rules as every other request.
public final class HTTPServerProbe: ServerProbe {
    private let httpClient: HTTPClient
    private let rootURL: URL?

    public init(connectionConfiguration: ConnectionConfiguration) {
        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = 10.0
        sessionConfiguration.timeoutIntervalForResource = 10.0
        httpClient = HTTPClient(
            connectionConfiguration: connectionConfiguration,
            sessionConfiguration: sessionConfiguration,
            delegate: HTTPClientDelegate(with: connectionConfiguration)
        )
        rootURL = URL(string: connectionConfiguration.url)?.appendingPathComponent("rest")
    }

    public func getRootVersion() async throws -> Int {
        guard let rootURL else { throw HTTPClientError.baseURLIsNil }
        let data: Data
        do {
            (data, _) = try await httpClient.doRequest(baseURL: rootURL, timeout: 10.0, type: .data)
        } catch HTTPClientError.httpError(let statusCode) {
            throw statusCode == 401 ? ServerProbeError.unauthorized : ServerProbeError.httpStatus(statusCode)
        }
        guard let root = try? JSONDecoder().decode(RootDocument.self, from: data),
              let version = root.majorVersion, version > 1 else {
            throw NetworkTrackerError.invalidServerVersion
        }
        return version
    }

    private struct RootDocument: Decodable {
        let version: String?

        var majorVersion: Int? {
            guard let version else { return nil }
            return Int(version.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".").first ?? "")
        }
    }
}

public func basicAuthHeader(username: String, password: String) -> String {
    let credential = Data("\(username):\(password)".utf8).base64EncodedString()
    return "Basic \(credential)"
}
