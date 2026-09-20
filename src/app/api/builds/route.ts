import { NextRequest, NextResponse } from "next/server";
import { randomBytes } from "crypto";
import { checkUploadToken } from "@/lib/auth";
import { notify } from "@/lib/apns";
import { readNote } from "./[token]/note/route";
import { putBuild, deleteBuild, allBuilds, groupIntoApps, storageReady, type Build, type Platform } from "@/lib/catalog";

const PLATFORMS: Platform[] = ["ios", "android", "macos"];

export async function POST(req: NextRequest) {
  if (!checkUploadToken(req.headers.get("authorization"))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  if (!storageReady()) {
    return NextResponse.json(
      { error: "storage is not configured: BLOB_READ_WRITE_TOKEN is not set on this deployment" },
      { status: 503 },
    );
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "body must be JSON" }, { status: 400 });
  }

  const str = (k: string) => (typeof body[k] === "string" ? (body[k] as string).trim() : "");
  const appSlug = str("appSlug");
  const platform = str("platform") as Platform;
  const version = str("version");
  const buildNumber = str("buildNumber");
  const fileUrl = str("fileUrl");
  const fileName = str("fileName");
  const bundleId = str("bundleId");
  const fileSize = typeof body.fileSize === "number" ? body.fileSize : 0;

  const missing = Object.entries({ appSlug, platform, version, buildNumber, fileUrl, fileName })
    .filter(([, v]) => !v)
    .map(([k]) => k);
  if (missing.length) {
    return NextResponse.json({ error: `missing: ${missing.join(", ")}` }, { status: 400 });
  }
  if (!PLATFORMS.includes(platform)) {
    return NextResponse.json(
      { error: `platform must be one of ${PLATFORMS.join(", ")}` },
      { status: 400 },
    );
  }
  if (platform === "ios" && !bundleId) {
    // Without it the OTA manifest cannot be built and the install fails on the
    // device with no explanation, which is miserable to debug. Refuse early.
    return NextResponse.json(
      { error: "bundleId is required for ios builds (the OTA manifest needs it)" },
      { status: 400 },
    );
  }
  if (!/^[a-z0-9][a-z0-9-]*$/.test(appSlug)) {
    return NextResponse.json(
      { error: "appSlug must be lowercase letters, digits and hyphens" },
      { status: 400 },
    );
  }

  // Re-uploading the same version and build number replaces the old record,
  // which is what you want after rebuilding to fix something. The install link
  // changes, because the record is immutable by design.
  const superseded = (await allBuilds()).find(
    (b) => b.appSlug === appSlug && b.version === version && b.buildNumber === buildNumber,
  );

  const build: Build = {
    shareToken: randomBytes(16).toString("hex"),
    appSlug,
    appName: str("name") || superseded?.appName || appSlug,
    platform,
    bundleId: bundleId || superseded?.bundleId,
    version,
    buildNumber,
    fileUrl,
    fileName,
    fileSize,
    notes: str("notes") || undefined,
    gitSha: str("gitSha") || undefined,
    branch: str("branch") || undefined,
    minOs: str("minOs") || undefined,
    urlScheme: str("urlScheme") || superseded?.urlScheme,
    iconUrl: str("iconUrl") || superseded?.iconUrl,
    profileName: str("profileName") || undefined,
    profileType: (str("profileType") || undefined) as Build["profileType"],
    profileExpiresAt: str("profileExpiresAt") || undefined,
    teamName: str("teamName") || undefined,
    provisionedUDIDs: Array.isArray(body.provisionedUDIDs)
      ? (body.provisionedUDIDs as string[]).filter((u) => typeof u === "string")
      : undefined,
    createdAt: new Date().toISOString(),
  };

  await putBuild(build);
  if (superseded) await deleteBuild(superseded.shareToken);

  // Deliberately awaited rather than fired and forgotten: a serverless function
  // can be frozen the moment it responds, which would drop the push. It never
  // throws, so a push failure cannot fail the upload.
  const notified = await notify({
    title: `${build.appName} ${build.version} (${build.buildNumber})`,
    body: build.notes?.trim() || "A new build is ready to install.",
    appSlug: build.appSlug,
    shareToken: build.shareToken,
    origin: req.nextUrl.origin,
  });

  return NextResponse.json({
    ok: true,
    replaced: Boolean(superseded),
    notified,
    installUrl: `${req.nextUrl.origin}/i/${build.shareToken}`,
  });
}

/**
 * The catalogue, for clients that are not a browser — the iOS app, a CI job,
 * anything scripted. Same bearer token as uploads, because one credential to
 * pair a phone with beats two.
 */
export async function GET(req: NextRequest) {
  if (!checkUploadToken(req.headers.get("authorization"))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  if (!storageReady()) {
    return NextResponse.json(
      { error: "storage is not configured: BLOB_READ_WRITE_TOKEN is not set on this deployment" },
      { status: 503 },
    );
  }

  const builds = await allBuilds();
  const slug = req.nextUrl.searchParams.get("app");
  const apps = groupIntoApps(slug ? builds.filter((b) => b.appSlug === slug) : builds);
  const origin = req.nextUrl.origin;

  return NextResponse.json(
    {
      apps: await Promise.all(apps.map(async (a) => ({
        slug: a.slug,
        name: a.name,
        platform: a.platform,
        bundleId: a.bundleId ?? null,
        iconUrl: a.builds.find((b) => b.iconUrl)?.iconUrl ?? null,
        builds: await Promise.all(a.builds.map(async (b) => ({
          shareToken: b.shareToken,
          version: b.version,
          buildNumber: b.buildNumber,
          fileName: b.fileName,
          fileSize: b.fileSize,
          notes: b.notes ?? null,
          gitSha: b.gitSha ?? null,
          branch: b.branch ?? null,
          minOs: b.minOs ?? null,
          urlScheme: b.urlScheme ?? null,
          iconUrl: b.iconUrl ?? null,
          userNote: await readNote(b.shareToken),
          profileType: b.profileType ?? null,
          profileExpiresAt: b.profileExpiresAt ?? null,
          deviceCount: b.provisionedUDIDs?.length ?? 0,
          createdAt: b.createdAt,
          installURL: `${origin}/i/${b.shareToken}`,
          // Handing the client a ready-made itms-services URL keeps the OTA
          // rules in one place rather than duplicated in every consumer.
          installDirectURL:
            b.platform === "ios"
              ? `itms-services://?action=download-manifest&url=${encodeURIComponent(
                  `${origin}/api/manifest/${b.shareToken}`,
                )}`
              : b.fileUrl,
        }))),
      }))),
    },
    { headers: { "Cache-Control": "no-store" } },
  );
}
