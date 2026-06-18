# PolinRider Org-Wide Scanning — Setup

## 1. Create (or reuse) a `security-tools` repo in your org

This holds the canonical scanner and both workflow files, so every other
repo's pipeline pulls from one source of truth instead of copy-pasting the
script everywhere.

```
security-tools/
├── scripts/
│   └── polinrider-scanner.sh
└── .github/workflows/
    ├── polinrider-scan-reusable.yml
    └── polinrider-org-scan.yml
```

Put the three files from this folder into that structure and push to `main`.

## 2. Create the org-scan token

The central scan needs to read every repo in the org, which a single repo's
default `GITHUB_TOKEN` can't do.

- Settings → Developer settings → Personal access tokens (fine-grained or
  classic). Classic scopes needed: `repo`, `read:org`.
- Add it as an **org-level secret** named `ORG_SCAN_TOKEN`, available to all
  repos (or at least to `security-tools`).
- If your repos calling the reusable workflow are private and the script
  needs to be fetched via API (rather than checked out), also add
  `SECURITY_TOOLS_PAT` with `repo` read scope as an org secret — only needed
  if `security-tools` itself is private and other repos need to read its raw
  contents via the API call in the reusable workflow.

## 3. (Optional) Slack alerts

Add an org secret `SLACK_SECURITY_WEBHOOK` with an Incoming Webhook URL if
you want the daily scan to post to Slack when something's found.

## 4. Wire up each repo's own pipeline (blocks merge/deploy on infection)

In any repo, add a job that calls the reusable workflow and make your real
jobs depend on it:

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  malware-scan:
    uses: YOUR_ORG/security-tools/.github/workflows/polinrider-scan-reusable.yml@main

  build:
    needs: malware-scan   # won't run if the scan fails
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
```

Replace `YOUR_ORG` with your actual GitHub org/user name. Do this in each
repo's workflow file (or push it via a script across all repos — ask if you
want a script for that part too).

## 5. The central nightly scan

`polinrider-org-scan.yml` lives only in `security-tools`. It runs daily at
03:00 UTC (edit the cron line to change the schedule) and on manual trigger.
It lists every non-archived repo in the org, checks each one out, runs the
scanner, and posts a summary to the workflow's Job Summary tab. If anything
is infected, it fails and (if configured) posts to Slack.

You can trigger it manually any time from the Actions tab → "PolinRider
Org-Wide Scan" → "Run workflow".

## Notes

- The reusable workflow does a full checkout (`fetch-depth: 0`) so the
  reflog/git-log checks in the scanner are meaningful — shallow clones won't
  show amended-commit history.
- `continue-on-error: true` on the central scan's matrix job means one
  infected or broken repo won't stop the rest of the org from being scanned;
  the final `report` job still fails the overall run if anything was found.
- If your org has more repos than fit comfortably in one matrix run, GitHub
  Actions caps matrix jobs at 256 — for very large orgs you may need to
  shard the repo list across multiple workflow runs.
