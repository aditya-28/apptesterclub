import { redirect } from "next/navigation";
import { isSignedIn } from "@/lib/auth";

export const dynamic = "force-dynamic";

export default async function Login({
  searchParams,
}: {
  searchParams: Promise<{ bad?: string }>;
}) {
  if (await isSignedIn()) redirect("/");
  const { bad } = await searchParams;

  return (
    <div className="wrap" style={{ maxWidth: "22rem", paddingTop: "5rem" }}>
      <p className="eyebrow">AppTesterClub</p>
      <h1>Sign in</h1>
      <p>Builds are private. Enter the access password.</p>

      {bad ? <div className="err">That password did not match. Try again.</div> : null}

      <form action="/api/session" method="post">
        <input
          className="field"
          type="password"
          name="password"
          placeholder="Access password"
          autoComplete="current-password"
          autoFocus
          required
        />
        <button className="btn" type="submit">
          Sign in
        </button>
      </form>
    </div>
  );
}
