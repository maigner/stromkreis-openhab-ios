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

## Server contract (to implement in the `stromkreis` platform)

Token redemption — unauthenticated, the token is the credential:

```
POST /api/app/setup/v1
Content-Type: application/json

{"token": "<one-time token>"}
```

Success `200`:

```json
{
  "cloudUrl": "https://hac.stromkreis.net",   // optional, defaults to hac.stromkreis.net
  "username": "anlage-7@stromkreis.net",      // battery_site.cloud_username
  "password": "abcdefghi123",                 // decrypted battery_site.cloud_password
  "siteName": "Haus Mustermann"               // optional, becomes the home name in the app
}
```

Failure: any non-2xx; optional `{"error": "human readable reason"}` is shown verbatim. The app treats
401/403/404/410 without a message as "invalid or already used".

Suggested implementation on the platform (mirrors the existing `login_token` pattern):

- table `app_setup_token (id, tenant_id, site_id, token_hash, expires_at, used_at, created_at)`;
  create from the `/intern/anlagen/[id]` page ("App-Einrichtungscode erzeugen"), e.g. 7 days validity;
- page `/app/setup/[token]` that renders the QR code (content = the page's own URL) plus an
  "In der App öffnen" button, and explains the steps for members without the app installed;
- `POST /api/app/setup/v1` consuming the token once (`used_at`), returning the JSON above;
- `static/.well-known/apple-app-site-association` served as `application/json` without redirect:

```json
{"applinks":{"details":[{"appIDs":["<TEAMID>.net.stromkreis.app"],"components":[{"/":"/app/setup/*"},{"/":"/app/setup","?":{"token":"*"}}]}]}}
```

The app declares `applinks:stromkreis.net` and `applinks:www.stromkreis.net` in its entitlements;
universal links only work once the AASA file is live and the app is signed with the matching team.
`stromkreis://` links work immediately without server support.

## In-app

- Onboarding UI: `openHAB/UI/Onboarding/` (`OnboardingView`, `QRScannerView`, `OnboardingCoordinator`).
- Re-run setup later: Home settings → *Scan Stromkreis setup code*.
- Credentials are written to the active home's remote connection (Keychain-backed) with
  *Stromkreis Cloud* enabled; the local connection URL defaults to empty so only the cloud is used.
