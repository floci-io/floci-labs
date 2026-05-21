# S3 Photo Gallery

> A 60-line Node.js script that uploads a folder of images to local S3 and generates a static HTML gallery from them.

## What it shows

- Creating a bucket and uploading objects with the AWS SDK v3
- Listing bucket contents and building presigned URLs
- That you don't need a "real" cloud to prototype a photo-sharing flow

## Stack

- Node.js 20+
- `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`
- Floci S3

## Run it

Make sure Floci is running:

```bash
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:latest
```

Install deps and run:

```bash
npm install
node gallery.js ./photos
```

Open `gallery.html` in your browser. The images load directly from local S3 via presigned URLs.

## How it works

The script does three things:

1. **Creates a bucket** called `photo-gallery` (no-op if it already exists).
2. **Uploads every file** in the directory you pass as an argument.
3. **Generates `gallery.html`** with `<img>` tags pointing at presigned URLs that expire in an hour.

The interesting bit is the endpoint override:

```js
const s3 = new S3Client({
  endpoint: "http://localhost:4566",
  region: "us-east-1",
  credentials: { accessKeyId: "test", secretAccessKey: "test" },
  forcePathStyle: true,
});
```

That's the entire difference between this script and one that targets real AWS. Drop the `endpoint` line and it works against your real account.

## Try changing...

- Swap `forcePathStyle: true` for virtual-hosted-style with `localhost.floci.io` and see what changes.
- Add a `--public` flag that sets the bucket ACL to public-read and drops the presigning.
- Generate thumbnails with `sharp` before upload, store originals and thumbs under different prefixes.

## Author

[your-handle-here] — replace this when you submit a real lab.
