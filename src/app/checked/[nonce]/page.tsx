import Link from "next/link";
import { notFound } from "next/navigation";
import { getObject } from "@/lib/storage";
import { getBuild } from "@/lib/catalog";

export const dynamic = "force-dynamic";

type Result = {
  udid: string;
  product: string | null;
  deviceName: string | null;
  version: string | null;
  buildToken: string;
  eligible: boolean;
};

async function readResult(nonce: string): Promise<Result | null> {
  if (!/^[0-9a-f]{32}$/.test(nonce)) return null;
  const raw = await getObject(`enroll/${nonce}.json`);
  if (!raw) return null;
  try {
    return JSON.parse(raw.toString()) as Result;
  } catch {
    return null;
  }
}

export default async function Checked({
  params,
}: {
  params: Promise<{ nonce: string }>;
}) {
  const { nonce } = await params;
  const result = await readResult(nonce);
  if (!result) notFound();

  const build = await getBuild(result.buildToken);

  return (
    <div className="wrap" style={{ maxWidth: "26rem" }}>
      <header className="top">
        <p className="brand">
          AppTesterClub<span>.</span>
        </p>
        <span className="tag">{result.eligible ? "Eligible" : "Not eligible"}</span>
      </header>

      <h1>{result.eligible ? "This device can install it" : "This device is not in the profile"}</h1>

      {result.eligible ? (
        <p>
          {result.deviceName ?? "This device"} is in the provisioning profile
          {build ? ` for ${build.appName} ${build.version}` : ""}. Go back and tap Install.
        </p>
      ) : (
        <p>
          iOS will refuse the install, and it will do so without telling you why. The
          device has to be registered and the build signed again before it will work.
        </p>
      )}

      <dl className="kv">
        {result.deviceName ? (
          <div>
            <dt>Device</dt>
            <dd>{result.deviceName}</dd>
          </div>
        ) : null}
        {result.product ? (
          <div>
            <dt>Model</dt>
            <dd className="mono">{result.product}</dd>
          </div>
        ) : null}
        {result.version ? (
          <div>
            <dt>iOS</dt>
            <dd className="mono">{result.version}</dd>
          </div>
        ) : null}
        <div>
          <dt>Identifier</dt>
          <dd className="mono">{result.udid}</dd>
        </div>
      </dl>

      {!result.eligible ? (
        <div className="notice">
          <strong>To fix it</strong>, register this identifier and re-sign:
          <p className="mono" style={{ marginTop: ".5rem", marginBottom: 0, fontSize: ".78rem" }}>
            asc devices create --udid {result.udid} --name &quot;{result.deviceName ?? "Device"}&quot; --platform IOS
          </p>
        </div>
      ) : null}

      <div style={{ marginTop: "1.5rem" }}>
        <Link className="btn" href={`/i/${result.buildToken}`}>
          Back to the build
        </Link>
      </div>

      <p className="meta" style={{ marginTop: "1.25rem" }}>
        The check profile does not stay on your device. Remove it any time from
        Settings &rsaquo; General &rsaquo; VPN &amp; Device Management.
      </p>
    </div>
  );
}
