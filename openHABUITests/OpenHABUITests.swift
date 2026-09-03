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
import XCTest

/// Store screenshots (fastlane snapshot). The app has a single surface — the Main UI — so
/// the only shot is the Main UI itself once it has loaded.
class OpenHABUITests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        let app = await XCUIApplication()
        await MainActor.run {
            app.launchEnvironment = ["UITest": "1"]
        }
        continueAfterFailure = false
        await setupSnapshot(app)
        await app.launch()
    }

    @MainActor
    func testShots() {
        let app = XCUIApplication()
        app.activate()
        XCTAssertTrue(app.otherElements["MainMenuBar"].waitForExistence(timeout: 10))
        sleep(10)
        snapshot("0_MainUI")
    }
}
