import { put, head, list, del } from "@vercel/blob";

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
  fileUrl: string;
  fileName: string;
  fileSize: number;
  notes?: string;
  gitSha?: string;
  branch?: string;
  minOs?: string;
  /** From the IPA's CFBundleURLTypes. Lets a client detect that the app is
   *  installed and offer to open it. */
  urlScheme?: string;
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
const recordPath = (token: string) => `${PREFIX}${token}.json`;

export async function putBuild(build: Build): Promise<void> {
  await put(recordPath(build.shareToken), JSON.stringify(build), {
    access: "public",
    contentType: "application/json",
    addRandomSuffix: false,
  });
}

export async function deleteBuild(token: string): Promise<void> {
  try {
    const meta = await head(recordPath(token));
    await del(meta.url);
  } catch {
    // Already gone is the outcome we wanted.
  }
}

/** Reading one build by token. The record is immutable, so this is exact. */
export async function getBuild(token: string): Promise<Build | null> {
  if (!/^[0-9a-f]{32}$/.test(token)) return null;
  try {
    const meta = await head(recordPath(token));
    const res = await fetch(meta.url, { cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as Build;
  } catch {
    return null;
  }
}

export async function allBuilds(): Promise<Build[]> {
  const { blobs } = await list({ prefix: PREFIX, limit: 1000 });
  const records = await Promise.all(
    blobs.map(async (b) => {
      try {
        const res = await fetch(b.url, { cache: "no-store" });
        return res.ok ? ((await res.json()) as Build) : null;
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
