#!/usr/bin/env bash
#
# claude-min-max installer — one command, two browser approvals, done.
#
#   curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | bash
#
# What it does, with no local files left behind:
#   1. creates <you>/claude-min-max in your GitHub account (from the template)
#   2. mints your Claude subscription token and stores it as an encrypted secret
#   3. detects your timezone, schedules the daily ping (8am by default)
#   4. fires a test run
#
# Re-running is safe — it updates your existing setup. Optional overrides:
#   curl -fsSL …/install.sh | PING_HOUR=8,13 bash      # change ping hour(s)
#   curl -fsSL …/install.sh | ROTATE=1 bash            # mint a fresh token
#   PING_TZ=Europe/Berlin, REPO_NAME=my-pinger, TEMPLATE=owner/repo also work.
#
# Safe to pipe into bash: anything interactive reads from /dev/tty, not stdin.
#
set -euo pipefail

TEMPLATE="${TEMPLATE:-PatrickJaiin/claude-min-max}"
REPO_NAME="${REPO_NAME:-claude-min-max}"
PING_HOUR="${PING_HOUR:-8}"

TTY=/dev/tty
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }
ask()  { local v=""; printf '%s' "$1" >"$TTY"; read -r v <"$TTY" || true; printf '%s' "${v:-${2:-}}"; }

TOKEN_TMP=""
trap '[ -n "$TOKEN_TMP" ] && rm -f "$TOKEN_TMP"' EXIT

bold "claude-min-max installer"
echo

# ── 1. The only hard dependency: the GitHub CLI ─────────────────────────────
if ! command -v gh >/dev/null 2>&1; then
  err "The GitHub CLI ('gh') is required: https://cli.github.com  (macOS: brew install gh)"
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  bold "GitHub login (browser will open)…"
  gh auth login <"$TTY" || { err "GitHub login failed."; exit 1; }
fi
ok "GitHub authenticated"

# ── 2. Your pinger repo: reuse it, or create it from the template ───────────
# No clone needed — everything below configures the repo remotely.
if [ -f ".github/workflows/ping.yml" ]; then
  # Running inside a pinger repo (e.g. a contributor's clone): configure this one.
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
    err "This folder isn't on GitHub yet. Publish it first:"
    printf '    gh repo create %s --public --source=. --push\n' "$REPO_NAME"
    exit 1
  }
  ok "Configuring this repo: $repo"
else
  user=$(gh api user -q .login)
  repo="$user/$REPO_NAME"
  if gh repo view "$repo" --json name >/dev/null 2>&1; then
    # Repo exists — make sure it's actually a pinger before touching it.
    if gh api "repos/$repo/contents/.github/workflows/ping.yml" >/dev/null 2>&1; then
      ok "Using your existing $repo"
    else
      err "$repo exists but isn't a claude-min-max pinger. Re-run with REPO_NAME=<something-else>."
      exit 1
    fi
  else
    gh repo create "$REPO_NAME" --template "$TEMPLATE" --public >/dev/null
    ok "Created $repo (public — free Actions minutes)"
  fi
fi

# ── 3. Claude subscription token → encrypted repo secret ────────────────────
# A bad bearer token always gets HTTP 401 from the API; any other status means
# the token is recognized. We verify BEFORE storing — a locally logged-in
# `claude` would silently use keychain credentials, so it can't be the check.
token_status() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 15 https://api.anthropic.com/v1/messages \
    -H "Authorization: Bearer $1" -H 'anthropic-beta: oauth-2025-04-20' \
    -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}' \
    2>/dev/null || printf '000'
}
valid_token() { [ -n "$1" ] && [ "$(token_status "$1")" != "401" ]; }

# Keep an existing token only if it has actually proven itself: the secret is
# write-only (can't be read back and re-validated), so the last run's verdict
# is the best signal. A token that never passed a run gets replaced.
have_secret=false
gh secret list --repo "$repo" 2>/dev/null | grep -q 'CLAUDE_CODE_OAUTH_TOKEN' && have_secret=true
last_run=$(gh run list --repo "$repo" --workflow=ping.yml --limit 1 --json conclusion -q '.[0].conclusion' 2>/dev/null || true)

if $have_secret && [ -z "${ROTATE:-}" ] && [ "$last_run" = "success" ]; then
  ok "Claude token already configured and working (re-run with ROTATE=1 to replace it)"
