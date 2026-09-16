#!/usr/bin/env node
/**
 * Configure Apple push for this instance.
 *
 *   node scripts/setup-push.mjs --key ./AuthKey_ABC123.p8 \
 *     --key-id ABC123 --team-id DEF456 --topic com.example.client
 *
 * The .p8 can only be created in the Apple Developer portal — there is no API
 * for it — and it downloads exactly once. Everything after that is this script.
 *
 * Run it from the project directory, with the Vercel CLI linked.
 */

import { readFileSync, existsSync } from "node:fs";
import { execFileSync, spawnSync } from "node:child_process";

function die(message) {
  console.error(`setup-push: ${message}`);
  process.exit(1);
}

const args = process.argv.slice(2);
const flag = (name) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};

if (args.includes("--help") || args.length === 0) {
  console.log(`Usage: node scripts/setup-push.mjs --key <file.p8> --key-id <id> --team-id <id> --topic <bundle-id>

  --key      The .p8 downloaded from the Apple Developer portal
  --key-id   The 10-character Key ID shown beside it
  --team-id  Your 10-character Apple Team ID
  --topic    The bundle identifier of the iOS client you built

Everything is written to the linked Vercel project. A redeploy follows, because
environment variables are baked in at build time and an existing deployment will
not pick them up.
`);
  process.exit(args.length === 0 ? 1 : 0);
}

const keyPath = flag("key");
const keyId = flag("key-id");
const teamId = flag("team-id");
const topic = flag("topic");

for (const [name, value] of Object.entries({ key: keyPath, "key-id": keyId, "team-id": teamId, topic })) {
  if (!value) die(`--${name} is required. Run with --help.`);
}
if (!existsSync(keyPath)) die(`no such file: ${keyPath}`);

const key = readFileSync(keyPath, "utf8");
if (!key.includes("BEGIN PRIVATE KEY")) {
  die(`${keyPath} does not look like a .p8 private key.`);
}
// Apple's key IDs and team IDs are both ten characters. Catching a swapped pair
// here beats debugging silent 403s from APNs later.
for (const [name, value] of Object.entries({ "key-id": keyId, "team-id": teamId })) {
  if (!/^[A-Z0-9]{10}$/i.test(value)) die(`--${name} should be 10 letters and digits, got "${value}".`);
}

const vars = {
  APNS_PRIVATE_KEY: key,
  APNS_KEY_ID: keyId,
  APNS_TEAM_ID: teamId,
  APNS_TOPIC: topic,
};

for (const [name, value] of Object.entries(vars)) {
  for (const env of ["production", "preview", "development"]) {
    // Remove first: `env add` appends rather than replaces, and a second value
    // for the same name in the same environment is rejected.
    spawnSync("npx", ["vercel", "env", "rm", name, env, "--yes"], { stdio: "ignore" });
    const result = spawnSync("npx", ["vercel", "env", "add", name, env], {
      input: value,
      stdio: ["pipe", "ignore", "ignore"],
    });
    if (result.status !== 0) die(`could not set ${name} for ${env}. Is this folder linked with \`vercel link\`?`);
  }
  console.log(`  set ${name}`);
}

console.log("\nDeploying, because environment variables only take effect on a new build.");
execFileSync("npx", ["vercel", "deploy", "--prod", "--yes"], { stdio: "inherit" });
console.log("\nDone. Push a build and any paired phone should hear about it.");
