import { cookies } from "next/headers";
import { createHmac, timingSafeEqual } from "crypto";

const COOKIE = "atc_session";

function secret(): string {
  return process.env.ATC_PASSWORD ?? "";
}

/** The cookie value is an HMAC of a fixed string under the password, so
 *  changing ATC_PASSWORD invalidates every existing session. */
export function sessionValue(): string {
  return createHmac("sha256", secret()).update("atc-v1").digest("hex");
}

export function constantTimeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

export async function isSignedIn(): Promise<boolean> {
  if (!secret()) return false;
  const jar = await cookies();
  const got = jar.get(COOKIE)?.value;
  if (!got) return false;
  return constantTimeEqual(got, sessionValue());
}

export const SESSION_COOKIE = COOKIE;

/** Uploads authenticate with a bearer token, not the browser session. */
export function checkUploadToken(header: string | null): boolean {
  const expected = process.env.ATC_UPLOAD_TOKEN;
  if (!expected) return false;
  const got = header?.replace(/^Bearer\s+/i, "") ?? "";
  if (!got) return false;
  return constantTimeEqual(got, expected);
}
