# Lab name

> One-sentence description of what this lab does.

## What it shows

A short paragraph or bullet list. What does this lab actually demonstrate? What AWS services does it touch? Why might someone read this?

## Stack

- Language / runtime:
- AWS services used: (e.g. S3, Lambda, SQS)
- Anything else worth knowing:

## Run it

Assumes Floci is running on `localhost:4566`. If not:

```bash
docker run -d --name floci -p 4566:4566 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  floci/floci:latest
```

Then:

```bash
# whatever commands run the lab
```

## How it works

Walk through the interesting bits. You don't need to explain every line — just the parts that taught you something or that you think are worth pointing out.

## Try changing...

Optional but encouraged: suggest a couple of things readers could tweak to learn more. Swap S3 for a different storage backend? Add a second consumer? Break it on purpose?

## Author

Your name / handle, link to your blog or socials if you want.
