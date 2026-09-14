import { NextRequest, NextResponse } from "next/server";
import { randomUUID } from "crypto";
import { put, list } from "@vercel/blob";
import { checkUploadToken } from "@/lib/auth";
import { getBuild, storageReady } from "@/lib/catalog";

/**
 * Notes a person adds to a build after the fact — "crashes on launch", "this
 * is the one we showed the client".
 *
 * Append-only, one record per note, newest wins on read. Build records are
 * immutable for a reason: object storage serves a rewritten file from cache for
 * up to a minute, so an edited note would appear to revert. Writing a new
 * record every time keeps that property.
 */

const prefix = (token: string) => `notes/${token}/`;

export async function POST(
  req: NextRequest,
  ctx: { params: Promise<{ token: string }> },
) {
  if (!checkUploadToken(req.headers.get("authorization"))) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  if (!storageReady()) {
    return NextResponse.json({ error: "storage is not configured" }, { status: 503 });
  }

  const { token } = await ctx.params;
  if (!/^[0-9a-f]{32}$/.test(token)) {
    return NextResponse.json({ error: "not found" }, { status: 404 });
  }
  if (!(await getBuild(token))) {
    return NextResponse.json({ error: "no such build" }, { status: 404 });
  }

  let body: { text?: unknown };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "body must be JSON" }, { status: 400 });
  }

  const text = typeof body.text === "string" ? body.text.trim() : "";
  // 2000 is generous for a note and small enough that nobody can use this as
  // free storage.
  if (text.length > 2000) {
    return NextResponse.json({ error: "note is too long (2000 characters max)" }, { status: 400 });
  }

  await put(
    `${prefix(token)}${Date.now()}-${randomUUID()}.json`,
    JSON.stringify({ text, at: new Date().toISOString() }),
    { access: "public", contentType: "application/json", addRandomSuffix: false },
  );

  return NextResponse.json({ ok: true, text });
}

/** The newest note for one build, or null. Empty text means it was cleared. */
export async function readNote(token: string): Promise<string | null> {
  try {
    const { blobs } = await list({ prefix: prefix(token), limit: 1000 });
    if (blobs.length === 0) return null;
    // Filenames start with the timestamp, so lexical order is chronological.
    const newest = blobs.sort((a, b) => b.pathname.localeCompare(a.pathname))[0];
    const res = await fetch(newest.url, { cache: "no-store" });
    if (!res.ok) return null;
    const { text } = (await res.json()) as { text: string };
    return text || null;
  } catch {
    return null;
  }
}
