import { NextRequest, NextResponse } from "next/server";
import { SESSION_COOKIE, sessionValue, constantTimeEqual } from "@/lib/auth";

export async function POST(req: NextRequest) {
  const expected = process.env.ATC_PASSWORD;
  if (!expected) {
    return NextResponse.json({ error: "ATC_PASSWORD is not set" }, { status: 500 });
  }

  const form = await req.formData();
  const given = String(form.get("password") ?? "");

  if (!given || !constantTimeEqual(given, expected)) {
    return NextResponse.redirect(new URL("/login?bad=1", req.url), { status: 303 });
  }

  const res = NextResponse.redirect(new URL("/", req.url), { status: 303 });
  res.cookies.set(SESSION_COOKIE, sessionValue(), {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: 60 * 60 * 24 * 90,
  });
  return res;
}

export async function DELETE(req: NextRequest) {
  const res = NextResponse.json({ ok: true });
  res.cookies.delete(SESSION_COOKIE);
  return res;
}
