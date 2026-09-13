import { headers } from "next/headers";
import { notFound } from "next/navigation";
import QRCode from "qrcode";
import { getBuild, formatSize, platformLabel } from "@/lib/catalog";

export const dynamic = "force-dynamic";

function daysUntil(iso?: string): number | null {
  if (!iso) return null;
  const ms = new Date(iso).getTime() - Date.now();
  return Math.floor(ms / 86_400_000);
}

/** Deliberately public. The iOS install daemon fetches the manifest and the
 *  binary without cookies, so a session check here would break the one flow
 *  this page exists for. The 128-bit token is the access control. */
export default async function Install({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  const build = await getBuild(token);
  if (!build) notFound();

  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "";
  const proto = h.get("x-forwarded-proto") ?? "https";
  const origin = `${proto}://${host}`;
  const pageUrl = `${origin}/i/${token}`;

  const isIOS = build.platform === "ios";
  const manifestUrl = `${origin}/api/manifest/${token}`;
  const installHref = isIOS
    ? `itms-services://?action=download-manifest&url=${encodeURIComponent(manifestUrl)}`
    : build.fileUrl;

  const expiresIn = daysUntil(build.profileExpiresAt);
  const expired = expiresIn !== null && expiresIn < 0;
  const deviceCount = build.provisionedUDIDs?.length ?? 0;
  // An App Store or enterprise profile is not limited to a device list, so the
  // eligibility question only applies to development and ad hoc builds.
  const deviceLimited = build.profileType === "development" || build.profileType === "ad-hoc";

  const qr = await QRCode.toString(pageUrl, {
    type: "svg",
    margin: 1,
    errorCorrectionLevel: "M",
    color: { dark: "#000000", light: "#ffffff" },
  });

  return (
    <div className="wrap" style={{ maxWidth: "26rem" }}>
      <header className="top">
        <p className="brand">
          AppTesterClub<span>.</span>
        </p>
        <span className="tag">{platformLabel(build.platform)}</span>
      </header>

      <h1>{build.appName}</h1>
      <p className="mono meta" style={{ marginBottom: "1.4rem" }}>
        {build.version} ({build.buildNumber}) &middot; {formatSize(build.fileSize)}
      </p>

      {build.notes ? <p>{build.notes}</p> : null}

      {expired ? (
        <div className="err">
          <strong>This build&rsquo;s signing profile expired</strong>{" "}
          {Math.abs(expiresIn!)} days ago. iOS will refuse it. Re-sign and upload again.
        </div>
      ) : null}

      <a className="btn" href={installHref}>
        {isIOS
          ? "Install on this iPhone"
          : `Download ${build.fileName.split(".").pop()?.toUpperCase()}`}
      </a>

      {isIOS && deviceLimited ? (
        <>
          <div style={{ marginTop: ".6rem" }}>
            <a className="btn secondary" href={`/api/enroll/${token}`}>
              Will it work on this device?
            </a>
          </div>
          <div className="notice">
            <strong>Install failing with no message?</strong> That is what iOS does when
            the device is not in the signing profile. The check above asks your device
            for its identifier and tells you straight away. It installs a small
            configuration profile, reports nothing else, and does not stay.
          </div>
        </>
      ) : null}

      {isIOS && !deviceLimited && build.profileType ? (
        <div className="notice">
          Signed for <strong>{build.profileType}</strong> distribution, so it is not
          restricted to a device list.
        </div>
      ) : null}

      <div style={{ marginTop: "1.75rem", textAlign: "center" }}>
        <p className="eyebrow">Scan to open on a phone</p>
        <div
          style={{
            background: "#fff",
            padding: ".6rem",
            borderRadius: "10px",
            width: "11rem",
            margin: "0 auto",
          }}
          dangerouslySetInnerHTML={{ __html: qr }}
        />
      </div>

      <dl className="kv">
        <div>
          <dt>Uploaded</dt>
          <dd>{new Date(build.createdAt).toLocaleString()}</dd>
        </div>
        {build.profileType ? (
          <div>
            <dt>Signing</dt>
            <dd>{build.profileType}</dd>
          </div>
        ) : null}
        {build.profileExpiresAt ? (
          <div>
            <dt>Profile expires</dt>
            <dd>
              {new Date(build.profileExpiresAt).toLocaleDateString()}
              {expiresIn !== null && !expired ? ` · ${expiresIn} days` : ""}
            </dd>
          </div>
        ) : null}
        {deviceLimited ? (
          <div>
            <dt>Registered devices</dt>
            <dd>{deviceCount}</dd>
          </div>
        ) : null}
        {build.teamName ? (
          <div>
            <dt>Team</dt>
            <dd>{build.teamName}</dd>
          </div>
        ) : null}
        {build.branch ? (
          <div>
            <dt>Branch</dt>
            <dd className="mono">{build.branch}</dd>
          </div>
        ) : null}
        {build.gitSha ? (
          <div>
            <dt>Commit</dt>
            <dd className="mono">{build.gitSha.slice(0, 12)}</dd>
          </div>
        ) : null}
        {build.minOs ? (
          <div>
            <dt>Minimum OS</dt>
            <dd className="mono">{build.minOs}</dd>
          </div>
        ) : null}
        <div>
          <dt>File</dt>
          <dd className="mono">{build.fileName}</dd>
        </div>
      </dl>
    </div>
  );
}
