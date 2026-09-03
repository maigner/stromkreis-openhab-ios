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

import XCTest

// MARK: - Fixtures

private enum InteractionFixture {
    static let toastTitle = "UITest Interaction Alert"
    static let toastMessage = "Motion detected."
    // JSON-encoded action list for UITestToastActions
    static let actionsJSON = #"[{"title":"Open Camera","action":"ui:/overview"}]"#
}

// MARK: - Test class

@MainActor
final class NotificationInteractionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITest"] = "1"
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private var screen: CGRect { app.windows.firstMatch.frame }

    @discardableResult
    private func waitFor(_ text: String, timeout: TimeInterval = 4) -> XCUIElement {
        let el = app.staticTexts[text]
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "Expected '\(text)' to appear within \(timeout)s")
        return el
    }

    private func waitForButton(_ label: String, timeout: TimeInterval = 4) -> XCUIElement {
        let el = app.buttons[label]
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "Expected button '\(label)' to appear within \(timeout)s")
        return el
    }

    private func launchWithToastAndActions() {
        app.launchEnvironment["UITestToastTitle"] = InteractionFixture.toastTitle
        app.launchEnvironment["UITestToastMessage"] = InteractionFixture.toastMessage
        app.launchEnvironment["UITestToastActions"] = InteractionFixture.actionsJSON
        app.launch()
    }

    // MARK: - Toast action button tests

    func testToastActionButtonAppears() {
        launchWithToastAndActions()

        let title = waitFor(InteractionFixture.toastTitle)
        let button = waitForButton("Open Camera")
        XCTAssertTrue(button.isHittable, "Action button must be on-screen and hittable")

        // Layout assertions — loose thresholds so minor spacing changes don't break them.
        let s = screen
        // Toast banner must sit in the lower portion of the screen (not at screen centre).
        XCTAssertGreaterThan(title.frame.minY, s.height * 0.5,
                             "Toast title must appear in the lower half of the screen")
        // Action button must be on the right side (action control is right-aligned).
        XCTAssertGreaterThan(button.frame.minX, s.width * 0.45,
                             "Action button must be on the right side of the banner")
        // Action button and title must share roughly the same vertical centre (horizontal layout).
        XCTAssertLessThan(abs(button.frame.midY - title.frame.midY), 30,
                          "Action button and title must be at similar vertical positions")
    }

    func testToastActionButtonDismissesToast() {
        launchWithToastAndActions()

        waitFor(InteractionFixture.toastTitle)
        waitForButton("Open Camera").tap()

        let gone = NSPredicate(format: "exists == false")
        let expectation = expectation(for: gone, evaluatedWith: app.staticTexts[InteractionFixture.toastTitle])
        wait(for: [expectation], timeout: 2)
    }

    func testToastBodyTapWithActionsStillDismisses() {
        launchWithToastAndActions()

        let title = waitFor(InteractionFixture.toastTitle)
        title.tap()

        let gone = NSPredicate(format: "exists == false")
        let expectation = expectation(for: gone, evaluatedWith: app.staticTexts[InteractionFixture.toastTitle])
        wait(for: [expectation], timeout: 2)
    }
}
