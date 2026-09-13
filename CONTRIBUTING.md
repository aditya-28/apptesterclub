# Contributing

The project is small on purpose: a tool that holds unreleased binaries should be
readable in an afternoon. Roughly 1,600 lines today, and keeping it close to
that is a feature.

## Getting set up

```bash
npm install
cp .env.example .env.local   # fill in at least ATC_PASSWORD and ATC_UPLOAD_TOKEN
npm run dev
```

## Before opening a pull request

- `npm run build` passes.
- New dependencies are argued for in the description. Each one is a thing every
  operator has to trust.
- If you touched the iOS install path, say how you tested it. A physical device
  is the only real test — the simulator cannot do over-the-air install.

## Things worth knowing before you change them

**Build records are written once and never rewritten.** An earlier design kept a
single mutable catalogue file, which is quietly broken: object storage serves
public files with a cache lifetime, so for a minute after every upload the CDN
returned the previous catalogue and a freshly pushed build 404'd. Records that
are written once cannot go stale.

**Install pages and manifests must stay reachable without a session.** Apple's
install daemon sends no cookies. Adding auth there breaks installing entirely.

**IPA parsing currently shells out to macOS tools** (`unzip`, `plutil`, `sips`,
`security`). That is the biggest limitation in the codebase — it cannot run on a
Linux CI box. Replacing it with pure JavaScript is the highest-value contribution
available right now.

## Where help is most wanted

See [ROADMAP.md](ROADMAP.md). The short version: storage adapters, JavaScript
binary parsing, Android metadata, and the standalone iOS client.
