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
import os

// MARK: - URLSessionDelegate for Basic Auth

public final class HTTPClientDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let connectionConfiguration: ConnectionConfiguration

    init(with connectionConfiguration: ConnectionConfiguration) {
        self.connectionConfiguration = connectionConfiguration
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await urlSessionInternal(session, task: nil, didReceive: challenge)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await urlSessionInternal(session, task: task, didReceive: challenge)
    }

    private func urlSessionInternal(_ session: URLSession, task: URLSessionTask?, didReceive challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let authenticationMethod = challenge.protectionSpace.authenticationMethod
        Logger.httpClientDelegate.debug("URLAuthenticationChallenge: \(authenticationMethod)")

        if challenge.previousFailureCount > 0 {
            // A repeated basic-auth challenge means the server rejected the stored
            // credentials we supplied on the first round (e.g. the Stromkreis Cloud
            // password changed). Cancelling kills the task with a transport error, so
            // no 401 response ever surfaces to callers — signal the rejection here,
            // where it is unambiguous, so the app can re-run its QR/link setup.
            if authenticationMethod.isAny(of: NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodDefault),
               !connectionConfiguration.username.isEmpty {
                Logger.httpClientDelegate.warning("Stored credentials rejected by host \(challenge.protectionSpace.host, privacy: .public)")
                NotificationCenter.default.post(name: .stromkreisCredentialsRejected, object: nil)
            }
            return (.cancelAuthenticationChallenge, nil)
        }
        switch authenticationMethod {
        case NSURLAuthenticationMethodDefault, NSURLAuthenticationMethodHTTPBasic:
            return await handleBasicAuth(challenge: challenge)
        default:
            return (.performDefaultHandling, nil)
        }
    }

    /// The Stromkreis server can answer with a redirect to its own `http://` address (TLS is terminated
    /// in front of it). ATS rightly refuses that, so keep the redirect on `https`.
    // swiftlint:disable:next async_without_await
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        guard let url = request.url, let upgraded = StromkreisSetup.upgradedToHTTPS(url) else { return request }
        Logger.httpClientDelegate.info("Upgrading redirect to https: \(upgraded.absoluteString, privacy: .public)")
        var upgradedRequest = request
        upgradedRequest.url = upgraded
        return upgradedRequest
    }

    // swiftlint:disable:next async_without_await
    private func handleBasicAuth(challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let credential = URLCredential(user: connectionConfiguration.username, password: connectionConfiguration.password, persistence: .forSession)
        return (.useCredential, credential)
    }
}
