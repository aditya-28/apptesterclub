/**
 * Shown instead of the catalogue when the instance is not finished being set
 * up. A fresh deployment with no storage attached used to throw a 500 from
 * inside the Blob SDK, which tells the operator nothing about what to do.
 */
export function Setup({ missing }: { missing: string[] }) {
  return (
    <div className="wrap" style={{ maxWidth: "32rem" }}>
      <header className="top">
        <p className="brand">
          AppTesterClub<span>.</span>
        </p>
        <span className="tag">Setup</span>
      </header>

      <h1>Almost there</h1>
      <p>
        This instance is running but not finished. Set the following on the
        deployment and redeploy.
      </p>

      <ul className="list">
        {missing.map((name) => (
          <li key={name}>
            <div className="card">
              <h2 className="mono">{name}</h2>
              <p className="meta">{HELP[name] ?? "Required."}</p>
            </div>
          </li>
        ))}
      </ul>

      <div className="notice">
        <strong>On Vercel:</strong> open the project, add a Blob store under
        Storage, then Settings &rsaquo; Environment Variables for the rest.
        Redeploy afterwards — environment changes do not apply to a running
        deployment.
      </div>

      <p className="meta" style={{ marginTop: "1.25rem" }}>
        Full instructions are in the{" "}
        <a href="https://github.com/aditya-28/apptesterclub#readme">README</a>.
      </p>
    </div>
  );
}

const HELP: Record<string, string> = {
  BLOB_READ_WRITE_TOKEN:
    "Where builds are stored. Create a Blob store on the project and Vercel sets this for you.",
  ATC_PASSWORD:
    "Password for these pages. The session cookie is signed with it, so changing it signs everyone out.",
  ATC_UPLOAD_TOKEN:
    "Bearer token the upload API and the phone app use. Generate one with: openssl rand -hex 24",
};
