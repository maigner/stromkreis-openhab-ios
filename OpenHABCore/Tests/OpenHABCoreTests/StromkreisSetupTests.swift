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

struct StromkreisSetupTests {
    @Test func universalLinkWithPathToken() {
        let link = StromkreisSetup.parse("https://stromkreis.net/app/setup/AbC123-xyz")
        #expect(link == .token("AbC123-xyz", origin: URL(string: "https://stromkreis.net")!))
    }

    @Test func universalLinkWithQueryToken() {
        let link = StromkreisSetup.parse(URL(string: "https://www.stromkreis.net/app/setup?token=t0k3n&x=1")!)
        #expect(link == .token("t0k3n", origin: URL(string: "https://www.stromkreis.net")!))
    }

    @Test func selfHostedPlatformKeepsOrigin() {
        let link = StromkreisSetup.parse("https://platform.example.org:8443/app/setup/tok")
        #expect(link == .token("tok", origin: URL(string: "https://platform.example.org:8443")!))
    }

    @Test func customSchemeToken() {
        let link = StromkreisSetup.parse("stromkreis://setup?token=abc")
        #expect(link == .token("abc", origin: StromkreisSetup.platformOrigin))
        let custom = StromkreisSetup.parse("stromkreis://setup?token=abc&origin=https://dev.stromkreis.net/foo")
        #expect(custom == .token("abc", origin: URL(string: "https://dev.stromkreis.net")!))
    }

    @Test func customSchemeInlineCredentials() {
        let link = StromkreisSetup.parse("stromkreis://setup?username=anlage-7@stromkreis.net&password=abcdefghi123&siteName=Haus%207")
        #expect(link == .credentials(StromkreisCloudCredentials(username: "anlage-7@stromkreis.net", password: "abcdefghi123", siteName: "Haus 7")))
    }

    @Test func jsonInlineCredentials() {
        let json = #"{"v":1,"cloudUrl":"https://hac.example.net","username":"u","password":"p"}"#
        let link = StromkreisSetup.parse(json)
        #expect(link == .credentials(StromkreisCloudCredentials(cloudUrl: "https://hac.example.net", username: "u", password: "p")))
    }

    @Test func rejectsUnrelatedPayloads() {
        #expect(StromkreisSetup.parse("https://stromkreis.net/") == nil)
        #expect(StromkreisSetup.parse("https://stromkreis.net/app/setup/") == nil)
        #expect(StromkreisSetup.parse("openhab://command:Item:ON") == nil)
        #expect(StromkreisSetup.parse("stromkreis://other?token=x") == nil)
        #expect(StromkreisSetup.parse("{\"username\":\"u\"}") == nil)
        #expect(StromkreisSetup.parse("hello world") == nil)
    }
}
