#!/usr/bin/env bash
#
# claude-min-max installer.
#
# Two ways to run it:
#   A) From anywhere (creates your repo from the template, then configures it):
#        curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | bash
#   B) From inside a clone of your pinger repo (just configures it):
#        ./install.sh
#
# It is safe to pipe into bash: all prompts read from /dev/tty, not stdin.
#
set -euo pipefail

# ─── MAINTAINER: set this to YOUR published template repo before sharing ───
#     (or callers can override it with:  TEMPLATE=me/claude-min-max bash install.sh )
TEMPLATE="${TEMPLATE:-PatrickJaiin/claude-min-max}"
# ───────────────────────────────────────────────────────────────────────────

TTY=/dev/tty
ask()       { local p="$1" d="${2:-}" v=""; printf '%s' "$p" >"$TTY"; read -r  v <"$TTY" || true; printf '%s' "${v:-$d}"; }
asksecret() { local p="$1"        v=""; printf '%s' "$p" >"$TTY"; read -rs v <"$TTY" || true; printf '\n' >"$TTY"; printf '%s' "$v"; }
confirm()   { local v; v=$(ask "$1" "Y"); [[ "$v" =~ ^[Yy] ]]; }
bold()      { printf '\033[1m%s\033[0m\n' "$*"; }
ok()        { printf '\033[32m✓\033[0m %s\n' "$*"; }
err()       { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; }

bold "claude-min-max installer"
echo

# 1. Required tools ----------------------------------------------------------
for c in gh git npm; do
  if ! command -v "$c" >/dev/null 2>&1; then
    err "'$c' is required but not installed."
    case "$c" in
      gh)  printf '  Install the GitHub CLI: https://cli.github.com  (macOS: brew install gh)\n' ;;
      git) printf '  Install git: https://git-scm.com\n' ;;
      npm) printf '  Install Node.js (includes npm): https://nodejs.org\n' ;;
    esac
    exit 1
  fi
done
ok "Found gh, git, npm"

# 2. GitHub auth -------------------------------------------------------------
gh auth status >/dev/null 2>&1 || gh auth login <"$TTY"
ok "GitHub authenticated"

# 3. Pick the target repo: configure this one, or create from template -------
if [ -f ".github/workflows/ping.yml" ]; then
  if ! repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); then
    err "This folder has the workflow but isn't pushed to GitHub yet. Publish it first:"
    printf '    git init && git add -A && git commit -m "init"\n'
    printf '    gh repo create claude-min-max --public --source=. --push\n'
    printf '  then re-run ./install.sh\n'
    exit 1
  fi
  ok "Configuring this repo: $repo"
else
  bold "Creating your pinger from template: $TEMPLATE"
  if [ "$TEMPLATE" = "OWNER/claude-min-max" ]; then
    err "Template not set. Re-run as:  TEMPLATE=<owner>/claude-min-max bash install.sh"
    exit 1
  fi
  name=$(ask "Name for your new repo [my-claude-pinger]: " "my-claude-pinger")
  gh repo create "$name" --template "$TEMPLATE" --public --clone
  cd "$name"
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
  ok "Created $repo"
fi

# 4. Claude Code + subscription token ----------------------------------------
command -v claude >/dev/null 2>&1 || { bold "Installing Claude Code…"; npm install -g @anthropic-ai/claude-code; }

echo
bold "Step 1/3 — Generate a Claude subscription token"
printf '  A browser opens. Log in with your Claude Pro/Max account and approve.\n'
printf '  It prints a token starting with sk-ant-oat… — copy it.\n'
ask "Press Enter to run 'claude setup-token'… " >/dev/null
claude setup-token <"$TTY" || { err "setup-token failed"; exit 1; }
token=$(asksecret "Paste the token (hidden), then Enter: ")
[ -n "$token" ] || { err "No token entered."; exit 1; }
printf '%s' "$token" | gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo "$repo"
ok "Stored secret CLAUDE_CODE_OAUTH_TOKEN"

# 5. Schedule ----------------------------------------------------------------
echo
bold "Step 2/3 — When should we ping you?"
tz=$(ask "Timezone [Asia/Kolkata]: " "Asia/Kolkata")
hours=$(ask "Hour(s) of day, 24h, comma-separated [8]: " "8")
gh variable set PING_TZ   --repo "$repo" --body "$tz"
gh variable set PING_HOUR --repo "$repo" --body "$hours"
ok "Will ping daily at ${hours}:00 (${tz})"

# 6. Test --------------------------------------------------------------------
echo
bold "Step 3/3 — Test it now?"
if confirm "Trigger a test ping? [Y/n]: "; then
  if gh workflow run ping.yml --repo "$repo"; then
    ok "Triggered. Watch it:  gh run watch --repo $repo   (or the Actions tab)"
  else
    err "Couldn't trigger — enable Actions under Settings → Actions → General, then retry."
  fi
fi

echo
ok "All set. Claude will ping on schedule — laptop open or not."
