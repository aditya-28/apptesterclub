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

## See it working

**[apptesterclub.vercel.app](https://apptesterclub.vercel.app)** — password `demo`

A real instance with a real signed build in it. Open it on an iPhone and the
install actually runs, though it will decline unless your device happens to be
in that build's provisioning profile — which is the whole point, and the install
page will tell you so plainly instead of failing in silence.

Browsing only. Pushing needs the upload token, which is not published.

## Deploy your own

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Faditya-28%2Fapptesterclub&project-name=apptesterclub&repository-name=apptesterclub&env=ATC_PASSWORD%2CATC_UPLOAD_TOKEN&envDescription=A%20password%20for%20the%20web%20pages%2C%20and%20a%20token%20the%20CLI%20and%20phone%20app%20use.%20Generate%20the%20token%20with%3A%20openssl%20rand%20-hex%2024&envLink=https%3A%2F%2Fgithub.com%2Faditya-28%2Fapptesterclub%2Fblob%2Fmain%2F.env.example&demo-title=AppTesterClub&demo-description=Self-hosted%20build%20distribution.%20Push%20a%20build%2C%20install%20it%20on%20a%20device.&demo-url=https%3A%2F%2Fgithub.com%2Faditya-28%2Fapptesterclub&stores=%5B%7B%22type%22%3A%22blob%22%7D%5D)

One click. Vercel clones the repository, creates the project, **provisions the
blob store for you**, and asks for two values:

| | |
|---|---|
| `ATC_PASSWORD` | Password for the web pages. Pick anything. |
| `ATC_UPLOAD_TOKEN` | What the CLI and phone app authenticate with. Generate one: `openssl rand -hex 24` |

### Two things to do straight after

**1. Turn off Vercel's deployment protection.** New projects get it enabled, and
it blocks Apple's install daemon — which cannot log in to anything. Installs
then fail with no error the user can see, which is the single most confusing way
this can break. Project → Settings → **Deployment Protection** → set Vercel
Authentication to Disabled.

Your instance is still protected: the web pages need `ATC_PASSWORD`, the API
needs `ATC_UPLOAD_TOKEN`, and install links carry a 128-bit unguessable token.

**2. Give the CLI the same storage credentials.** The command line uploads
binaries straight to storage rather than through the API, so serverless request
limits never cap the size of a build. That means it needs the credentials the
deployment has.

On Vercel Blob:

```bash
npx vercel env pull .env.production --environment=production
grep BLOB_READ_WRITE_TOKEN .env.production
```

```json
{
  "url": "https://your-instance.vercel.app",
  "uploadToken": "...",
  "blobToken": "vercel_blob_rw_..."
}
```

On S3-compatible storage, the `s3` block replaces `blobToken`:

```json
{
  "url": "https://your-instance.vercel.app",
  "uploadToken": "...",
  "s3": {
    "endpoint": "https://<account-id>.r2.cloudflarestorage.com",
    "region": "auto",
    "bucket": "your-bucket",
    "accessKeyId": "...",
    "secretAccessKey": "..."
  }
}
```

`chmod 600 ~/.atc.json` — it holds a write credential.

### Storage backends

Vercel Blob by default. Set `S3_BUCKET` and `S3_ACCESS_KEY_ID` and it uses that
instead: Cloudflare R2, MinIO, Backblaze B2 or AWS S3, same adapter. R2 is the
reason this exists, because an IPA is re-downloaded on every install by every
tester and R2 charges nothing for egress.

Download links are signed when one is needed and expire in an hour. Apple's
install daemon cannot authenticate, so the object has to be fetchable without
credentials; signing it at manifest time gives that without leaving a leaked
install link working forever. Set `S3_PUBLIC_URL` to serve from a public bucket
instead.

Build records written before you switch carry an absolute URL rather than a
key. Both are honoured, so old install links keep working and nothing has to be
migrated.

**Two instances must not share a bucket unprefixed.** The catalogue lists every
object under `meta/`, so they would each show the other's builds and serve the
other's binaries. Two ways out:

- **Separate buckets**, each with its own scoped token. The stronger option,
  and the default advice.
- **One bucket, `S3_PREFIX` per instance.** Set `S3_PREFIX=tenant-a` on one and
  `S3_PREFIX=tenant-b` on the other and each gets its own namespace inside the
  bucket. Useful when one R2 token is scoped to a single bucket, which is what
  Cloudflare gives you by default.

  A prefix separates the catalogues, not the access. Any credential that can
  reach the bucket can reach every prefix in it, so share one only between
  deployments you would trust with each other's builds — including trusting
  them not to delete them. The prefix is applied on write and stripped on read,
  so it never appears inside a build record and a record stays portable.

**Moving an instance that already has builds:**

```bash
npx vercel env pull .env.production --environment=production
set -a && . ./.env.production && set +a     # the blob token
export S3_ENDPOINT=... S3_BUCKET=... S3_ACCESS_KEY_ID=... S3_SECRET_ACCESS_KEY=...

node scripts/migrate-storage.mjs            # report what would happen
node scripts/migrate-storage.mjs --apply    # copy, and rewrite the records
```

It is re-runnable and never deletes anything from Blob. Verify a real install
off the new storage before removing the old copy, and remove
`BLOB_READ_WRITE_TOKEN` from the deployment afterwards so there is no silent
fallback.

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

## Notifications

A build pushed to your instance can reach every paired phone within seconds.
Optional — leave it unconfigured and everything else works, silently.

It needs an Apple push key, which **can only be created in the Apple Developer
portal**. There is no API for it, and it downloads exactly once.

Certificates, Identifiers & Profiles &rarr; **Keys** &rarr; **+** &rarr; tick
**Apple Push Notifications service (APNs)** &rarr; Continue &rarr; Register, then
download the `.p8`. Note the Key ID beside it, and your Team ID from the top
right of the portal.

```bash
node scripts/setup-push.mjs --key ./AuthKey_ABC1234567.p8 \
  --key-id ABC1234567 --team-id DEF1234567 --topic com.you.apptesterclub
```

`--topic` is the bundle identifier of the iOS client **you** built, not this
repository's default. The script sets all four variables and redeploys, because
environment variables are baked in at build time.

Settings in the app shows whether this device registered, so you can tell a
permission problem from a server one.

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
atc push ./MyApp.ipa
```

**TLS is not optional.** iOS refuses over-the-air install over plain HTTP, so any
real deployment needs a valid certificate. That rules out pushing to a localhost
instance and installing from a phone — deploy first.

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
