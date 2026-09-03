# Stromkreis iOS Development Guide

## Build/Test Commands
- Build: `xcodebuild -workspace openHAB.xcworkspace -scheme openHAB`
- Test all: `fastlane unittests` or `xcodebuild test -workspace openHAB.xcworkspace -scheme openHABTestsSwift -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Core package tests: `xcodebuild test -workspace openHAB.xcworkspace -scheme openHABTestsSwift -testPlan openHABTests -only-testing:OpenHABCoreTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Single test: `xcodebuild test -workspace openHAB.xcworkspace -scheme openHABTestsSwift -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:openHABTestsSwift/TestClassName/testMethodName`
- If the exact simulator is unavailable, switch to an available iPhone simulator
- Beta build: `fastlane beta`
- UI tests: `xcodebuild test -workspace openHAB.xcworkspace -scheme openHABUITests`

## Architecture
The app shows exactly one surface: the member's openHAB **Main UI** in a `WKWebView`. Everything else from the upstream openHAB client (sitemap renderer, settings, multiple homes, watch/widget/CarPlay/Siri targets, push notifications, REST client, Firebase) has been removed on purpose — do not reintroduce it.

- **Main app**: openHAB/ — SwiftUI iOS app targeting iOS 18+
  - `OpenHABApp.swift` / `AppDelegate.swift`: entry point; handles `stromkreis://` and universal setup links
  - `UI/OpenHABRootView.swift`: web view host, native mirror of the Main UI navigation bar, connecting placeholder, certificate alerts
  - `UI/OpenHABWebView*.swift`, `UI/WebViewURLHelper.swift`, `UI/Util/URL+WebViewPath.swift`: the Main UI web view
  - `UI/Onboarding/`: QR-code / setup-link onboarding (see docs/stromkreis-onboarding.md)
  - `UI/NetworkConnectionService.swift`: starts connection tracking, surfaces TLS certificate prompts
- **Core library**: OpenHABCore/ — Swift package: connection tracking (`NetworkTracker`, `ServerProbe`), preferences and Keychain credentials, TLS/certificate handling, `HTTPClient`, ETag checks, `StromkreisSetup`
- **Tests**: openHABTestsSwift/ (Swift Testing) and OpenHABCore/Tests; openHABUITests/ (UI automation of the web view layout)
- **Dependencies**: SFSafeSymbols, swift-timeout. Deliberately no Google/Firebase, no analytics or crash-reporting SDKs, no image or OpenAPI libraries.

## Code Style
- Swift 6
- SwiftUI for new views
- Naming: PascalCase classes, camelCase properties/methods, OpenHAB prefix for core types
- Use SFSafeSymbols for SF Symbols
- Avoid force unwrapping, prefer optionals
- Error handling: Result types in OpenHABCore, SwiftUI alerts in the app
- Avoid trailing closure syntax when passing multiple closures (use parentheses for all closures to prevent multiple_closures_with_trailing_closure warnings)
- Respect "BuildTools/.swiftformat"  and "BuildTools/.swiftlint.yml"
- Always use Swift Regex with Swift 6 syntax
- Prefer `guard` for early exits over `if/else if` chains — when a branch returns, use `guard`/early return to flatten nesting
- Move logic to the type that owns the data — methods that operate on a type's internals belong on that type, not in the caller
- Drop argument labels for parameters already implied by the function name — use `_` for positional parameters whose meaning is obvious from the function name, keep labels only for semantically distinct parameters
- Prefer direct calls to shared helpers over thin wrapper closures that just forward arguments

## Rules for writing tests

- Always write tests with Swift Testing
- Add a parameter with a default value (e.g. `networkTracker: NetworkTracker = .shared`) to make functions testable without coupling them to singletons
- **Always write UI tests** for any new or modified UI surface. See **[docs/UI_TESTING_GUIDE.md](docs/UI_TESTING_GUIDE.md)** for the full guide, including how to register new test files, inject test state, write layout assertions, and pitfalls to avoid.

## Verification cycle

After every set of code changes, run a full verification cycle before committing. See **[docs/SIMULATOR_VERIFICATION.md](docs/SIMULATOR_VERIFICATION.md)** for the step-by-step process and full MCP tool reference.

To replicate the MCP server setup, see **[docs/MCP_SETUP.md](docs/MCP_SETUP.md)**.

## git
- Always use git commit with -s (signed-off-by)
- If using XcodeBuildMCP, use the installed XcodeBuildMCP skill before calling XcodeBuildMCP tools.
