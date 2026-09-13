import { headers } from "next/headers";
import { redirect } from "next/navigation";
import QRCode from "qrcode";
import { isSignedIn } from "@/lib/auth";

export const dynamic = "force-dynamic";

/**
 * Pairing code for the iOS app.
 *
 * Behind the admin password deliberately: the QR carries the upload token, so
 * anyone who can photograph this screen can push builds to this instance.
 */
export default async function Pair() {
  if (!(await isSignedIn())) redirect("/login");

  const token = process.env.ATC_UPLOAD_TOKEN;
  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "";
  const proto = h.get("x-forwarded-proto") ?? "https";
  const origin = `${proto}://${host}`;

  if (!token) {
    return (
      <div className="wrap" style={{ maxWidth: "26rem" }}>
        <h1>Pairing unavailable</h1>
        <p>
          Set <span className="mono">ATC_UPLOAD_TOKEN</span> on this deployment and reload.
        </p>
      </div>
    );
  }

  const link =
    `apptesterclub://pair?url=${encodeURIComponent(origin)}` +
    `&token=${encodeURIComponent(token)}` +
    `&name=${encodeURIComponent(host)}`;

  const qr = await QRCode.toString(link, {
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
      </header>

      <h1>Pair your phone</h1>
      <p>
        Open AppTesterClub on the phone, go to Settings, and tap{" "}
        <strong>Scan pairing code</strong>.
      </p>

      <div style={{ marginTop: "1.5rem", textAlign: "center" }}>
        <div
          style={{
            background: "#fff",
            padding: ".75rem",
            borderRadius: "12px",
            width: "15rem",
            margin: "0 auto",
          }}
          dangerouslySetInnerHTML={{ __html: qr }}
        />
      </div>

      <div className="notice">
        <strong>Treat this like a password.</strong> The code carries this
        instance&rsquo;s access token, so anyone who photographs the screen can read
        your builds and push new ones. Do not put it on a slide.
      </div>

      <p className="meta" style={{ marginTop: "1.25rem" }}>
        No app yet? Build it from <span className="mono">ios/</span> in the
        repository and sign it with your own Apple account. The README has the
        steps.
      </p>
    </div>
  );
}
