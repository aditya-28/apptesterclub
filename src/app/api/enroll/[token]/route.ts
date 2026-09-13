import { NextRequest, NextResponse } from "next/server";
import { randomBytes, randomUUID } from "crypto";
import { put } from "@vercel/blob";
import { getBuild } from "@/lib/catalog";

/**
 * Device check, the way every distribution site does it.
 *
 * GET serves a "Profile Service" configuration profile. iOS installs it, asks
 * the user to confirm, then POSTs a signed plist back here carrying the device's
 * UDID. That is the only way to learn a UDID from the device itself — without
 * it, a tester needs a Mac and Finder.
 *
 * We use it to answer one question before the user taps Install: is this device
 * in the provisioning profile this build was signed with? If it is not, iOS
 * fails with no explanation at all, which is the single most confusing failure
 * in ad hoc distribution.
 */

export async function GET(
  req: NextRequest,
  ctx: { params: Promise<{ token: string }> },
) {
  const { token } = await ctx.params;
  const build = await getBuild(token);
  if (!build || build.platform !== "ios") {
    return new NextResponse("Not found", { status: 404 });
  }

  const origin = req.nextUrl.origin;
  const profile = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <dict>
    <key>URL</key>
    <string>${origin}/api/enroll/${token}</string>
    <key>DeviceAttributes</key>
    <array>
      <string>UDID</string>
      <string>PRODUCT</string>
      <string>VERSION</string>
      <string>DEVICE_NAME</string>
    </array>
  </dict>
  <key>PayloadOrganization</key>
  <string>AppTesterClub</string>
  <key>PayloadDisplayName</key>
  <string>AppTesterClub device check</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadUUID</key>
  <string>${randomUUID()}</string>
  <key>PayloadIdentifier</key>
  <string>club.apptester.enroll</string>
  <key>PayloadDescription</key>
  <string>Reports this device's identifier so AppTesterClub can tell you whether this build will install. Nothing is installed and the profile removes itself.</string>
  <key>PayloadType</key>
  <string>Profile Service</string>
</dict>
</plist>
`;

  return new NextResponse(profile, {
    headers: {
      // iOS only treats it as a profile with this exact type.
      "Content-Type": "application/x-apple-aspen-config",
      "Content-Disposition": 'attachment; filename="device-check.mobileconfig"',
      "Cache-Control": "no-store",
    },
  });
}

/** Pull a value out of the device's reply. The body is a CMS-signed blob with a
 *  plain XML plist inside it; extracting the XML avoids needing a full PKCS#7
 *  parser for four strings. */
function field(xml: string, key: string): string | undefined {
  const re = new RegExp(`<key>${key}</key>\\s*<string>([^<]*)</string>`);
  return xml.match(re)?.[1];
}

export async function POST(
  req: NextRequest,
  ctx: { params: Promise<{ token: string }> },
) {
  const { token } = await ctx.params;
  const build = await getBuild(token);
  if (!build) return new NextResponse("Not found", { status: 404 });

  const body = Buffer.from(await req.arrayBuffer()).toString("latin1");
  const start = body.indexOf("<?xml");
  const end = body.lastIndexOf("</plist>");
  const xml = start >= 0 && end > start ? body.slice(start, end + 8) : "";

  const udid = field(xml, "UDID");
  if (!udid) return new NextResponse("Could not read the device identifier", { status: 400 });

  const eligible = (build.provisionedUDIDs ?? []).includes(udid);

  // The result is keyed by a random nonce rather than carried in the URL, so a
  // device identifier never ends up in a query string, a log, or a referrer.
  const nonce = randomBytes(16).toString("hex");
  await put(
    `enroll/${nonce}.json`,
    JSON.stringify({
      udid,
      product: field(xml, "PRODUCT") ?? null,
      version: field(xml, "VERSION") ?? null,
      deviceName: field(xml, "DEVICE_NAME") ?? null,
      buildToken: token,
      eligible,
      checkedAt: new Date().toISOString(),
    }),
    { access: "public", contentType: "application/json", addRandomSuffix: false },
  );

  // iOS follows this redirect in Safari once the profile finishes.
  return NextResponse.redirect(`${req.nextUrl.origin}/checked/${nonce}`, { status: 302 });
}
