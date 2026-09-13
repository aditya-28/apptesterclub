# AppTesterClub

Self-hosted build distribution. Push a build from your terminal, open a link on
your phone, install it. Your own TestFlight, on your own storage, with no review
queue and no third party holding your binaries.

```bash
atc push ./MyApp.ipa
```

That is the whole command. Version, build number, bundle identifier, icon,
minimum OS and the entire signing profile are read out of the binary. You get
back an install link and a QR code.

## Deploy your own

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Faditya-28%2Fapptesterclub&project-name=apptesterclub&repository-name=apptesterclub&env=ATC_PASSWORD%2CATC_UPLOAD_TOKEN&envDescription=A%20password%20for%20the%20web%20pages%2C%20and%20a%20token%20the%20CLI%20and%20phone%20app%20use.%20Generate%20the%20token%20with%3A%20openssl%20rand%20-hex%2024&envLink=https%3A%2F%2Fgithub.com%2Faditya-28%2Fapptesterclub%2Fblob%2Fmain%2F.env.example&demo-title=AppTesterClub&demo-description=Self-hosted%20build%20distribution.%20Push%20a%20build%2C%20install%20it%20on%20a%20device.&demo-url=https%3A%2F%2Fgithub.com%2Faditya-28%2Fapptesterclub&stores=%5B%7B%22type%22%3A%22blob%22%7D%5D)

One click. Vercel clones the repository, creates the project, **provisions the
blob store for you**, and asks for two values:

| | |
|---|---|
| `ATC_PASSWORD` | Password for the web pages. Pick anything. |
| `ATC_UPLOAD_TOKEN` | What the CLI and phone app authenticate with. Generate one: `openssl rand -hex 24` |

That is the whole setup. The free tier is enough for one developer, and TLS —
which iOS requires for over-the-air install — comes with it.

> **Status: early but working.** In production for one developer across iOS,
> Android and macOS. Two known limits: the upload tool needs macOS, because it
> reads IPAs with `plutil` and friends, and Vercel is the only deployment
> target. See [ROADMAP.md](ROADMAP.md).

## The part other tools get wrong

An iOS ad hoc build only installs on devices that were named in its provisioning
profile **when it was signed**. When that is not true, iOS fails silently. No
message, no error — the icon just never appears. Every distribution tool lets
you discover this by watching nothing happen.

AppTesterClub reads the profile out of the IPA at upload and tells you first:

- which devices this build can install on, and whether yours is one of them
- whether the signature has expired, before you tap rather than after
- a **Will it work on this device?** check that asks the device for its own
  identifier and answers plainly, with the exact command to fix a no

## What it does

| | |
|---|---|
| **One command** | `atc push ./App.ipa` — no flags needed for iOS |
| **Reads the binary** | Version, icon, identifier, minimum OS, signing profile, device list |
| **Over-the-air install** | Tap a link, the app installs. No cable, no Xcode |
| **Eligibility check** | Answers "will this install on my phone?" before you try |
| **Version history** | Every build kept and reinstallable, so you can find where a bug started |
| **QR codes** | In the terminal and on the page. Laptop to phone in one scan |
| **Push notifications** | Optional. Fires the moment a build lands |
| **Three platforms** | iOS, Android and macOS |

## Running it locally

```bash
git clone https://github.com/aditya-28/apptesterclub.git
cd apptesterclub
npm install
cp .env.example .env.local     # ATC_PASSWORD, ATC_UPLOAD_TOKEN, BLOB_READ_WRITE_TOKEN
npm run dev
```

Open it before configuring anything and it tells you what is missing rather than
failing — but it needs a blob store to do anything useful, so `vercel env pull`
from a deployed project is the quickest way to get one.

Then point the CLI at it:

```bash
npm link                       # puts `atc` on your PATH
cat > ~/.atc.json <<'JSON'
{ "url": "https://your-instance.example.com",
  "uploadToken": "...",
  "blobToken": "..." }
JSON
atc push ./MyApp.ipa
```

**TLS is not optional.** iOS refuses over-the-air install over plain HTTP, so any
real deployment needs a valid certificate.

## The iOS app

A phone client lives in [`ios/`](ios/). One row per app, one button that already
knows whether you need Install, Update or Open, full version history, and
notifications when a build lands.

**You build and sign it yourself** with your own Apple account — there is no App
Store build to install. That is deliberate: it keeps every key, certificate and
push credential yours, and means the client talks only to servers you pair it
with. See [ios/README.md](ios/README.md).

```bash
cd ios && xcodegen generate && open AppTesterClub.xcodeproj
```

Pair it by opening `/pair` on your instance and scanning the code.

## How it is put together

```
  your machine or CI              your instance              your phone
  ──────────────────              ─────────────              ──────────
  atc push App.ipa
    │
    ├─ read and check the binary
    │
    ├─ artifact ───────────►  your storage       never passes
    │                         (yours alone)      through the API
    │
    └─ metadata ───────────►  build record ─────────►  install page
                              (write-once)             ├─ eligible?
                                                       ├─ expired?
                                                       └─ install
```

Two decisions worth knowing:

**The artifact goes straight from your machine to storage.** Serverless request
bodies cap at a few megabytes and an IPA is routinely forty, so only metadata
touches the API.

**There is no database.** One immutable JSON record per build in object storage.
One less service to run, and immune to a problem a mutable index has: object
storage serves public files with a cache lifetime, so a rewritten catalogue is
served stale and a freshly pushed build vanishes for a minute.

## Contributing

Small on purpose. See [CONTRIBUTING.md](CONTRIBUTING.md) — the most valuable
thing anyone could do right now is replace the macOS-only binary parsing with
pure JavaScript, which is what stops it running in CI.

## Licence

MIT. See [LICENSE](LICENSE).
