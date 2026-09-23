import { put, list, head, del } from "@vercel/blob";
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

/**
 * Where builds and their metadata live.
 *
 * Two backends behind one interface: Vercel Blob, and anything S3-compatible —
 * Cloudflare R2, MinIO, Backblaze, AWS. R2 is the reason this exists. Binaries
 * are the traffic in this product, an IPA gets re-downloaded on every install,
 * and R2 charges nothing for egress where Blob bills it.
 *
 * Which one is used is decided by configuration alone. Set the S3 variables and
 * it uses those; otherwise it falls back to Blob, so an existing deployment
 * keeps working untouched.
 */

export type StoredObject = {
  key: string;
  size: number;
  uploadedAt: string;
};

export type Backend = "s3" | "blob";

export function backend(): Backend {
  return process.env.S3_BUCKET && process.env.S3_ACCESS_KEY_ID ? "s3" : "blob";
}

export function storageReady(): boolean {
  return backend() === "s3"
    ? Boolean(process.env.S3_BUCKET && process.env.S3_ACCESS_KEY_ID && process.env.S3_SECRET_ACCESS_KEY && process.env.S3_ENDPOINT)
    : Boolean(process.env.BLOB_READ_WRITE_TOKEN);
}

let client: S3Client | null = null;
function s3(): S3Client {
  if (!client) {
    client = new S3Client({
      region: process.env.S3_REGION ?? "auto",
      endpoint: process.env.S3_ENDPOINT,
      credentials: {
        accessKeyId: process.env.S3_ACCESS_KEY_ID!,
        secretAccessKey: process.env.S3_SECRET_ACCESS_KEY!,
      },
    });
  }
  return client;
}

const bucket = () => process.env.S3_BUCKET!;

export async function putObject(
  key: string,
  body: Buffer | string,
  contentType: string,
): Promise<void> {
  if (backend() === "s3") {
    await s3().send(
      new PutObjectCommand({ Bucket: bucket(), Key: key, Body: body, ContentType: contentType }),
    );
    return;
  }
  await put(key, body, {
    access: "public",
    contentType,
    addRandomSuffix: false,
    allowOverwrite: true,
  });
}

/**
 * Reads an object's bytes.
 *
 * On S3 this is a direct GET, which is always current. The Blob path has to go
 * through the CDN, which serves a public object for up to a minute after it
 * changes — the reason build records are written once and never rewritten.
 */
export async function getObject(key: string): Promise<Buffer | null> {
  if (backend() === "s3") {
    try {
      const res = await s3().send(new GetObjectCommand({ Bucket: bucket(), Key: key }));
      const bytes = await res.Body?.transformToByteArray();
      return bytes ? Buffer.from(bytes) : null;
    } catch {
      return null;
    }
  }
  try {
    const meta = await head(key);
    const res = await fetch(meta.url, { cache: "no-store" });
    return res.ok ? Buffer.from(await res.arrayBuffer()) : null;
  } catch {
    return null;
  }
}

export async function listObjects(prefix: string): Promise<StoredObject[]> {
  if (backend() === "s3") {
    const out: StoredObject[] = [];
    let token: string | undefined;
    do {
      const res = await s3().send(
        new ListObjectsV2Command({ Bucket: bucket(), Prefix: prefix, ContinuationToken: token }),
      );
      for (const o of res.Contents ?? []) {
        if (!o.Key) continue;
        out.push({
          key: o.Key,
          size: o.Size ?? 0,
          uploadedAt: (o.LastModified ?? new Date()).toISOString(),
        });
      }
      token = res.IsTruncated ? res.NextContinuationToken : undefined;
    } while (token);
    return out;
  }
  const { blobs } = await list({ prefix, limit: 1000 });
  return blobs.map((b) => ({
    key: b.pathname,
    size: b.size ?? 0,
    uploadedAt: new Date(b.uploadedAt).toISOString(),
  }));
}

export async function deleteObject(key: string): Promise<void> {
  try {
    if (backend() === "s3") {
      await s3().send(new DeleteObjectCommand({ Bucket: bucket(), Key: key }));
      return;
    }
    const meta = await head(key);
    await del(meta.url);
  } catch {
    // Already gone is the outcome we wanted.
  }
}

/**
 * A URL a browser — or Apple's install daemon — can fetch without credentials.
 *
 * Presigned rather than public, because the daemon cannot authenticate and a
 * permanently public object means a leaked install link is a permanent
 * download. An hour is far longer than an install takes and short enough that a
 * copied URL stops working.
 *
 * `S3_PUBLIC_URL` overrides this for operators who have made the bucket public
 * and would rather serve straight from it.
 */
export async function readableUrl(key: string, seconds = 3600): Promise<string> {
  if (backend() === "s3") {
    const base = process.env.S3_PUBLIC_URL?.replace(/\/+$/, "");
    if (base) return `${base}/${key}`;
    return getSignedUrl(s3(), new GetObjectCommand({ Bucket: bucket(), Key: key }), {
      expiresIn: seconds,
    });
  }
  const meta = await head(key);
  return meta.url;
}
