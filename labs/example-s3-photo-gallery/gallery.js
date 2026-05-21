// gallery.js — upload a folder of images to local S3 and generate an HTML gallery
import { readdirSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { extname, join, basename } from "node:path";
import {
  S3Client,
  CreateBucketCommand,
  PutObjectCommand,
  GetObjectCommand,
  ListObjectsV2Command,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const BUCKET = "photo-gallery";
const IMAGE_EXTS = new Set([".jpg", ".jpeg", ".png", ".gif", ".webp"]);

const s3 = new S3Client({
  endpoint: "http://localhost:4566",
  region: "us-east-1",
  credentials: { accessKeyId: "test", secretAccessKey: "test" },
  forcePathStyle: true,
});

const contentTypeFor = (ext) =>
  ({ ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
     ".gif": "image/gif", ".webp": "image/webp" }[ext.toLowerCase()] ?? "application/octet-stream");

async function ensureBucket() {
  try {
    await s3.send(new CreateBucketCommand({ Bucket: BUCKET }));
    console.log(`Created bucket: ${BUCKET}`);
  } catch (err) {
    if (err.name !== "BucketAlreadyOwnedByYou" && err.name !== "BucketAlreadyExists") throw err;
  }
}

async function uploadFolder(dir) {
  const entries = readdirSync(dir).filter(
    (f) => statSync(join(dir, f)).isFile() && IMAGE_EXTS.has(extname(f).toLowerCase())
  );
  for (const file of entries) {
    const body = readFileSync(join(dir, file));
    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: file,
      Body: body,
      ContentType: contentTypeFor(extname(file)),
    }));
    console.log(`Uploaded: ${file}`);
  }
  return entries;
}

async function buildGallery() {
  const list = await s3.send(new ListObjectsV2Command({ Bucket: BUCKET }));
  const items = list.Contents ?? [];
  const urls = await Promise.all(
    items.map((o) =>
      getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: o.Key }), { expiresIn: 3600 })
    )
  );
  const html = `<!doctype html>
<title>Floci Photo Gallery</title>
<style>
  body { font-family: system-ui; background: #0a0c10; color: #eee; padding: 2rem; }
  h1 { color: #e6ac00; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 1rem; }
  .grid img { width: 100%; height: 220px; object-fit: cover; border-radius: 8px; }
</style>
<h1>Photo Gallery</h1>
<p>${items.length} image(s), served from local S3 via presigned URLs.</p>
<div class="grid">
${urls.map((u, i) => `  <a href="${u}"><img src="${u}" alt="${basename(items[i].Key)}"></a>`).join("\n")}
</div>`;
  writeFileSync("gallery.html", html);
  console.log(`\nWrote gallery.html with ${items.length} image(s). Open it in your browser.`);
}

const dir = process.argv[2];
if (!dir) {
  console.error("Usage: node gallery.js <directory-of-images>");
  process.exit(1);
}

await ensureBucket();
await uploadFolder(dir);
await buildGallery();
