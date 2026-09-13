import Link from "next/link";
import { redirect, notFound } from "next/navigation";
import { isSignedIn } from "@/lib/auth";
import { allBuilds, groupIntoApps, formatSize, platformLabel } from "@/lib/catalog";

export const dynamic = "force-dynamic";

export default async function AppBuilds({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  if (!(await isSignedIn())) redirect("/login");

  const { slug } = await params;
  const app = groupIntoApps(await allBuilds()).find((a) => a.slug === slug);
  if (!app) notFound();

  return (
    <div className="wrap">
      <header className="top">
        <p className="brand">
          AppTesterClub<span>.</span>
        </p>
        <span className="tag">{platformLabel(app.platform)}</span>
      </header>

      <Link className="back" href="/">
        &larr; All apps
      </Link>

      <h1>{app.name}</h1>
      {app.bundleId ? <p className="mono meta">{app.bundleId}</p> : null}

      <ul className="list">
        {app.builds.map((b, i) => (
          <li key={b.shareToken}>
            <Link className="card" href={`/i/${b.shareToken}`}>
              <div className="row">
                <h2 className="mono">
                  {b.version} ({b.buildNumber})
                </h2>
                {i === 0 ? <span className="tag latest">Latest</span> : null}
              </div>
              <p className="meta">
                {new Date(b.createdAt).toLocaleString(undefined, {
                  day: "numeric",
                  month: "short",
                  hour: "2-digit",
                  minute: "2-digit",
                })}
                {" · "}
                {formatSize(b.fileSize)}
                {b.branch ? ` · ${b.branch}` : ""}
                {b.gitSha ? ` · ${b.gitSha.slice(0, 7)}` : ""}
              </p>
              {b.notes ? <p className="meta">{b.notes}</p> : null}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
