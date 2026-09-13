import Link from "next/link";
import { redirect } from "next/navigation";
import { isSignedIn } from "@/lib/auth";
import { allBuilds, groupIntoApps, platformLabel, storageReady } from "@/lib/catalog";
import { Setup } from "./Setup";

export const dynamic = "force-dynamic";

export default async function Home() {
  const missing = [
    !process.env.ATC_PASSWORD && "ATC_PASSWORD",
    !process.env.ATC_UPLOAD_TOKEN && "ATC_UPLOAD_TOKEN",
    !storageReady() && "BLOB_READ_WRITE_TOKEN",
  ].filter(Boolean) as string[];
  // Checked before the sign-in redirect: without ATC_PASSWORD nobody can sign
  // in at all, so redirecting to a login they cannot pass is a dead end.
  if (missing.length) return <Setup missing={missing} />;

  if (!(await isSignedIn())) redirect("/login");

  const builds = await allBuilds();
  const apps = groupIntoApps(builds);

  return (
    <div className="wrap">
      <header className="top">
        <p className="brand">
          AppTesterClub<span>.</span>
        </p>
        <span className="meta">
          {builds.length} build{builds.length === 1 ? "" : "s"}
        </span>
      </header>

      <h1>Your builds</h1>
      <p>Open an app to get an install link. On iPhone, open that link on the phone itself.</p>

      {apps.length === 0 ? (
        <p className="empty">
          Nothing here yet. Push your first build with <span className="mono">atc push</span>.
        </p>
      ) : (
        <ul className="list">
          {apps.map((app) => {
            const latest = app.builds[0];
            return (
              <li key={app.slug}>
                <Link className="card" href={`/a/${app.slug}`}>
                  <div className="row">
                    <h2>{app.name}</h2>
                    <span className="tag">{platformLabel(app.platform)}</span>
                  </div>
                  <p className="meta">
                    <span className="mono">
                      {latest.version} ({latest.buildNumber})
                    </span>
                    {" · "}
                    {new Date(latest.createdAt).toLocaleDateString(undefined, {
                      day: "numeric",
                      month: "short",
                    })}
                    {" · "}
                    {app.builds.length} build{app.builds.length === 1 ? "" : "s"}
                  </p>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
