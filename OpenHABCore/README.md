# OpenHABCore

The non-UI core of the Stromkreis iOS app:

- `NetworkTracker` / `MainActorNetworkTracker`: picks the reachable connection (local or Stromkreis Cloud), retries with backoff, and reports rejected credentials
- `ServerProbe`: the single REST call left — a GET of `/rest/` to check reachability and the openHAB version
- `HTTPClient`, `HTTPClientDelegate`, `SessionChallengeHandler`, `ClientCertificateManager`, `ServerCertificateManager`: HTTP with basic auth, TLS trust prompts and client certificates
- `Preferences`, `ConnectionConfiguration`, `CredentialsStore`: per-home settings with credentials in the Keychain
- `StromkreisSetup`: parsing and redeeming Stromkreis setup links / QR codes
- `ETagChecker` / `ETagCache`: change detection for the Main UI web view

The package depends only on [swift-timeout](https://github.com/swhitty/swift-timeout). It imports UIKit, so it
builds for iOS only; run its tests through the Xcode workspace (`openHABTests` test plan).
