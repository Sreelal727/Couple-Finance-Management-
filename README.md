# Duo Finance

A personal finance app for two people who live together, built so that **no data ever leaves your phones**.

- What you log stays on your phone. What your partner logs stays on theirs.
- When both phones are on the same Wi‑Fi (or one phone's hotspot), they sync **directly with each other**. No server, no account, no cloud.
- Every entry records who paid, who logged it, and when, so nothing gets mixed up.

Built with Flutter for Android.

## Features

| Area | What you get |
|---|---|
| Logging | Add expenses and income in two taps. Title autocomplete, category chips, date/time, receipt photo or screenshot. |
| Quick add | One‑tap chips on the home screen for things you pay for daily (auto ₹40, tea ₹15). Undo from the snackbar. |
| SMS capture | Bank and UPI debit/credit alerts are parsed on the phone and turned into a notification. Tap it, type the purpose, done. Handles SBI, HDFC, ICICI, Axis, Kotak, Federal, SIB, Paytm and most others. OTPs, requests, failed and future debits are ignored. |
| Share to app | Share a UPI screenshot (or copied confirmation text) from any app straight into Duo Finance; the amount and payee are prefilled and the image is attached. |
| Split & settle | Mark an expense as shared, split 50/50, "partner owes all", or a custom share. The home screen always shows who owes whom. Record settlements when you square up. |
| Budgets | Overall and per‑category monthly budgets with progress bars and over‑budget warnings. |
| Reports | Monthly spent / income / saved, spend per person, category donut, 6‑month trend, top spends, CSV export. |
| Savings goals | Shared goals with a target and deadline; contributions tracked per person. |
| App lock | 4–6 digit PIN, optional fingerprint/face, auto‑lock after leaving the app. |
| Sync activity | A log of every sync: when, with whom, how many entries and photos moved, and any errors. |
| Backup | Export everything to an encrypted file (save it to Drive, email it to yourself). Restore merges it back. |

## How sync works

Each phone keeps a full copy of both people's data in a local SQLite database.

1. **Identity.** Every record carries the author, the device that last wrote it, that device's write sequence number, an `updated_at` timestamp and a tombstone flag for deletes.
2. **Discovery.** While the app is open, each phone broadcasts a small UDP beacon on the LAN every two seconds. Hearing a beacon tells the other phone your IP and port. Works on home Wi‑Fi and on a phone hotspot. No mDNS plugin, no configuration.
3. **Pairing.** One phone shows a QR code containing a random 256‑bit secret; the other scans it. All sync traffic is compressed and sealed with AES‑256‑GCM using a key derived from that secret. Someone else on the same Wi‑Fi cannot read or forge your data.
4. **Exchange.** The phone that initiates asks the other for its "seen vector" (highest sequence number it has from each device), sends only the rows the other lacks, and receives the rows it lacks in return. Receipt photos are fetched afterwards by id and verified by SHA‑256.
5. **Merge.** Newest `updated_at` wins; ties are broken by device id so both phones converge on the same answer. Deletes are tombstones, so they propagate.
6. **Auto‑sync.** With auto‑sync on, a paired phone that is seen on the network is synced immediately (throttled to once every 45 s).

### Without shared Wi‑Fi

- **Hotspot.** Turn on the hotspot on one phone and connect the other to it. That's a network too; the normal sync works and no mobile data is consumed.
- **Sync file.** Sync › *Create sync file* packs everything the partner hasn't seen into one encrypted `.duosync` file. Send it by Bluetooth, Quick Share, WhatsApp or cable; the other phone opens it with Duo Finance (share it to the app, or Sync › *Open sync file*). Same merge rules, so mixing methods is safe.

### Data model

Synced tables: `members`, `categories`, `transactions`, `settlements`, `budgets`, `goals`, `goal_contributions`, `quick_adds`, `attachments`.
Local‑only tables: `sms_inbox`, `peers`, `sync_log`, `seen_vector`, `meta`.

Amounts are stored as integer paise.

## Project layout

```
lib/
  core/        money formatting, dates, ids, theme
  data/        SQLite schema, models, repository (all reads/writes + merge logic)
  sync/        crypto, UDP discovery, HTTP server, client, offline bundle, service
  sms/         bank SMS parser, notifications, capture service (foreground + background)
  features/    one folder per screen: home, transactions, reports, goals, budgets,
               categories, settle, sms_inbox, sync, settings, lock, onboarding, quick_adds
test/
  sms_parser_test.dart   real bank SMS formats, debit/credit/ignore cases
  sync_test.dart         two simulated phones: LAN sync, deletes, balance, attachments,
                         wrong key, offline bundle round trip
  app_smoke_test.dart    onboarding → add expense → every tab
```

## Building

### On GitHub (no local setup)

Every push runs the **Build APK** workflow (`.github/workflows/build-apk.yml`): it analyzes, tests and builds a release APK, and attaches it to the run as an artifact.

To get an APK you can download straight onto a phone, run the workflow by hand: **Actions › Build APK › Run workflow**. That also publishes a GitHub **Release** (tagged `build-N`) with the `.apk` attached. Pushing a tag like `v1.0.0` does the same, as a full release.

By default the release APK is signed with the runner's throw-away debug key, so a newer build will not install over an older one; uninstall first. To make updates install in place, sign every build with the same key by adding these repository secrets (Settings › Secrets and variables › Actions):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | key alias |
| `ANDROID_KEY_PASSWORD` | key password |

Create the keystore once and keep it somewhere safe:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias duo
```

### Locally

Requirements: Flutter 3.47+ (Dart 3.13+), Android SDK with platform 37, JDK 17.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`. Install it on **both** phones.

Local builds are signed with the debug key unless `android/key.properties` exists (see the comment at the top of `android/app/build.gradle.kts`). Both phones must be installed from builds signed with the same key for in-place updates to work.

## First run

1. Enter your name and pick a colour on each phone.
2. On one phone: Settings › Sync & pairing › **Show pairing code**. On the other: **Scan partner's code**. That's it, they sync right away if they're on the same network.
3. Optional: Settings › **SMS capture** (grant SMS + notification permission). The last 30 days of bank alerts are scanned into *Detected transactions*.
4. Optional: Settings › **App lock**.

## Permissions

| Permission | Why |
|---|---|
| Internet / network state | The on‑device sync server and LAN discovery. Nothing is sent to the internet. |
| Receive / read SMS | Only if you turn SMS capture on. Parsed locally; SMS text never leaves the phone. |
| Camera | Scanning the pairing QR code and photographing receipts. |
| Notifications | The "tap to add" notification for detected transactions. |
| Biometrics | App lock. |

## Limitations worth knowing

- Sync needs the app open (or recently backgrounded) on both phones. Android eventually stops background sockets; there's no push server to wake the other side.
- SMS capture depends on the bank's message format. Unrecognised formats are silently skipped; use the *Detected transactions* screen to see what was caught.
- The app trusts both phones' clocks for conflict resolution. If the clocks differ by more than 10 minutes, sync refuses to run until they're fixed.
