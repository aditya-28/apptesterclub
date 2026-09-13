# AppTesterClub for iOS

The phone client. Shows every build on your instance, installs them in one tap,
and turns into **Open** the moment the install lands.

There is no App Store build, by design. **You build and sign this yourself**,
with your own Apple account, and it talks only to the servers you pair it with.
Nobody else's key is involved and nothing routes through a third party.

## What it does

- **One row per app** with icon, name and the newest version
- **Install / Update / Open** — the button already knows which one you need
- **Full history** behind each app, any version reinstallable
- **Several servers at once** — your own and a client's, side by side
- **Pair by scanning** the QR on your instance's `/pair` page
- **Notifications** when a build lands, if your instance has push configured
- **Expiry warnings** before you tap a build iOS would refuse

## Build it

You need Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and an Apple
developer account.

```bash
brew install xcodegen
cd ios
xcodegen generate
open AppTesterClub.xcodeproj
```

In Xcode, set the target's **Team** and change the bundle identifier from
`club.apptester.client` to something in your own namespace. Then run it on your
device.

### Or from the command line

```bash
xcodegen generate
xcodebuild -project AppTesterClub.xcodeproj -scheme AppTesterClub \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=YOURTEAMID \
  PRODUCT_BUNDLE_IDENTIFIER=com.yourname.apptesterclub \
  build
```

Signing, certificates and provisioning are the same as any other app you ship.
If you use an AI coding agent with App Store Connect access, "build and install
AppTesterClub on my phone" is usually enough.

### Skip the pairing step

A build made for one instance can carry it, so you never see the pairing screen:

```bash
ATC_SERVER_URL=https://builds.example.com ATC_SERVER_TOKEN=... xcodegen generate
```

## Two settings that matter

**`LSApplicationQueriesSchemes`** in `project.yml` is empty by default. iOS
answers `canOpenURL` false for any scheme not listed, and that is how the app
tells whether a build is already installed. **Add the URL scheme of every app
you distribute**, or every button will say Install even when the app is there.
Apple caps the list at 50.

**`aps-environment`** in `Sources/AppTesterClub.entitlements` is set to
`development`. Change it to `production` for a build you distribute, or the
device hands back a token Apple will not deliver to. Delete the key if you are
not using notifications.

## Things worth knowing before changing them

**`itms-services://` will not open through SwiftUI's `openURL`.** It silently
declines. UIKit's `open(_:options:completionHandler:)` fires it, and then
reports `false` even when the install starts, so the result cannot be trusted
either.

**iOS never announces that an install finished.** The only signal is
`canOpenURL` against the app's own scheme, so the app polls for the change.

**An update has no not-installed-to-installed edge.** The app is already there.
But iOS removes the old copy before laying down the new one, so the scheme goes
true, false, true — the installer watches for that dip, which is why updates
poll faster than fresh installs.

**iOS will not tell one app another's version.** `canOpenURL` answers installed
or not, nothing more. So the app remembers what it installed. A build that
arrived another way — Xcode, a Safari link — is invisible to that record and
shows Update rather than Open, which is the harmless direction to be wrong in.

## Known gaps

- Server tokens are in `UserDefaults`, not the keychain. On the roadmap.
- Per-app notification switches are not built yet; notifications are all or
  nothing per server.
- No offline cache. The list needs a reachable server to populate.
