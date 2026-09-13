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

> **Status: early.** It works — it has been running in production for one
> developer across iOS, Android and macOS — but it currently only deploys to
> Vercel, and the upload tool only runs on macOS. Both are being fixed. See
> [ROADMAP.md](ROADMAP.md).

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

## Getting started

```bash
git clone https://github.com/aditya-28/apptesterclub.git
cd apptesterclub
npm install
cp .env.example .env.local     # set ATC_PASSWORD and ATC_UPLOAD_TOKEN
npm run dev
```

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
