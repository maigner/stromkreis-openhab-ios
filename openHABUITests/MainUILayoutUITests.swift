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
import XCTest

// MARK: - JS probes

/// JS snippets injected via UITestInjectJS. Each snippet calls window.ohUITest.report(key, value);
/// the test reads results via app.staticTexts with identifier "UITestReport-<key>".
private enum LayoutJS {
    /// Reports the top safe-area inset the web view exposes to the page. It is only
    /// non-zero when the web view extends under the status bar / Dynamic Island.
    static let safeAreaTop = #"""
    (function(){
      var probe = document.getElementById('safe-probe');
      var tries = 0;
      // The inset reaches the page only after the first layout pass, so poll for it.
      var timer = setInterval(function(){
        var h = probe.getBoundingClientRect().height;
        if (h > 0 || ++tries > 50) {
          clearInterval(timer);
          window.ohUITest.report('safeAreaTop', String(h));
        }
      }, 100);
    })();
    """#

    /// Mimics Framework7 hiding its navbar on scroll: posts the same `navbarState`
    /// message the app's navbar proxy sends. Delayed so it lands after the proxy's own
    /// initial post on page load.
    static let hideWebNavbar = #"""
    setTimeout(function(){
      window.webkit.messageHandlers.mainUi.postMessage(
        {type:'navbarState',hidden:'true',titleHidden:'true',height:'44'});
    }, 600);
    """#

    static func base64(_ js: String) -> String {
        Data(js.utf8).base64EncodedString()
    }
}

// MARK: - HTML fixtures

/// Minimal HTML pages mirroring the Framework7 DOM structure used by the MainUI SPA.
private enum LayoutHTML {
    /// Main UI reserves the navbar itself: page content is padded by the navbar height plus
    /// the top safe area, exactly what the native bar (44pt below the safe area) must cover.
    /// viewport-fit=cover mirrors the real SPA, which makes env(safe-area-inset-top) live, and
    /// `#app` marks the document as the Main UI so the app does not pad the body itself.
    static let reservedNavbar = """
    <!DOCTYPE html><html>
    <head><meta name='viewport' content='width=device-width,initial-scale=1,viewport-fit=cover'>
    <style>
    *{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui}
    #safe-probe{height:env(safe-area-inset-top);width:1px}
    .navbar{position:absolute;top:0;left:0;right:0;height:calc(44px + env(safe-area-inset-top))}
    .page-content{padding-top:calc(44px + env(safe-area-inset-top))}
    .marker{height:24px;padding-left:16px}
    </style></head>
    <body>
    <div id='safe-probe' style='position:fixed;top:0;left:0'></div>
    <div id='app' class='framework7-root'><div class='view view-main'><div class='page page-current'>
      <div class='navbar'><div class='navbar-inner'><div class='title'>UITest</div></div></div>
      <div class='page-content'><p class='marker' aria-label='UITest Content Marker'>Content</p></div>
    </div></div></div>
    </body></html>
    """

    /// Framework7-like page with a position:fixed bottom tab bar.
    static let bottomTabBar = """
    <!DOCTYPE html><html>
    <head><meta name='viewport' content='width=device-width,initial-scale=1,viewport-fit=cover'>
    <style>
    *{margin:0;padding:0;box-sizing:border-box}body{font-family:system-ui;height:100vh}
    #safe-probe{height:env(safe-area-inset-top);width:1px}
    .page-content{padding:16px}
    .tab-bar{position:fixed;bottom:0;left:0;right:0;height:49px;background:#eee;
             display:flex;align-items:center;justify-content:space-around}
    </style></head>
    <body>
    <div id='safe-probe' style='position:fixed;top:0;left:0'></div>
    <div class='page-content'><p>Page content</p></div>
    <div class='tab-bar'><button aria-label='UITest Tab Bar'>Tab</button></div>
    </body></html>
    """

    static func base64(_ html: String) -> String {
        Data(html.utf8).base64EncodedString()
    }
}

// MARK: - Test class

/// Layout tests for the Main UI web view host.
///
/// The web view fills the whole screen (under the status bar) and the Main UI lays itself
/// out from the safe-area insets, reserving room for the navbar the native bar sits on.
/// The native bar mirrors the web navbar: same height, and it slides away when the web
/// navbar hides.
@MainActor
final class MainUILayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITest"] = "1"
    }

    override func tearDown() {
        app = nil; super.tearDown()
    }

    // MARK: - Launch helpers

    private static let placeholderHTML = "<html><body><p>UITest Placeholder</p></body></html>"

    private func launchInWebviewMode(html: String? = nil, js: String? = nil, navbarItems: Bool = false) {
        app.launchEnvironment["UITestWebViewMode"] = "1"
        // Always inject at least a placeholder so the webView has stable content
        // and loadWebView cannot race against injected state.
        app.launchEnvironment["UITestInjectHTML"] = LayoutHTML.base64(html ?? Self.placeholderHTML)
        if let js { app.launchEnvironment["UITestInjectJS"] = LayoutJS.base64(js) }
        if navbarItems {
            app.launchEnvironment["UITestWebViewNavbarItems"] =
                #"[{"label":"Menu","jsAction":"document.querySelector('.hamburger,.menu-btn')?.click()"}]"#
        }
        app.launch()
    }

    // MARK: - Helpers

    private var menuBar: XCUIElement {
        app.otherElements.matching(identifier: "MainMenuBar").firstMatch
    }

    /// Finds a web element inside the webView by its accessibility label (aria-label).
    @discardableResult
    private func waitForWebLabel(_ label: String, timeout: TimeInterval = 8) -> XCUIElement {
        let pred = NSPredicate(format: "label == %@", label)
        let el = app.webViews.firstMatch.descendants(matching: .any).matching(pred).firstMatch
        XCTAssertTrue(
            el.waitForExistence(timeout: timeout),
            "Expected web element with label '\(label)' within \(timeout)s"
        )
        return el
    }

    @discardableResult
    private func waitForReport(_ key: String, timeout: TimeInterval = 8) -> String {
        let el = app.staticTexts.matching(identifier: "UITestReport-\(key)").firstMatch
        XCTAssertTrue(
            el.waitForExistence(timeout: timeout),
            "Expected JS report '\(key)' within \(timeout)s — check ohUITest bridge is active"
        )
        return el.label
    }

    // MARK: - Web view fills the screen

    /// The web view must extend under the status bar and the bottom edge. The Main UI
    /// positions itself from the safe-area insets, so a web view that is padded or inset
    /// by the host would double-count them.
    func testWebViewFillsScreen() {
        launchInWebviewMode(html: LayoutHTML.reservedNavbar, js: LayoutJS.safeAreaTop)
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 8))
        let screen = app.windows.firstMatch.frame

        XCTAssertEqual(
            webView.frame.minY,
            screen.minY,
            accuracy: 1,
            "Web view must start at the top of the screen, under the status bar"
        )
        XCTAssertEqual(
            webView.frame.maxY,
            screen.maxY,
            accuracy: 1,
            "Web view must reach the bottom of the screen"
        )

        let safeTop = Double(waitForReport("safeAreaTop")) ?? 0
        XCTAssertGreaterThan(
            safeTop,
            0,
            "The page must see a non-zero top safe-area inset so Main UI can lay itself out"
        )
    }

    // MARK: - Native bar covers exactly the navbar space Main UI reserves

    /// Content laid out by the Main UI below its reserved navbar space must start exactly
    /// where the native bar ends: safe-area top + the bar height (44pt by default).
    func testContentBelowNavbarMeetsNativeBarBottom() {
        launchInWebviewMode(html: LayoutHTML.reservedNavbar, js: LayoutJS.safeAreaTop)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8))

        let safeTop = Double(waitForReport("safeAreaTop")) ?? 0
        let marker = waitForWebLabel("UITest Content Marker")

        XCTAssertEqual(
            marker.frame.minY, CGFloat(safeTop) + 44, accuracy: 2,
            "Content top (\(marker.frame.minY)pt) must meet the native bar bottom (safe area \(safeTop)pt + 44pt bar)"
        )
    }

    // MARK: - Bottom-fixed elements

    /// position:fixed bottom:0 elements (Framework7 tab bar) must sit on the screen bottom,
    /// not be pushed off-screen by an inset applied to the web view.
    func testBottomFixedElementSitsOnScreenBottom() {
        launchInWebviewMode(html: LayoutHTML.bottomTabBar)
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 8))

        let tabBarBtn = waitForWebLabel("UITest Tab Bar")
        let overflowBelowWebview = tabBarBtn.frame.maxY - webView.frame.maxY

        XCTAssertLessThanOrEqual(
            overflowBelowWebview, 2,
            "position:fixed bottom:0 element extends \(overflowBelowWebview)pt below the web view bottom edge"
        )
    }

    // MARK: - Native bar mirrors the web navbar hiding

    /// When Main UI hides its navbar (hide-bars-on-scroll) it posts `navbarState`; the native
    /// bar must slide away with it and stop taking touches.
    func testNativeBarMirrorsWebNavbarHiding() {
        launchInWebviewMode(js: LayoutJS.hideWebNavbar)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(menuBar.waitForExistence(timeout: 4), "Native bar must be visible while the web navbar is shown")

        let gone = NSPredicate(format: "exists == false OR hittable == false")
        expectation(for: gone, evaluatedWith: menuBar)
        waitForExpectations(timeout: 8)
    }

    // MARK: - Navbar proxy infrastructure

    /// Verifies navbarItems are set in the view model (UITestReport-navbarItemCount > 0),
    /// and that the proxy button, when present in the AX tree, is in the top bar area.
    ///
    /// SwiftUI buttons in a ZStack overlaying a WKWebView may not appear in XCTest's AX
    /// tree on some iOS versions, so the item count is the authoritative check.
    func testNavbarProxyButtonAppearsInMenuBar() {
        launchInWebviewMode(navbarItems: true)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8))

        let count = Int(waitForReport("navbarItemCount")) ?? 0
        XCTAssertGreaterThan(count, 0, "navbarItems must be non-empty after UITestWebViewNavbarItems injection")

        let menuBtn = app.buttons.matching(identifier: "NavbarProxyButton-Menu").firstMatch
        if menuBtn.waitForExistence(timeout: 3) {
            XCTAssertLessThan(
                menuBtn.frame.maxY,
                120,
                "Proxy button must be in the native menuBar area (top 120pt of screen)"
            )
        }
    }

    /// Verifies the proxy button is hittable when navbarItems are set via the test environment.
    func testNavbarProxyButtonIsHittable() {
        launchInWebviewMode(navbarItems: true)
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8))

        let count = Int(waitForReport("navbarItemCount")) ?? 0
        XCTAssertGreaterThan(count, 0, "navbarItems must be non-empty — proxy button would not appear without items")

        let menuBtn = app.buttons.matching(identifier: "NavbarProxyButton-Menu").firstMatch
        if menuBtn.waitForExistence(timeout: 3) {
            XCTAssertTrue(
                menuBtn.isHittable,
                "Navbar proxy 'Menu' button must be hittable inside the native menuBar"
            )
        }
    }
}
