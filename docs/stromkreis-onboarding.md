# Stromkreis app onboarding

The app is a thin client for the Stromkreis Cloud (`https://hac.stromkreis.net`): after setup it
opens the member's openHAB MainUI through the cloud. There is no demo mode. Until the active home
has a cloud login (URL + username + password) the app shows the onboarding screen.

## Member flow

1. The Stromkreis admin creates the openHABian SD card for a new member (`/intern` → *Anlage anlegen*
   → *Image bauen*). On first boot the gateway provisions itself and the platform creates the
   member's cloud account (`battery_site.cloud_username` / `cloud_password`).
2. The member installs the Stromkreis app and receives a link to their Stromkreis page that shows a
   **one-time QR code**, or receives the **setup link** directly on the phone.
3. Either:
   - the member scans the QR code with the app (camera; or pastes the link), or
   - the member taps the link on the phone → iOS opens the app (universal link) → the app
     configures the cloud connection automatically.

## Link / QR payload accepted by the app

| Form | Example |
|---|---|
| Universal link (preferred; also the QR content) | `https://stromkreis.net/app/setup/<token>` or `https://stromkreis.net/app/setup?token=<token>` |
| Custom scheme fallback | `stromkreis://setup?token=<token>[&origin=https://stromkreis.net]` |
| Inline credentials (offline QR) | `stromkreis://setup?username=…&password=…[&cloudUrl=…][&siteName=…]` |
| Inline credentials (JSON QR) | `{"v":1,"username":"…","password":"…","cloudUrl":"https://hac.stromkreis.net","siteName":"…"}` |

Any `https` host is accepted for the `/app/setup/…` form (self-hosted platforms); the origin of the
link is used to redeem the token. Parsing lives in `OpenHABCore/Sources/OpenHABCore/Util/StromkreisSetup.swift`.

## Server contract (implemented in the `stromkreis` platform, commit `5523f69`)

Platform side lives in `platform/src/lib/server/app-setup.js`, `platform/src/routes/api/app/setup/v1/`,
`platform/src/routes/app/setup/[token]/` and `platform/src/routes/.well-known/apple-app-site-association/`.

- **Token**: 24 random bytes, base64url (`A–Z a–z 0–9 - _`), only its SHA-256 hash is stored in
  `app_setup_token` (`tenant_id, site_id, token_hash, expires_at, used_at`). Valid **7 days**; creating a
  new code for a site invalidates the old one. Created by the admin on `/intern/anlagen/[id]` (tab
  *App-Einrichtung*, action `app_code_erzeugen`); link and QR are shown exactly once.
- **QR content / link**: `https://stromkreis.net/app/setup/<token>` (from `platformBaseUrl()`).
- **Fallback page** `/app/setup/[token]` (public, checks the token without consuming it): steps for
  members, button *In der App öffnen* → `stromkreis://setup?token=<token>&origin=https://stromkreis.net`,
  and the QR code for the desktop case.
- **Redeem** — unauthenticated, the token is the credential; POST so it never lands in access logs:

```
POST /api/app/setup/v1
Content-Type: application/json

{"token": "<one-time token>"}
```

Success `200` (token is consumed only after the password was decrypted successfully):

```json
{
  "cloudUrl": "https://hac.stromkreis.net",   // CLOUD_BASE_URL of the platform
  "username": "anlage-7@stromkreis.net",      // battery_site.cloud_username
  "password": "kqzrtwmnb482",                 // decrypted battery_site.cloud_password
  "siteName": "Haus Muster"                   // battery_site.name → home name in the app
}
```

Errors carry `{"error": "<German text>"}` which the app shows verbatim:

| Status | Meaning |
|---|---|
| `400` | malformed request / missing token |
| `409` | site has no cloud account yet — token is **not** consumed, retry later with the same code |
| `410` | token unknown, expired or already used |
| `500` | stored password could not be decrypted |

- **Universal links**: `/.well-known/apple-app-site-association` is served as JSON for
  `6U7435AK45.net.stromkreis.app` with `/app/setup/*` and `/app/setup?token=*`. The app declares
  `applinks:stromkreis.net` / `applinks:www.stromkreis.net` and signs with team `6U7435AK45`, so links
  open the app directly once the platform is deployed. `stromkreis://` links work without that.

The app's redeem path is tested against these exact responses in
`OpenHABCore/Tests/OpenHABCoreTests/StromkreisSetupRedeemTests.swift`.

## In-app

- Onboarding UI: `openHAB/UI/Onboarding/` (`OnboardingView`, `QRScannerView`, `OnboardingCoordinator`).
- Re-run setup later: Home settings → *Scan Stromkreis setup code*.
- Credentials are written to the active home's remote connection (Keychain-backed) with
  *Stromkreis Cloud* enabled; the local connection URL defaults to empty so only the cloud is used.
