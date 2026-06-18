# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A centralized security scanning toolkit for GitHub orgs, targeting the **PolinRider malware** — a supply-chain threat that appends obfuscated JS payloads to frontend config files (`postcss.config.mjs`, `tailwind.config.js`, etc.) and uses `temp_auto_push.bat` to amend and force-push infected commits.

The repo holds three files that other repos consume:

- [scripts/polinrider-scanner.sh](scripts/polinrider-scanner.sh) — the portable Bash scanner
- [.github/workflows/polinrider-scan-reusable.yml](.github/workflows/polinrider-scan-reusable.yml) — reusable workflow called from any repo's CI
- [.github/workflows/polinrider-org-scan.yml](.github/workflows/polinrider-org-scan.yml) — nightly org-wide scan (lives only in this repo)

## Running the scanner locally

```bash
# Scan current directory (finds all git repos under it)
./scripts/polinrider-scanner.sh

# Scan a specific directory tree
./scripts/polinrider-scanner.sh /path/to/projects

# Verbose + scan all .js files (not just known config files)
./scripts/polinrider-scanner.sh --verbose --js-all ~/projects
```

Exit codes: `0` = clean, `1` = infected, `2` = error.

## How the CI integration works

**Per-repo (blocks merge/deploy):** Other repos call the reusable workflow via `workflow_call`. The reusable workflow fetches the canonical scanner script from this repo at runtime using the `SECURITY_TOOLS_PAT` secret (needed only if this repo is private), then runs it against the checked-out repo.

**Org-wide nightly scan:** `polinrider-org-scan.yml` uses `ORG_SCAN_TOKEN` (classic PAT with `repo` + `read:org`) to list all non-archived org repos via `gh repo list`, checks each out in a matrix job, runs the scanner, and aggregates results. If infections are found, the workflow fails and optionally posts to Slack via `SLACK_SECURITY_WEBHOOK`.

## Required org secrets

| Secret | Where used | Scope |
|---|---|---|
| `ORG_SCAN_TOKEN` | Org-wide scan — list repos + checkout | classic PAT: `repo`, `read:org` |
| `SECURITY_TOOLS_PAT` | Reusable workflow — fetch scanner script | `repo` read (only if this repo is private) |
| `SLACK_SECURITY_WEBHOOK` | Org-wide scan — Slack alert on infection | Incoming Webhook URL |

## Scanner detection logic

The scanner checks for:
1. **Primary signature** `("rmcej%otb%",2857687)` in config files
2. **Secondary signature** `global['!']='8-270-2';var _$_1e42=` in config files
3. Presence of `temp_auto_push.bat` (propagation script)
4. Presence of `config.bat` (hidden orchestrator)
5. `config.bat` entry in `.gitignore`
6. Amended commits in git reflog (flagged only as a corroborating signal when other findings exist)

`CONFIG_FILES` is the hardcoded list of targeted config filenames; `--js-all` extends scanning to all `.js` files outside `node_modules/` and `.git/`.

## Wiring a new repo into CI

```yaml
jobs:
  malware-scan:
    uses: YOUR_ORG/security-tools/.github/workflows/polinrider-scan-reusable.yml@main

  build:
    needs: malware-scan   # blocked until scan passes
    ...
```

Replace `YOUR_ORG` with your actual GitHub org/username.