else
  if $have_secret && [ -z "${ROTATE:-}" ]; then
    bold "Existing token has never passed a test run — replacing it."
  fi
  if ! command -v claude >/dev/null 2>&1; then
    bold "Installing Claude Code…"
    curl -fsSL https://claude.ai/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
  fi
  echo
  bold "Claude login (browser will open) — approve with your Pro/Max account…"
  # Run setup-token under a pty so it stays fully interactive, while teeing its
  # output to a temp file. If the token prints cleanly we grab it ourselves and
  # the user never has to copy-paste anything.
  TOKEN_TMP=$(mktemp)
  if [ "$(uname)" = "Darwin" ]; then
    script -q "$TOKEN_TMP" claude setup-token <"$TTY" >"$TTY" 2>&1 || true
  else
    script -qec "claude setup-token" "$TOKEN_TMP" <"$TTY" >"$TTY" 2>&1 || true
  fi
  esc=$(printf '\033')
  clean=$(sed "s/${esc}\[[0-9;]*[A-Za-z]//g" "$TOKEN_TMP" | tr -d '\r')
  rm -f "$TOKEN_TMP"; TOKEN_TMP=""

  # Candidate tokens, most-complete first: everything joined (rescues tokens
  # hard-wrapped across lines by narrow terminals), per-line matches longest
  # first, and the clipboard. First one that authenticates wins.
  pat='sk-ant-oat[0-9]*-[A-Za-z0-9_-]{20,}'
  token=""
  candidates=$(
    printf '%s' "$clean" | tr -d '\n' | grep -oE "$pat" || true
    printf '%s' "$clean" | tr -d '[:space:]' | grep -oE "$pat" || true
    printf '%s\n' "$clean" | grep -oE "$pat" | awk '{print length, $0}' | sort -rn | cut -d' ' -f2- || true
    command -v pbpaste >/dev/null 2>&1 && pbpaste 2>/dev/null | grep -oE "$pat" || true
  )
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    if valid_token "$cand"; then token="$cand"; break; fi
  done <<EOF
$(printf '%s\n' "$candidates" | awk '!seen[$0]++')
EOF

  if [ -n "$token" ]; then
    ok "Token captured and verified"
  else
    # Couldn't capture a working token — fall back to manual paste, verified.
    tries=0
    while [ -z "$token" ] && [ "$tries" -lt 3 ]; do
      tries=$((tries + 1))
      printf 'Paste the sk-ant-oat… token (input hidden): ' >"$TTY"
      # Terminal copies often hard-wrap the token across lines (Claude Code's
      # TUI does). read stops at the first newline, so slurp the whole paste:
      # keep reading while more input arrives within a second, then strip all
      # whitespace. Wrapped, spaced, or multi-line pastes all come out clean.
      IFS= read -rs cand <"$TTY"
      while IFS= read -rs -t 1 extra <"$TTY"; do cand="$cand$extra"; done
      printf '\n' >"$TTY"
      cand=$(printf '%s' "$cand" | tr -d '[:space:]')
      if valid_token "$cand"; then
        token="$cand"; ok "Token verified"
      else
        err "That token didn't authenticate (401). If your terminal wrapped it, widen the window, re-copy, and try again."
      fi
    done
    [ -n "$token" ] || { err "Couldn't get a working token after 3 attempts."; exit 1; }
  fi
  printf '%s' "$token" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$repo"
  ok "Token stored as encrypted secret in $repo"
fi

# ── 4. Schedule: your timezone (auto-detected) + ping hour(s) ───────────────
tz="${PING_TZ:-}"
if [ -z "$tz" ] && [ -L /etc/localtime ]; then
  tz=$(readlink /etc/localtime | sed -E 's|.*/zoneinfo/||')
fi
if [ -z "$tz" ] && command -v timedatectl >/dev/null 2>&1; then
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
fi
[ -n "$tz" ] || tz=$(ask "Couldn't detect your timezone — enter it (e.g. Asia/Kolkata) [UTC]: " "UTC")
gh variable set PING_TZ   --repo "$repo" --body "$tz"
gh variable set PING_HOUR --repo "$repo" --body "$PING_HOUR"
ok "Daily ping at ${PING_HOUR}:00 ($tz)"

# ── 5. Fire a test run and wait for the verdict ─────────────────────────────
# (retries briefly: template copies are async)
triggered=false
for _ in 1 2 3 4 5; do
  if gh workflow run ping.yml --repo "$repo" >/dev/null 2>&1; then triggered=true; break; fi
  sleep 3
done
if $triggered; then
  bold "Test ping running (~30s)…"
  sleep 6
  run_id=$(gh run list --repo "$repo" --workflow=ping.yml --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  if [ -n "$run_id" ] && gh run watch "$run_id" --repo "$repo" --exit-status >/dev/null 2>&1; then
    ok "Test ping succeeded — checked end to end."
  else
    err "Test ping failed. Inspect it:  gh run view ${run_id:-<id>} --repo $repo --log-failed"
    exit 1
  fi
else
  err "Couldn't trigger the test run. Enable Actions (repo Settings → Actions) and run:"
  printf '    gh workflow run ping.yml --repo %s\n' "$repo"
fi

echo
ok "Done. Claude pings at ${PING_HOUR}:00 ($tz) every day — laptop open or not."
printf '  Change the schedule anytime:  gh variable set PING_HOUR --repo %s --body "8,13"\n' "$repo"
