import { SignJWT, importPKCS8 } from "jose";
import { list, put, del } from "@vercel/blob";
import http2 from "node:http2";

/**
 * Push, for "a new build just landed".
 *
 * AppTesterClub keeps its own device list rather than reading the pipeline server's,
 * so neither service depends on the other being up. The APNs auth key is a
 * team-wide credential, not another app's infrastructure, so sharing that one
 * is fine — it is the databases that stay separate.
 */

const PROD = "https://api.push.apple.com";
const SANDBOX = "https://api.sandbox.push.apple.com";
const PREFIX = "devices/";

export type Device = {
  token: string;
  platform: "ios" | "macos";
  environment: "sandbox" | "production";
  /** The bundle identifier of the app that owns this token.
   *
   *  APNs addresses a push by app, not by server, so one instance serving two
   *  different client apps cannot use a single topic — the wrong one comes back
   *  DeviceTokenNotForTopic. Older records have none and fall back to
   *  APNS_TOPIC. */
  topic?: string;
  registeredAt: string;
};

export function pushConfigured(): boolean {
  return Boolean(
    process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_PRIVATE_KEY,
  );
}

/**
 * APNs speaks HTTP/2 only and closes an HTTP/1.1 connection without a useful
 * error, which `fetch` gives no way around — it produced nothing but "fetch
 * failed", and because sends are caught and counted as failures, every push
 * silently reported zero devices. Hence the raw http2 client.
 */
function post(
  host: string,
  path: string,
  headers: Record<string, string>,
  body: string,
): Promise<{ status: number; reason?: string }> {
  return new Promise((resolve) => {
    const client = http2.connect(host);
    const done = (result: { status: number; reason?: string }) => {
      client.close();
      resolve(result);
    };
    client.on("error", (e) => done({ status: 0, reason: e.message }));

    const request = client.request({ ":method": "POST", ":path": path, ...headers });
    let status = 0;
    let payload = "";
    request.setTimeout(10_000, () => done({ status: 0, reason: "timeout" }));
    request.on("response", (h) => { status = Number(h[":status"] ?? 0); });
    request.on("data", (chunk) => { payload += chunk; });
    request.on("error", (e) => done({ status: 0, reason: e.message }));
    request.on("end", () => {
      let reason: string | undefined;
      try { reason = payload ? (JSON.parse(payload) as { reason?: string }).reason : undefined; } catch {}
      done({ status, reason });
    });
    request.end(body);
  });
}

export async function saveDevice(device: Device): Promise<void> {
  // One immutable record per token, same reasoning as the build catalogue: a
  // rewritten object is served stale from the CDN for a minute.
  await put(`${PREFIX}${device.token}.json`, JSON.stringify(device), {
    access: "public",
    contentType: "application/json",
    addRandomSuffix: false,
    allowOverwrite: true,
  });
}

export async function allDevices(): Promise<Device[]> {
  const { blobs } = await list({ prefix: PREFIX, limit: 1000 });
  const rows = await Promise.all(
    blobs.map(async (b) => {
      try {
        const res = await fetch(b.url, { cache: "no-store" });
        return res.ok ? ((await res.json()) as Device) : null;
      } catch {
        return null;
      }
    }),
  );
  return rows.filter((d): d is Device => d !== null);
}

let cached: { token: string; issuedAt: number } | null = null;

/** Apple rejects provider tokens refreshed more often than every 20 minutes and
 *  expires them at 60, so reuse inside that window. */
async function providerToken(): Promise<string> {
  const now = Date.now();
  if (cached && now - cached.issuedAt < 30 * 60_000) return cached.token;

  const key = await importPKCS8(process.env.APNS_PRIVATE_KEY!, "ES256");
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: process.env.APNS_KEY_ID! })
    .setIssuer(process.env.APNS_TEAM_ID!)
    .setIssuedAt()
    .sign(key);

  cached = { token, issuedAt: now };
  return token;
}

export type BuildPush = {
  title: string;
  body: string;
  appSlug: string;
  shareToken: string;
  /** Which instance sent it. A phone paired with two servers can hold the same
   *  app slug on both, so a tap needs this to land on the right one. */
  origin: string;
};

/** Returns how many devices accepted it. Never throws: a failed push must not
 *  fail the upload that triggered it. */
export async function notify(message: BuildPush): Promise<number> {
  if (!pushConfigured()) return 0;

  let jwt: string;
  try {
    jwt = await providerToken();
  } catch {
    return 0;
  }

  const body = JSON.stringify({
    aps: {
      alert: { title: message.title, body: message.body },
      sound: "default",
      "thread-id": message.appSlug,
    },
    app_slug: message.appSlug,
    share_token: message.shareToken,
    origin: message.origin,
  });

  const devices = await allDevices();
  const results = await Promise.all(
    devices.map(async (device) => {
      const topic = device.topic ?? process.env.APNS_TOPIC;
      if (!topic) return false;
      const host = device.environment === "sandbox" ? SANDBOX : PROD;
      const { status, reason } = await post(
        host,
        `/3/device/${device.token}`,
        {
          authorization: `bearer ${jwt}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "5",
        },
        body,
      );
      // A token Apple has retired is worth forgetting rather than retrying
      // forever on every upload.
      if (reason === "BadDeviceToken" || reason === "Unregistered") {
        await forgetDevice(device.token);
      }
      return status === 200;
    }),
  );
  return results.filter(Boolean).length;
}

/** Drops a token Apple has told us is dead. */
async function forgetDevice(token: string): Promise<void> {
  try {
    const { blobs } = await list({ prefix: `${PREFIX}${token}.json`, limit: 1 });
    if (blobs[0]) await del(blobs[0].url);
  } catch {
    // Best effort: a stale record costs one rejected push per upload.
  }
}
