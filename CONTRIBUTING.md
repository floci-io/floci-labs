# Contributing to Floci Labs

Thanks for thinking about adding a lab. Here's the short version.

## The flow

1. Fork this repo.
2. Copy `labs/_template/` to `labs/your-lab-name/` (kebab-case).
3. Build your lab. Any language, any stack.
4. Fill in the README.
5. Open a PR.

## What we look for

- **It runs.** Someone with vanilla Floci (`docker run -p 4566:4566 floci/floci:latest`) should be able to follow your README and get it working in a few minutes.
- **It teaches something or is fun.** Both count. A clever hack is just as welcome as a polished tutorial.
- **It's yours.** No copying tutorials wholesale. Quoting or building on prior work is fine — just credit it.

## What we don't ask for

- Comprehensive docs. A short README is enough.
- Perfect code. Hacky is fine if it's honest about being hacky.
- A specific structure inside your lab folder. Organize it however makes sense.

## Things that will get a PR sent back

- **Doesn't run** against a stock `floci/floci:latest` container.
- **Real credentials** committed to the repo. Even fake-looking ones. Use `test`/`test`.
- **Harmful content** — malware demos, scraping people's personal data, that kind of thing.
- **A screenshot of the Floci landing page with no code.** (You'd be surprised.)

## Questions before you start?

Open a [Discussion](https://github.com/floci-io/floci/discussions) or ping the Slack at [floci.slack.com](https://floci.slack.com). "Is this a dumb idea for a lab?" is a fine thing to ask. The answer is almost always no.

## Licensing

By submitting a PR, you agree your lab is shared under the MIT License, same as Floci itself.
