#!/usr/bin/env node
/**
 * Move an existing instance from Vercel Blob to S3-compatible storage.
 *
 * Copies every object, then rewrites each build record so it addresses its
 * binary by key rather than by absolute Blob URL. Dry run by default: nothing
 * is written without --apply, and nothing is ever deleted from Blob. Deleting
 * the old copy is a separate, deliberate step once you have verified an install.
 *
 * Re-runnable. An object already present at the destination is skipped, so an
 * interrupted run can simply be run again.
 *
 *   node scripts/migrate-storage.mjs            # report what would happen
 *   node scripts/migrate-storage.mjs --apply    # do it
 *
 * Reads BLOB_READ_WRITE_TOKEN and the S3_* variables from the environment, or
 * from ~/.atc.json. Pull them from the deployment first:
 *
 *   npx vercel env pull .env.production --environment=production
 *   set -a && . ./.env.production && set +a
 */

import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { list } from "@vercel/blob";
import {
  S3Client, PutObjectCommand, HeadObjectCommand, GetObjectCommand,
  ListObjectsV2Command,
} from "@aws-sdk/client-s3";

const apply = process.argv.includes("--apply");

let file = {};
const path = join(homedir(), ".atc.json");
if (existsSync(path)) {
  try { file = JSON.parse(readFileSync(path, "utf8")); } catch {}
}

const blobToken = process.env.BLOB_READ_WRITE_TOKEN || file.blobToken;
const s3cfg = {
  endpoint: process.env.S3_ENDPOINT || file.s3?.endpoint,
  bucket: process.env.S3_BUCKET || file.s3?.bucket,
  accessKeyId: process.env.S3_ACCESS_KEY_ID || file.s3?.accessKeyId,
  secretAccessKey: process.env.S3_SECRET_ACCESS_KEY || file.s3?.secretAccessKey,
  region: process.env.S3_REGION || file.s3?.region || "auto",
  prefix: (process.env.S3_PREFIX || file.s3?.prefix || "").replace(/^\/+|\/+$/g, ""),
};

/** Where an object lives in the bucket, once this instance's prefix is applied. */
const at = (key) => (s3cfg.prefix ? `${s3cfg.prefix}/${key}` : key);

const missing = [
  !blobToken && "BLOB_READ_WRITE_TOKEN",
  !s3cfg.endpoint && "S3_ENDPOINT",
  !s3cfg.bucket && "S3_BUCKET",
  !s3cfg.accessKeyId && "S3_ACCESS_KEY_ID",
  !s3cfg.secretAccessKey && "S3_SECRET_ACCESS_KEY",
].filter(Boolean);
if (missing.length) {
  console.error(`migrate: missing ${missing.join(", ")}`);
  process.exit(1);
}

const s3 = new S3Client({
  region: s3cfg.region,
  endpoint: s3cfg.endpoint,
  credentials: { accessKeyId: s3cfg.accessKeyId, secretAccessKey: s3cfg.secretAccessKey },
});

/**
 * A bucket already holding build records belongs to another instance.
 *
 * The catalogue lists every object under `meta/`, so two instances sharing one
 * bucket would each show the other's builds and serve the other's binaries.
 * Give each instance its own bucket.
 */
const existing = await s3.send(new ListObjectsV2Command({ Bucket: s3cfg.bucket, Prefix: at("meta/"), MaxKeys: 1 }));
if ((existing.KeyCount ?? 0) > 0) {
  console.error(
    `migrate: ${s3cfg.bucket}${s3cfg.prefix ? "/" + s3cfg.prefix : ""} already contains build records.\n` +
    `         Two instances must not share one bucket and prefix, or the two\n` +
    `         catalogues merge. Set S3_PREFIX to give this instance its own.`,
  );
  process.exit(1);
}

// Every blob, paged.
const blobs = [];
let cursor;
do {
  const page = await list({ token: blobToken, limit: 1000, cursor });
  blobs.push(...page.blobs);
  cursor = page.hasMore ? page.cursor : undefined;
} while (cursor);

const bytes = blobs.reduce((n, b) => n + (b.size ?? 0), 0);
console.log(
  `migrate: ${blobs.length} objects, ${(bytes / 1048576).toFixed(1)} MB` +
  (apply ? "" : "  (dry run, nothing will be written)"),
);
if (!blobs.length) process.exit(0);

// Blob URL -> key, so a record's absolute fileUrl can be resolved to the key
// the same bytes now live at.
const byUrl = new Map(blobs.map((b) => [b.url, b.pathname]));

let copied = 0, skipped = 0, rewritten = 0;

for (const blob of blobs) {
  if (blob.pathname.startsWith("meta/")) continue;   // records go last, rewritten
  try {
    await s3.send(new HeadObjectCommand({ Bucket: s3cfg.bucket, Key: at(blob.pathname) }));
    skipped++;
    continue;
  } catch { /* not there yet */ }

  if (!apply) { copied++; continue; }
  const res = await fetch(blob.url);
  if (!res.ok) { console.error(`  could not read ${blob.pathname} (${res.status})`); continue; }
  await s3.send(new PutObjectCommand({
    Bucket: s3cfg.bucket,
    Key: at(blob.pathname),
    Body: Buffer.from(await res.arrayBuffer()),
    ContentType: res.headers.get("content-type") ?? "application/octet-stream",
  }));
  copied++;
  process.stdout.write(".");
}
if (apply && copied) process.stdout.write("\n");

/** A record's fileUrl becomes a fileKey, so the server signs it at request time. */
for (const blob of blobs.filter((b) => b.pathname.startsWith("meta/"))) {
  const res = await fetch(blob.url, { cache: "no-store" });
  if (!res.ok) { console.error(`  could not read ${blob.pathname}`); continue; }
  const record = JSON.parse(await res.text());

  if (record.fileUrl && byUrl.has(record.fileUrl)) {
    record.fileKey = byUrl.get(record.fileUrl);
    delete record.fileUrl;
  }
  if (record.iconUrl && byUrl.has(record.iconUrl)) {
    record.iconKey = byUrl.get(record.iconUrl);
    delete record.iconUrl;
  }
  // A record whose binary is not in this Blob store keeps its absolute URL.
  // Both forms are honoured, so the old link goes on working.

  if (!apply) { rewritten++; continue; }
  await s3.send(new PutObjectCommand({
    Bucket: s3cfg.bucket,
    Key: at(blob.pathname),
    Body: JSON.stringify(record),
    ContentType: "application/json",
  }));
  rewritten++;
}

console.log(
  `migrate: ${apply ? "copied" : "would copy"} ${copied}, already present ${skipped}, ` +
  `${apply ? "rewrote" : "would rewrite"} ${rewritten} records`,
);
if (!apply) console.log("migrate: re-run with --apply to do it.");
else console.log(
  "migrate: Vercel Blob is untouched. Verify an install, then delete it separately.",
);
