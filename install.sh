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
if [ -z "${ROTATE:-}" ] && gh secret list --repo "$repo" 2>/dev/null | grep -q 'CLAUDE_CODE_OAUTH_TOKEN'; then
  ok "Claude token already configured (re-run with ROTATE=1 to replace it)"
else
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
  token=$(sed "s/${esc}\[[0-9;]*[A-Za-z]//g" "$TOKEN_TMP" | tr -d '\r' \
          | grep -oE 'sk-ant-oat[0-9]*-[A-Za-z0-9_-]{20,}' | tail -1 || true)
  rm -f "$TOKEN_TMP"; TOKEN_TMP=""
  if [ -n "$token" ]; then
    ok "Token captured automatically"
  else
    # Couldn't read it cleanly (e.g. wrapped by a narrow terminal) — fall back.
    printf 'Paste the sk-ant-oat… token (input hidden): ' >"$TTY"
    read -rs token <"$TTY"; printf '\n' >"$TTY"
  fi
  case "$token" in
    sk-ant-oat*) ;;
    *) err "That doesn't look like a setup-token (should start with sk-ant-oat)."; exit 1 ;;
  esac
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

# ── 5. Fire a test run (retries briefly: template copies are async) ─────────
triggered=false
for _ in 1 2 3 4 5; do
  if gh workflow run ping.yml --repo "$repo" >/dev/null 2>&1; then triggered=true; break; fi
  sleep 3
done
if $triggered; then
  ok "Test ping triggered — watch it:  gh run watch --repo $repo"
else
  err "Couldn't trigger the test run. Enable Actions (repo Settings → Actions) and run:"
  printf '    gh workflow run ping.yml --repo %s\n' "$repo"
fi

echo
ok "Done. Claude pings at ${PING_HOUR}:00 ($tz) every day — laptop open or not."
printf '  Change the schedule anytime:  gh variable set PING_HOUR --repo %s --body "8,13"\n' "$repo"
