// Copyright (c) 2026 Stromkreis contributors
//
// This program and the accompanying materials are made available under the
// terms of the Eclipse Public License 2.0 which is available at
// http://www.eclipse.org/legal/epl-2.0
//
// SPDX-License-Identifier: EPL-2.0

import Foundation
@testable import OpenHABCore
import Testing

/// Replays the exact responses of the Stromkreis platform's `POST /api/app/setup/v1`
/// (platform/src/routes/api/app/setup/v1/+server.js) so the app's redeem path is checked
/// against the real server contract.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct StromkreisSetupRedeemTests {
    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func requestBody(_ request: URLRequest) -> [String: String] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: 4096)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: String]) ?? [:]
    }

    @Test func successReturnsCredentialsFromServer() async throws {
        let token = "Xy_3-abcDEF0123456789ghijklmnop"
        nonisolated(unsafe) var seen: (method: String?, url: String?, body: [String: String])?
        StubURLProtocol.handler = { request in
            seen = (request.httpMethod, request.url?.absoluteString, Self.requestBody(request))
            let json = #"{"cloudUrl":"https://hac.stromkreis.net","username":"anlage-7@stromkreis.net","password":"kqzrtwmnb482","siteName":"Haus Muster"}"#
            return (200, Data(json.utf8))
        }
        let link = try #require(StromkreisSetup.parse("https://stromkreis.net/app/setup/\(token)"))
        let creds = try await StromkreisSetup.resolve(link, session: Self.session())

        #expect(seen?.method == "POST")
        #expect(seen?.url == "https://stromkreis.net/api/app/setup/v1")
        #expect(seen?.body == ["token": token])
        #expect(creds == StromkreisCloudCredentials(cloudUrl: "https://hac.stromkreis.net", username: "anlage-7@stromkreis.net", password: "kqzrtwmnb482", siteName: "Haus Muster"))
    }

    @Test func fallbackPageAppLinkRedeemsAtGivenOrigin() async throws {
        // The /app/setup/[token] page's "In der App öffnen" button.
        StubURLProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://stromkreis.net/api/app/setup/v1")
            return (200, Data(#"{"username":"u","password":"p","siteName":"S"}"#.utf8))
        }
        let link = try #require(StromkreisSetup.parse("stromkreis://setup?token=abc%2Ddef&origin=https%3A%2F%2Fstromkreis.net"))
        #expect(link == .token("abc-def", origin: URL(string: "https://stromkreis.net")!))
        let creds = try await StromkreisSetup.resolve(link, session: Self.session())
        #expect(creds.cloudUrl == StromkreisSetup.defaultCloudURL)
        #expect(creds.siteName == "S")
    }

    @Test func usedTokenSurfacesServerMessage() async {
        StubURLProtocol.handler = { _ in
            (410, Data(#"{"error":"Der Einrichtungscode ist ungültig oder wurde bereits verwendet."}"#.utf8))
        }
        await #expect(throws: StromkreisSetupError.tokenRejected(status: 410, message: "Der Einrichtungscode ist ungültig oder wurde bereits verwendet.")) {
            try await StromkreisSetup.redeem(token: "t", origin: StromkreisSetup.platformOrigin, session: Self.session())
        }
    }

    @Test func pendingCloudAccountSurfacesServerMessage() async {
        StubURLProtocol.handler = { _ in
            (409, Data(#"{"error":"Für diese Anlage ist noch kein Cloud-Konto eingerichtet. Bitte später erneut versuchen."}"#.utf8))
        }
        await #expect(throws: StromkreisSetupError.tokenRejected(status: 409, message: "Für diese Anlage ist noch kein Cloud-Konto eingerichtet. Bitte später erneut versuchen.")) {
            try await StromkreisSetup.redeem(token: "t", origin: StromkreisSetup.platformOrigin, session: Self.session())
        }
    }

    @Test func malformedSuccessBodyIsInvalidResponse() async {
        StubURLProtocol.handler = { _ in (200, Data(#"{"username":"only"}"#.utf8)) }
        await #expect(throws: StromkreisSetupError.invalidResponse) {
            try await StromkreisSetup.redeem(token: "t", origin: StromkreisSetup.platformOrigin, session: Self.session())
        }
    }
}
