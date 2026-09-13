# Security

## Reporting a vulnerability

Open a [private security advisory](https://github.com/aditya-28/apptesterclub/security/advisories/new)
rather than a public issue. You will get an acknowledgement within a few days.

## How access works

AppTesterClub holds unreleased binaries, so it is worth being precise about what
protects what.

| Surface | Protection |
|---|---|
| Browsable catalogue | Admin password, session cookie signed with it |
| Upload API | Bearer token |
| Install pages and OTA manifests | 128-bit unguessable token, **no session** |
| Device check results | Addressed by a random nonce, never by device identifier |
| Artifacts in storage | Unguessable paths |

**Install links are capability URLs.** Anyone holding one can download that
build. That is deliberate: the iOS install daemon sends no cookies, so a session
check on those routes would break the only flow they exist for. Treat an install
link like a password. Per-link expiry is on the roadmap.

**Turn off platform-level access protection for install routes.** Vercel's
deployment protection, Cloudflare Access and similar will block Apple's install
daemon, and the install then fails with no error the user can see.

**TLS is not optional.** iOS refuses over-the-air install over plain HTTP.

## What is not sent anywhere

No telemetry, no analytics, no phoning home. Binaries go from your machine to
your storage. The only outbound request the server makes is to Apple's push
service, and only if you configure it.
