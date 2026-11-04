# Contributing

> **Unofficial reference.** This tutorial is an unofficial reference, not official Liferay
> documentation, and is not supported by Liferay. See [learn.liferay.com](https://learn.liferay.com)
> for official documentation.

Thanks for helping improve this tutorial. Fixes to typos, broken steps, outdated screenshots and
code are all welcome, as are new chapters.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Contributions are
accepted under the [Apache License 2.0](LICENSE): anything you submit is licensed under the same terms.

## The one rule: verify against a running Liferay

Every endpoint, field name, permission and UI label in this tutorial has been checked against a running
Liferay DXP 2026.Q1 instance, not written from memory or older documentation. Please keep it that way:

- If you change a script or an API call, run it against the local instance (below) before opening a
  pull request.
- If you change a step in the docs, follow the step yourself.
- If you only have a hunch that something is wrong, open an issue instead. That is just as useful.

## Run everything locally

You need Docker, `curl` and `jq` (and Xcode for the iOS chapters).

```bash
cd liferay
docker compose up -d          # Liferay DXP 2026.Q1 on http://localhost:8080
./scripts/setup.sh            # object, permissions, users (safe to re-run)
./scripts/smoke-test.sh       # every API call the app uses, as the self-service users
```

If your change affects API responses, re-record the test fixtures and commit the result:

```bash
OAUTH_CLIENT_ID=id-xxxxxxxx ./scripts/record-fixtures.sh
```

`OAUTH_CLIENT_ID` is optional; it adds the OAuth error responses (see chapter 02, step 3).

## What CI checks

The [`Liferay`](.github/workflows/liferay.yml) workflow runs on every pull request:

| Job | Checks |
|---|---|
| Lint scripts and docs | `shellcheck -S style` on `liferay/scripts/`, valid JSON, relative Markdown links |
| Liferay API smoke test | Starts DXP 2026.Q1, runs `setup.sh` twice, runs `smoke-test.sh`, and fails if a recorded fixture's JSON shape no longer matches Liferay |

Run the same lint checks locally:

```bash
shellcheck -x -S style liferay/scripts/*.sh
python3 .github/scripts/check_md_links.py
```

## Style

- **Docs:** short sentences, one idea per step, and say *why* as well as *what*. Code and commands go
  in fenced blocks that run as written. Mark behaviour that surprised you with a **Gotcha** note.
- **Shell scripts:** `bash` with `set -euo pipefail`, idempotent where possible, and shellcheck-clean.
- **Swift:** Swift 6, no third-party dependencies, `async`/`await`, and no secrets in code. Client IDs
  and URLs belong in `ios/Config/Local.xcconfig`, which is git-ignored.
- **Never commit** credentials, activation keys, access or refresh tokens, or real customer data.

## Pull requests

1. Create a branch from `main`.
2. Keep each pull request focused on one change. If it changes a chapter, update that chapter's
   checkpoint too.
3. Fill in the pull request template, including how you verified the change.
4. Make sure CI is green.

## Reporting problems

Use the issue templates: **Tutorial problem** if a step doesn't work, **Improvement** for everything
else. For security issues, see [SECURITY.md](SECURITY.md); please don't open a public issue.
