# Roadmap

The product exists and works. What it cannot yet do is be installed by a
stranger. Everything below is that gap.

Status key: **done** · **blocking 1.0** · **after 1.0**

---

## Blocking 1.0 — installability

**Vercel is the deployment target.** Not a temporary state: it provisions the
blob store from the deploy button, terminates TLS (which iOS requires for
over-the-air install), and its free tier covers a solo developer. Supporting
every host would mean solving storage, TLS and deployment three times over for
an audience that has not asked yet.

- [x] **S3-compatible storage** — Cloudflare R2, MinIO, Backblaze, AWS. Chosen
      by configuration alone; leave the S3 variables unset and Vercel Blob is
      used, so an existing deployment is untouched. Records written before the
      switch keep an absolute URL and still resolve.
- [x] **One-click deploy** button that also provisions storage.
- [x] **Setup screen** instead of a crash when an instance is not finished
      being configured. A fresh deployment with no storage used to throw a 500
      from inside the Blob SDK, which tells the operator nothing.
- [ ] **JavaScript binary parsing.** Reading an IPA shells out to `unzip`,
      `plutil`, `sips` and `security`, so the CLI is macOS-only and cannot run
      on a Linux CI runner. Needs pure-JS handling of ZIP, binary plist,
      CMS-signed provisioning profiles and Apple's CgBI PNG variant. **The
      highest-value contribution available.**
- [ ] **`atc` published to npm**, configured per project or globally.
- [ ] **Verified by a stranger** from the written instructions alone. If they
      have to ask a question, this is not done.
- [ ] **Disable deployment protection automatically.** New Vercel projects
      enable it, and it blocks Apple's install daemon, so every operator has to
      find and switch it off. Documented for now; a build-time check that warns
      on the setup screen would be better.
- [ ] **Hand the blob token to the CLI without a manual step.** Right now the
      operator runs `vercel env pull` and copies a value, which is the least
      obvious part of setup.

## Blocking 1.0 — completeness

- [ ] **Android metadata parity.** Read version name, version code, package
      name, minimum SDK and icon from the APK, the way the IPA already is.
      Today Android needs every field passed by hand.
- [ ] **Named upload tokens**, revocable one at a time, so a leaked CI token
      does not mean rotating everything.
- [ ] **Expiring share links** for builds sent outside the team.
- [ ] **GitHub Action** and a documented curl recipe.
- [ ] **Documentation**: getting started, a signing guide for iOS newcomers,
      storage and deployment recipes, API reference, and troubleshooting
      organised by symptom rather than by subsystem.

## The iOS client — shipped

Lives in [`ios/`](ios/). **Every operator builds and signs their own** with
their own Apple account. There is no published App Store build.

That is the better answer rather than a compromise, and it dissolves a problem
that otherwise has no clean solution. Apple addresses push by *app*, and the key
belongs to whoever publishes it — so a self-hosted instance could never push to
a client someone else published. Every self-hosted project with a mobile client
hits that wall and ends up running a relay. Here the operator owns the app, the
key and the server, so push works directly and no central infrastructure exists
to trust.

- [x] Install / Update / Open, the button reflecting what is on the phone
- [x] Full version history, any version reinstallable
- [x] Several servers at once — yours and a client's, side by side
- [x] Pair by scanning the QR on the instance's `/pair` page
- [x] Push registration against every paired server
- [x] Expiry warnings before you tap a build iOS would refuse
- [ ] **Per-app notification switches** — currently all or nothing per server
- [ ] **Tokens in the keychain** rather than UserDefaults
- [ ] **Readable offline**, refreshing behind you

## After 1.0

- **Local filesystem storage**, for a self-hosted instance with a disk. The
  S3-compatible adapter already landed, so the interface it would implement
  exists; see `src/lib/storage.ts`
- **Docker image**, which only becomes meaningful alongside that adapter
- Release channels — internal, beta and release as separate streams
- Size change warnings — "40% larger than the last build" catches a bundled asset
- Release notes drafted from commits since the previous build
- Install receipts — who installed which version, when
- Device list — every known device and which builds it can run
- Slack and Discord webhooks
- **Re-signing** with operator-held certificates, which would remove the device
  eligibility problem entirely. Held back because it means holding other
  people's distribution certificates — too much responsibility for a first
  release

## Explicitly not planned

| Left out | Why |
|---|---|
| Accounts, roles, organisations | An instance with revocable tokens covers small teams. Real multi-tenancy is a different product |
| An Android client app | Android installs an APK straight from the browser. The website already is the Android experience |
| Crash reporting, analytics | Sentry and PostHog exist and are better at it |
| App Store submission | Adjacent, enormous, already served by `fastlane` and `asc` |
| Registering devices with Apple | Needs App Store Connect credentials on the server. Show the command instead |

## Open questions

- **Who publishes the iOS client**, and under whose Apple account. That account
  owns the push key the relay depends on, which makes it a governance question
  as much as a technical one.
- **Whether a project-run relay is acceptable at all** to the privacy-minded
  users this tool is partly for. Worth asking publicly before building it.
