import { NextRequest, NextResponse } from "next/server";
import { checkUploadToken } from "@/lib/auth";
import { saveDevice, type Device } from "@/lib/apns";

export async function POST(req: NextRequest) {
  if (!checkUploadToken(req.headers.get("authorization"))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "body must be JSON" }, { status: 400 });
  }

  const token = typeof body.token === "string" ? body.token.trim() : "";
  const platform = body.platform === "macos" ? "macos" : "ios";
  const environment = body.environment === "sandbox" ? "sandbox" : "production";

  // APNs tokens are hex. Anything else would become a blob path, so reject it.
  if (!/^[0-9a-f]{64,200}$/i.test(token)) {
    return NextResponse.json({ error: "token must be hex" }, { status: 400 });
  }

  const bundleId = typeof body.topic === "string" ? body.topic.trim() : "";
  const device: Device = {
    token: token.toLowerCase(),
    platform,
    environment,
    // Which app this token belongs to. Without it one instance cannot notify
    // two different client apps: APNs addresses a push by app, not by server.
    topic: bundleId || undefined,
    registeredAt: new Date().toISOString(),
  };
  await saveDevice(device);

  return NextResponse.json({ ok: true });
}
