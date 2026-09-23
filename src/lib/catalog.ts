import { putObject, getObject, listObjects, deleteObject, readableUrl, storageReady as ready } from "./storage";

/**
 * One immutable JSON record per build, named by its share token.
 *
 * The first design kept a single catalog.json and overwrote it. That is subtly
 * broken: Vercel Blob serves public objects with `cache-control: max-age=60`
 * and ignores a request for zero, so for a minute after every upload the CDN
 * still hands back the previous catalog and a freshly pushed build 404s.
 *
 * Records that are written once and never rewritten cannot go stale. A new
 * object has no cached copy to serve, so the very first read is correct.
 * Listing goes through the blob API rather than the CDN, which is consistent.
 */

export type Platform = "ios" | "android" | "macos";

export type Build = {
  /** Unguessable, and also the record's filename. The iOS install daemon sends
   *  no cookies, so the manifest and binary must be reachable without a
   *  session; this token is the access control. */
  shareToken: string;
  appSlug: string;
  appName: string;
  platform: Platform;
  bundleId?: string;
  version: string;
  buildNumber: string;
  /** Storage key for the binary. Records written before the storage layer
   *  existed carry an absolute `fileUrl` instead; both are honoured. */
  fileKey?: string;
  fileUrl?: string;
  fileName: string;
  fileSize: number;
  notes?: string;
  gitSha?: string;
  branch?: string;
  minOs?: string;
  /** From the IPA's CFBundleURLTypes. Lets a client detect that the app is
   *  installed and offer to open it. */
  urlScheme?: string;
  iconKey?: string;
  iconUrl?: string;
  /** Read out of the IPA's embedded.mobileprovision at upload time. This is what
   *  lets a client say "this build will not install on your device" before the
   *  user taps, rather than letting iOS fail with no explanation. */
  profileName?: string;
  profileType?: "development" | "ad-hoc" | "app-store" | "enterprise";
  profileExpiresAt?: string;
  teamName?: string;
  provisionedUDIDs?: string[];
  createdAt: string;
};

export type App = {
  slug: string;
  name: string;
  platform: Platform;
  bundleId?: string;
  builds: Build[];
};

const PREFIX = "meta/";

/** Storage is the one thing that cannot be defaulted. Without it every page
 *  that lists builds fails, so it is checked up front and reported as a setup
 *  step rather than surfacing as a 500 from deep inside the SDK. */
export function storageReady(): boolean {
  return ready();
}

/** A URL a browser or Apple's install daemon can fetch. Prefers the storage
 *  key, falling back to the absolute URL on older records. */
export async function urlFor(key?: string, legacy?: string): Promise<string> {
  if (key) return readableUrl(key);
  return legacy ?? "";
}
const recordPath = (token: string) => `${PREFIX}${token}.json`;

export async function putBuild(build: Build): Promise<void> {
  await putObject(recordPath(build.shareToken), JSON.stringify(build), "application/json");
}

export async function deleteBuild(token: string): Promise<void> {
  await deleteObject(recordPath(token));
}

/** Reading one build by token. The record is immutable, so this is exact. */
export async function getBuild(token: string): Promise<Build | null> {
  if (!/^[0-9a-f]{32}$/.test(token)) return null;
  const raw = await getObject(recordPath(token));
  if (!raw) return null;
  try {
    return JSON.parse(raw.toString()) as Build;
  } catch {
    return null;
  }
}

export async function allBuilds(): Promise<Build[]> {
  const objects = await listObjects(PREFIX);
  const records = await Promise.all(
    objects.map(async (o) => {
      const raw = await getObject(o.key);
      if (!raw) return null;
      try {
        return JSON.parse(raw.toString()) as Build;
      } catch {
        return null;
      }
    }),
  );
  return records
    .filter((b): b is Build => b !== null)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

/** Apps are derived from their builds rather than stored separately, so there
 *  is no second record to keep in step. */
export function groupIntoApps(builds: Build[]): App[] {
  const bySlug = new Map<string, App>();
  for (const b of builds) {
    const existing = bySlug.get(b.appSlug);
    if (existing) {
      existing.builds.push(b);
    } else {
      bySlug.set(b.appSlug, {
        slug: b.appSlug,
        name: b.appName,
        platform: b.platform,
        bundleId: b.bundleId,
        builds: [b],
      });
    }
  }
  return [...bySlug.values()].sort((a, b) => a.name.localeCompare(b.name));
}

export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const mb = bytes / (1024 * 1024);
  if (mb < 1) return `${(bytes / 1024).toFixed(0)} KB`;
  return `${mb.toFixed(1)} MB`;
}

export function platformLabel(p: Platform): string {
  return p === "ios" ? "iOS" : p === "macos" ? "macOS" : "Android";
}
