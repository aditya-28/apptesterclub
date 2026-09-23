import { NextRequest, NextResponse } from "next/server";
import { getBuild, urlFor } from "@/lib/catalog";

/** XML has five characters that must never appear raw. A build name with an
 *  ampersand in it would otherwise produce a manifest iOS refuses to parse. */
function xml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

export async function GET(
  _req: NextRequest,
  ctx: { params: Promise<{ token: string }> },
) {
  const { token } = await ctx.params;
  const build = await getBuild(token);

  if (!build || build.platform !== "ios") {
    return new NextResponse("Not found", { status: 404 });
  }
  if (!build.bundleId) {
    return new NextResponse("Build has no bundle identifier", { status: 409 });
  }

  // Signed here rather than stored: a presigned URL expires, and the manifest
  // is fetched moments before the download, so each request gets a fresh one.
  const binary = await urlFor(build.fileKey, build.fileUrl);
  if (!binary) return new NextResponse("Build has no file", { status: 409 });

  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>${xml(binary)}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>${xml(build.bundleId)}</string>
        <key>bundle-version</key>
        <string>${xml(build.version)}</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>${xml(build.appName)}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
`;

  return new NextResponse(plist, {
    headers: {
      // Apple's install daemon wants XML and will not follow a redirect chain
      // that ends somewhere unexpected, so serve it directly.
      "Content-Type": "application/xml; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
