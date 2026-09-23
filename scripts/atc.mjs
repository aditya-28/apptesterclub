#!/usr/bin/env node
/**
 * Push a build to AppTesterClub.
 *
 *   atc push ./build/App.ipa --app myapp
 *   atc push ./app-release.apk --app myapp --platform android --version 1.2 --build 7
 *
 * The binary goes straight from this machine to blob storage, so the 4.5 MB
 * serverless request limit never comes into it. Only the metadata touches the
 * API.
 *
 * Config, from the environment or ~/.atc.json:
 *   ATC_URL             https://atc.example.com
 *   ATC_UPLOAD_TOKEN    bearer token the API checks
 *
 * ...plus storage credentials, because the binary goes straight there rather
 * than through the API. Either S3-compatible (Cloudflare R2, MinIO, AWS):
 *   S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY
 * or Vercel Blob:
 *   BLOB_READ_WRITE_TOKEN
 */

import { readFileSync, statSync, existsSync, writeFileSync, unlinkSync, mkdtempSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { basename, extname, join } from "node:path";
import { homedir, tmpdir } from "node:os";
import { put } from "@vercel/blob";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

// ---------------------------------------------------------------- config

function loadConfig() {
  const file = join(homedir(), ".atc.json");
  let fromFile = {};
  if (existsSync(file)) {
    try {
      fromFile = JSON.parse(readFileSync(file, "utf8"));
    } catch {
      die(`~/.atc.json is not valid JSON.`);
    }
  }
  const cfg = {
    url: process.env.ATC_URL || fromFile.url,
    uploadToken: process.env.ATC_UPLOAD_TOKEN || fromFile.uploadToken,
    blobToken: process.env.BLOB_READ_WRITE_TOKEN || fromFile.blobToken,
    s3: {
      endpoint: process.env.S3_ENDPOINT || fromFile.s3?.endpoint,
      bucket: process.env.S3_BUCKET || fromFile.s3?.bucket,
      accessKeyId: process.env.S3_ACCESS_KEY_ID || fromFile.s3?.accessKeyId,
      secretAccessKey: process.env.S3_SECRET_ACCESS_KEY || fromFile.s3?.secretAccessKey,
      region: process.env.S3_REGION || fromFile.s3?.region || "auto",
    },
  };
  cfg.useS3 = Boolean(cfg.s3.bucket && cfg.s3.accessKeyId && cfg.s3.secretAccessKey && cfg.s3.endpoint);

  const missing = [];
  if (!cfg.url) missing.push("url");
  if (!cfg.uploadToken) missing.push("uploadToken");
  // One storage backend has to be configured; which one is the operator's call.
  if (!cfg.useS3 && !cfg.blobToken) missing.push("blobToken (or the S3_* settings)");
  if (missing.length) {
    die(
      `Missing config: ${missing.join(", ")}.\n` +
        `Set them in the environment or in ~/.atc.json.`,
    );
  }
  cfg.url = cfg.url.replace(/\/+$/, "");
  return cfg;
}

// ------------------------------------------------------------------ args

function parseArgs(argv) {
  const positional = [];
  const flags = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next === undefined || next.startsWith("--")) flags[key] = true;
      else {
        flags[key] = next;
        i++;
      }
    } else positional.push(a);
  }
  return { positional, flags };
}

function die(msg) {
  console.error(`atc: ${msg}`);
  process.exit(1);
}

// ------------------------------------------------- metadata from the IPA

/**
 * Read Info.plist out of the IPA. macOS ships unzip and plutil, so this needs
 * no extra dependency. Anything unreadable falls back to the flags.
 */
