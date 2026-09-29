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

private func logChallengeDecision(label: String, _ challenge: URLAuthenticationChallenge, _ disposition: URLSession.AuthChallengeDisposition, reason: String) {
    let host = challenge.protectionSpace.host
    let method = challenge.protectionSpace.authenticationMethod
    Logger.sessionChallenge.info("\(label, privacy: .public) decision host=\(host, privacy: .public), method=\(method, privacy: .public), disposition=\(String(describing: disposition), privacy: .public), reason=\(reason, privacy: .public)")
}

private func logSessionTaskChallengeDecision(_ challenge: URLAuthenticationChallenge, _ disposition: URLSession.AuthChallengeDisposition, reason: String) {
    logChallengeDecision(label: "Session task challenge", challenge, disposition, reason: reason)
}

private func credentialForMatchedHost(_ challenge: URLAuthenticationChallenge,
                                      networkTracker: NetworkTracker,
                                      log: (URLAuthenticationChallenge, URLSession.AuthChallengeDisposition, String) -> Void) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    let host = challenge.protectionSpace.host
    guard let matchedConfiguration = await networkTracker.connectionConfiguration(forHost: host) else {
        Logger.sessionChallenge.error("No host match for challenge host=\(host, privacy: .public)")
        let decision: URLSession.AuthChallengeDisposition = .performDefaultHandling
        log(challenge, decision, "no-host-match")
        return (decision, nil)
    }

    let credential = URLCredential(user: matchedConfiguration.username, password: matchedConfiguration.password, persistence: .forSession)
    let decision: URLSession.AuthChallengeDisposition = .useCredential
    log(challenge, decision, "matched-host")
    return (decision, credential)
}

@MainActor
public func onReceiveSessionTaskChallenge(with challenge: URLAuthenticationChallenge, networkTracker: NetworkTracker = .shared) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
    let host = challenge.protectionSpace.host
    Logger.sessionChallenge.info("onReceiveSessionTaskChallenge host=\(host, privacy: .public), method=\(challenge.protectionSpace.authenticationMethod, privacy: .public)")

    guard challenge.previousFailureCount == 0 else {
        let decision: URLSession.AuthChallengeDisposition = .cancelAuthenticationChallenge
        logSessionTaskChallengeDecision(challenge, decision, reason: "previous-failure")
        return (decision, nil)
    }

    guard challenge.protectionSpace.authenticationMethod.isAny(of: NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodDefault) else {
        let decision: URLSession.AuthChallengeDisposition = .performDefaultHandling
        logSessionTaskChallengeDecision(challenge, decision, reason: "unsupported-auth-method")
        return (decision, nil)
    }

    return await credentialForMatchedHost(challenge, networkTracker: networkTracker, log: logSessionTaskChallengeDecision)
}
