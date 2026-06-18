#!/bin/bash
#
# Bootstrap PolinRider scanning across every repo in a GitHub org.
#
# For each non-archived repo that does NOT already have a malware-scan
# workflow, this script commits .github/workflows/malware-scan.yml directly
# to the default branch, wiring it up to the reusable scanner in this repo.
#
# Prerequisites:
#   - gh CLI installed and authenticated (gh auth login)
#   - Token must have: repo (write), read:org
#
# Usage:
#   ./scripts/bootstrap-org-scanning.sh --org YOUR_ORG
#   ./scripts/bootstrap-org-scanning.sh --org YOUR_ORG --dry-run
#
# Exit codes:
#   0 - All repos processed (or nothing to do)
#   1 - One or more repos failed

set -uo pipefail

ORG=""
DRY_RUN=0
ADDED=0
SKIPPED=0
FAILED=0

while [ $# -gt 0 ]; do
  case "$1" in
    --org)   ORG="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h)
      echo "Usage: $0 --org ORG [--dry-run]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$ORG" ]; then
  echo "Error: --org is required" >&2
  echo "Usage: $0 --org YOUR_ORG [--dry-run]" >&2
  exit 1
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run mode — no changes will be made]"
fi

echo "Listing repos for org: $ORG ..."
repos=$(gh repo list "$ORG" \
  --limit 1000 \
  --no-archived \
  --json nameWithOwner \
  --jq '.[].nameWithOwner')

for repo in $repos; do
  # Never add a self-referential workflow to this repo
  if [ "$repo" = "$ORG/security-tools" ]; then
    echo "[SKIP] $repo (security-tools itself)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Skip repos that already have the workflow
  if gh api "repos/$repo/contents/.github/workflows/malware-scan.yml" \
       --silent 2>/dev/null; then
    echo "[SKIP] $repo (already has malware-scan.yml)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "[ADD]  $repo"

  if [ "$DRY_RUN" -eq 1 ]; then
    ADDED=$((ADDED + 1))
    continue
  fi

  default_branch=$(gh api "repos/$repo" --jq '.default_branch')

  workflow_content="name: Malware Scan

on:
  push:
  pull_request:

jobs:
  malware-scan:
    uses: ${ORG}/security-tools/.github/workflows/polinrider-scan-reusable.yml@main
    secrets: inherit
"

  encoded=$(printf '%s' "$workflow_content" | base64 | tr -d '\n')

  if gh api "repos/$repo/contents/.github/workflows/malware-scan.yml" \
       --method PUT \
       --field message="ci: add PolinRider malware scan" \
       --field "content=$encoded" \
       --field "branch=$default_branch" \
       --silent 2>/dev/null; then
    echo "       -> committed to $default_branch"
    ADDED=$((ADDED + 1))
  else
    echo "       -> FAILED (check permissions for $repo)" >&2
    FAILED=$((FAILED + 1))
  fi
done

echo ""
echo "Done. Added: $ADDED  Skipped: $SKIPPED  Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi
exit 0