function readIpaMetadata(path) {
  try {
    const listing = execFileSync("unzip", ["-Z1", path], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const entry = listing
      .split("\n")
      .find((l) => /^Payload\/[^/]+\.app\/Info\.plist$/.test(l.trim()));
    if (!entry) return {};

    const raw = execFileSync("unzip", ["-p", path, entry.trim()], {
      encoding: "buffer",
      maxBuffer: 16 * 1024 * 1024,
      stdio: ["ignore", "pipe", "ignore"],
    });
    const json = execFileSync("plutil", ["-convert", "json", "-o", "-", "-"], {
      input: raw,
      encoding: "utf8",
      maxBuffer: 16 * 1024 * 1024,
    });
    const plist = JSON.parse(json);
    return {
      bundleId: plist.CFBundleIdentifier,
      version: plist.CFBundleShortVersionString,
      buildNumber: plist.CFBundleVersion,
      name: plist.CFBundleDisplayName || plist.CFBundleName,
      minOs: plist.MinimumOSVersion,
      // The first declared URL scheme, which is how a catalogue client can tell
      // the app is installed and offer to open it.
      urlScheme: plist.CFBundleURLTypes?.[0]?.CFBundleURLSchemes?.[0],
    };
  } catch {
    return {};
  }
}

/**
 * Read the embedded provisioning profile. This is what lets the install page
 * say "this build will not run on your device" before the user taps, instead of
 * letting iOS fail silently with no explanation — the single most useful thing
 * a distribution site does.
 */
function readProvisioning(path) {
  const tmp = join(tmpdir(), `atc-prov-${process.pid}.plist`);
  try {
    const listing = execFileSync("unzip", ["-Z1", path], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    const entry = listing
      .split("\n")
      .find((l) => /^Payload\/[^/]+\.app\/embedded\.mobileprovision$/.test(l.trim()));
    if (!entry) return {};

    const raw = execFileSync("unzip", ["-p", path, entry.trim()], {
      encoding: "buffer",
      maxBuffer: 16 * 1024 * 1024,
      stdio: ["ignore", "pipe", "ignore"],
    });
    // The profile is CMS-signed; strip the signature to reach the plist.
    const der = execFileSync("security", ["cms", "-D", "-i", "/dev/stdin"], {
      input: raw,
      encoding: "buffer",
      maxBuffer: 16 * 1024 * 1024,
      stdio: ["pipe", "pipe", "ignore"],
    });
    writeFileSync(tmp, der);

    // Key by key rather than converting the whole thing: the profile carries the
    // developer certificates as <data>, and `plutil -convert json` refuses the
    // entire document rather than skipping them.
    const extract = (key, fmt = "raw") => {
      try {
        return execFileSync("plutil", ["-extract", key, fmt, "-o", "-", tmp], {
          encoding: "utf8",
          stdio: ["ignore", "pipe", "ignore"],
        }).trim();
      } catch {
        return undefined;
      }
    };

    const devicesJSON = extract("ProvisionedDevices", "json");
    const devices = devicesJSON ? JSON.parse(devicesJSON) : undefined;
    const getTaskAllow = extract("Entitlements.get-task-allow");
    const allDevices = extract("ProvisionsAllDevices");

    // Apple does not label the type, so infer it the way Xcode does.
    let profileType = "app-store";
    if (devices && getTaskAllow === "true") profileType = "development";
    else if (devices) profileType = "ad-hoc";
    else if (allDevices === "true") profileType = "enterprise";

    const expires = extract("ExpirationDate");
    return {
      profileName: extract("Name"),
      profileType,
      profileExpiresAt: expires ? new Date(expires).toISOString() : undefined,
      teamName: extract("TeamName"),
      provisionedUDIDs: devices ?? [],
    };
  } catch {
    return {};
  } finally {
    try {
      unlinkSync(tmp);
    } catch {
      /* nothing to clean up */
    }
  }
}

/**
 * Pull the app icon out of the bundle so the catalogue can show it.
 *
 * Xcode writes icons as CgBI PNGs — Apple's own variant with the colour
 * channels swapped and the alpha premultiplied. Browsers refuse them outright.
 * sips reads the format and re-emits a standard PNG, which is why this is a
 * round trip through a file rather than a straight copy.
 */
function extractIcon(path) {
  const dir = mkdtempSync(join(tmpdir(), "atc-icon-"));
  try {
    const listing = execFileSync("unzip", ["-Z1", path], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).split("\n");

    const candidates = listing
      .map((l) => l.trim())
      .filter((l) => /^Payload\/[^/]+\.app\/AppIcon[^/]*\.png$/i.test(l));
    if (candidates.length === 0) return undefined;

    let best = null;
    for (const entry of candidates) {
      const local = join(dir, basename(entry));
      writeFileSync(
        local,
        execFileSync("unzip", ["-p", path, entry], {
          encoding: "buffer",
          maxBuffer: 32 * 1024 * 1024,
          stdio: ["ignore", "pipe", "ignore"],
        }),
      );
      try {
        const w = parseInt(
          execFileSync("sips", ["-g", "pixelWidth", local], {
            encoding: "utf8",
            stdio: ["ignore", "pipe", "ignore"],
          })
            .trim()
            .split(":")
            .pop(),
          10,
        );
        if (!best || w > best.width) best = { width: w, file: local };
      } catch {
        /* unreadable, try the next one */
      }
    }
    if (!best) return undefined;

    const out = join(dir, "icon.png");
    execFileSync("sips", ["-s", "format", "png", best.file, "--out", out], {
      stdio: ["ignore", "ignore", "ignore"],
    });
    return readFileSync(out);
  } catch {
    return undefined;
  } finally {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      /* nothing to clean up */
    }
  }
}

function gitInfo() {
  const run = (args) => {
    try {
      return execFileSync("git", args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
    } catch {
      return undefined;
    }
  };
  return { gitSha: run(["rev-parse", "HEAD"]), branch: run(["rev-parse", "--abbrev-ref", "HEAD"]) };
}

function platformFor(file, explicit) {
  if (explicit) return explicit;
  const ext = extname(file).toLowerCase();
  if (ext === ".ipa") return "ios";
  if (ext === ".apk" || ext === ".aab") return "android";
  if (ext === ".dmg" || ext === ".pkg" || ext === ".zip") return "macos";
  return undefined;
}

// ------------------------------------------------------------------ main

const argv = process.argv.slice(2);
// `atc push file` and `atc file` both work; the verb exists so more can be
// added later without breaking the short form people will actually type.
if (argv[0] === "push") argv.shift();
const { positional, flags } = parseArgs(argv);

if (flags.help || positional.length === 0) {
  console.log(`Usage: atc push <file> [options]

  --app          Short slug the build belongs to (required)
  --name         Display name, defaults to the slug or the app's own name
  --platform     ios | android | macos, inferred from the file extension
  --version      Marketing version, read from an IPA automatically
  --build        Build number, read from an IPA automatically
  --bundle-id    Bundle identifier, read from an IPA automatically
  --min-os       Minimum OS version
  --url-scheme   URL scheme, read from an IPA automatically
  --notes        What changed in this build
`);
  process.exit(positional.length === 0 ? 1 : 0);
}

const file = positional[0];
if (!existsSync(file)) die(`no such file: ${file}`);

const cfg = loadConfig();
const appSlug = flags.app;
if (!appSlug) die("--app <slug> is required.");

const platform = platformFor(file, flags.platform);
if (!platform) die(`cannot infer platform from "${basename(file)}" — pass --platform.`);

const fromIpa = platform === "ios" ? readIpaMetadata(file) : {};
const prov = platform === "ios" ? readProvisioning(file) : {};
const version = flags.version || fromIpa.version;
const buildNumber = flags.build || fromIpa.buildNumber;
const bundleId = flags["bundle-id"] || fromIpa.bundleId;

if (!version) die("could not determine the version — pass --version.");
if (!buildNumber) die("could not determine the build number — pass --build.");
if (platform === "ios" && !bundleId) {
  die("an iOS build needs a bundle identifier for the OTA manifest — pass --bundle-id.");
}

const size = statSync(file).size;
const fileName = basename(file);
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const key = `builds/${appSlug}/${version}-${buildNumber}-${stamp}/${fileName}`;

console.log(`atc: uploading ${fileName} (${(size / 1048576).toFixed(1)} MB)`);

/**
 * Straight from this machine to storage. The API only ever sees metadata, so
 * serverless request limits never cap the binary size.
 */
async function upload(storageKey, bytes, contentType) {
  if (cfg.useS3) {
    const s3 = new S3Client({
      region: cfg.s3.region,
      endpoint: cfg.s3.endpoint,
      credentials: { accessKeyId: cfg.s3.accessKeyId, secretAccessKey: cfg.s3.secretAccessKey },
    });
    await s3.send(new PutObjectCommand({
      Bucket: cfg.s3.bucket, Key: storageKey, Body: bytes, ContentType: contentType,
    }));
    // The server signs a URL when one is needed; the key is what it stores.
    return { key: storageKey, url: undefined };
  }
  const blob = await put(storageKey, bytes, {
    access: "public", token: cfg.blobToken, contentType, addRandomSuffix: false,
  });
  return { key: undefined, url: blob.url };
}

const stored = await upload(
  key,
  readFileSync(file),
  platform === "android" ? "application/vnd.android.package-archive" : "application/octet-stream",
);

// The icon is small and rarely changes, but it is keyed per build so an app
// that rebrands does not retroactively relabel its own history.
let iconKey, iconUrl;
if (platform === "ios") {
  const icon = extractIcon(file);
  if (icon) {
    const placed = await upload(`icons/${appSlug}/${version}-${buildNumber}-${stamp}.png`, icon, "image/png");
    iconKey = placed.key;
    iconUrl = placed.url;
  }
}

const { gitSha, branch } = gitInfo();

const res = await fetch(`${cfg.url}/api/builds`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    Authorization: `Bearer ${cfg.uploadToken}`,
  },
  body: JSON.stringify({
    appSlug,
    name: flags.name || fromIpa.name,
    platform,
    bundleId,
    version,
    buildNumber,
    fileKey: stored.key,
    fileUrl: stored.url,
    fileName,
    fileSize: size,
    notes: flags.notes,
    minOs: flags["min-os"] || fromIpa.minOs,
    urlScheme: flags["url-scheme"] || fromIpa.urlScheme,
    iconKey,
    iconUrl,
    ...prov,
    gitSha,
    branch,
  }),
});

if (!res.ok) {
  const body = await res.text();
  die(`API rejected the build (${res.status}): ${body}`);
}

const { installUrl, replaced, notified } = await res.json();
console.log(`atc: ${replaced ? "replaced" : "published"} ${version} (${buildNumber})`);
if (typeof notified === "number" && notified > 0) {
  console.log(`atc: notified ${notified} device${notified === 1 ? "" : "s"}`);
}
console.log(`atc: ${installUrl}`);
