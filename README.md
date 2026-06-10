# claude-min-max

**Start your Claude 5-hour usage window on a schedule — automatically, even with your laptop closed.**

Claude Pro/Max usage resets on a **rolling 5-hour window**. The clock starts on your *first* message, not at a fixed time. So if you quickly check something at 7am, your window runs 7am–12pm and resets mid-afternoon — rarely lined up with your actual workday.

`claude-min-max` sends a tiny ping at the time(s) you pick (say **9:30am**), so your window starts *then*. Add a second ping (e.g. **2:30pm**) and you get two back-to-back windows covering 9:30am–7:30pm. You decide when the clock starts instead of stumbling into it.

It runs as a **GitHub Action**, so:

- ✅ It fires **even when your laptop is closed or off** (it's on GitHub's servers, not yours).
- ✅ It's **free** on public repos (unlimited Actions minutes).
- ✅ Setup is **one command and two browser approvals**.

> **This uses your subscription, not the API.** The ping runs Claude Code in headless mode authenticated with a Pro/Max token, so it counts against your *real* account window. The Anthropic API is pay-per-token and has no 5-hour window — pinging it would do nothing for this. You need a **Claude Pro or Max** plan.

---

## Install — one command (≈2 min)

The only prerequisite is the [GitHub CLI](https://cli.github.com) (`brew install gh`) and a **Claude Pro/Max** plan.

```bash
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | bash
```

You approve **two browser logins** — GitHub, then Claude — and the installer does everything else, with **no prompts and no local files**:

1. creates `your-username/claude-min-max` in your GitHub account,
2. mints your Claude subscription token, **verifies it authenticates**, and stores it as an encrypted repo secret,
3. auto-detects your timezone and schedules the daily **9:30am** ping,
4. fires a test run so you can see it work.

**Re-running it is safe** — it updates your existing setup instead of starting over. `ROTATE=1` forces a fresh token, `PING_TZ`/`REPO_NAME` override the detected timezone / repo name:

```bash
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | ROTATE=1 bash
```

## Changing the ping time

The ping time lives in one repo variable, **`PING_HOUR`** — change it any time, no re-install, no commit. It takes effect at the next half-hour check.

**Format:** 24-hour clock, whole or half hours only (`H` or `H:30`), comma-separated for multiple pings a day. Times are in your `PING_TZ` timezone.

| You want | Set `PING_HOUR` to |
|---|---|
| 9:30am (default) | `9:30` |
| 8am sharp | `8` |
| 9:30am + 2:30pm (back-to-back windows, 9:30am–7:30pm) | `9:30,14:30` |
| morning, afternoon, evening | `8,13,18` |

Pick whichever way is convenient:

```bash
# 1. One command with the GitHub CLI:
gh variable set PING_HOUR --repo your-username/claude-min-max --body "9:30,14:30"

# 2. Or re-run the installer with the override:
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | PING_HOUR=9:30,14:30 bash
```

**3. Or in the browser:** your repo → **Settings → Secrets and variables → Actions → Variables** → edit `PING_HOUR`.

To change the **timezone** instead, set `PING_TZ` the same way (any [IANA name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones), e.g. `Europe/Berlin`).

## Install — no terminal (web UI only)

You only need Claude Code locally to mint the token.

1. Click **“Use this template” → Create a new repository** (keep it **public** for free Actions minutes).
2. On your machine, run `claude setup-token`, log in with Pro/Max, and copy the `sk-ant-oat…` token.
3. In your new repo: **Settings → Secrets and variables → Actions → New repository secret** — name `CLAUDE_CODE_OAUTH_TOKEN`, value the token.
4. Same page, **Variables** tab — set `PING_TZ` and `PING_HOUR` (defaults: 9:30am Asia/Kolkata):

   | Variable      | Example              | Default        | Meaning |
   |---------------|----------------------|----------------|---------|
   | `PING_TZ`     | `Europe/Berlin`      | `Asia/Kolkata` | Your [IANA timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) |
   | `PING_HOUR`   | `9:30` or `8,14:30`  | `9:30`         | Time(s) to ping — `H` or `H:30`, 24h clock, comma-separated |
   | `PING_PROMPT` | `say hi`             | `Reply with only the single word ready` | What to send |
   | `PING_MODEL`  | `haiku`              | `haiku`        | Model for the ping (haiku = smallest footprint) |

5. **Test:** Actions tab → *Morning Claude Ping* → **Run workflow**.

---

## How it works

```
GitHub cron (every 30 min, UTC)
        │
        ▼
  Gate step ── is it PING_HOUR in PING_TZ right now? ── no ──▶ exit (a few seconds)
        │ yes
        ▼
  Install Claude Code (native installer)  →  claude -p "…" with your subscription token
        │
        ▼
  Your account's 5-hour window starts. ✓
```

The cron fires every 30 minutes, but the gate exits immediately unless the current half-hour matches one of your `PING_HOUR` times in your timezone. Resolving the timezone live means **DST and half-hour offsets (India, etc.) just work** — no UTC math, no twice-a-year edits.

The ping itself is a single Haiku turn (a few tokens) — a negligible slice of your window's budget.

---

## Notes & caveats

- **Timing is approximate.** GitHub's scheduled workflows are best-effort and can be delayed several minutes (occasionally longer) during peak load. Fine for "start my window around 8am"; not a second-accurate alarm.
- **Keep the repo active.** GitHub **disables scheduled workflows after 60 days with no commits.** A push every couple of months (or any commit) keeps it alive.
- **Public vs private.** Public repos get unlimited Actions minutes — recommended. On a **private** repo the 30-min cron uses ~48 short runs/day against your free minutes; if you care, switch to a single precise daily run (see below).
- **Your token is a credential.** It lives only in *your* repo's encrypted secrets and authenticates as your Claude account. Don't paste it anywhere else. Rotate it any time by re-running the installer with `ROTATE=1`.
- **No third-party actions.** The workflow uses zero marketplace actions — just GitHub's runner and the official Claude Code installer. Less supply chain to trust.
- **It's just normal usage.** A small scheduled message is ordinary product use — nothing exotic.

### Want one precise run/day instead of the 30-min gate? (good for private repos)

Replace the `schedule:` block in `.github/workflows/ping.yml` with a single UTC time and drop the gate. For **9:30am IST (UTC+5:30)** that's **4:00 UTC**:

```yaml
on:
  schedule:
    - cron: "0 4 * * *"   # 09:30 Asia/Kolkata — adjust for your timezone
  workflow_dispatch: {}
```

Trade-off: you compute UTC yourself and re-edit when *your* timezone changes for DST (India doesn't observe DST, so this is set-and-forget there).

---

## Alternatives for laptop-only setups

If you'd rather not use the cloud, you can schedule a local ping with `cron` (Linux) or `launchd` + `pmset` (macOS) running `claude -p "ready" --max-turns 1`. The catch: these **won't reliably fire with the lid closed / machine asleep** — which is exactly why this project defaults to GitHub Actions. An always-on box (Raspberry Pi, home server, cheap VPS) with a plain cron entry works great too.

---

## Publishing this so others can install it (maintainers)

The one-liner only works once this repo is **public** and marked as a **template**. The installer + README are already pointed at `PatrickJaiin/claude-min-max` (change that in `install.sh`'s `TEMPLATE=` line and the README if you fork under a different name). To publish:

```bash
# already committed locally; just publish it
gh repo create claude-min-max --public --source=. --push

# mark it a template (enables the green "Use this template" button)
gh repo edit --template
```

After that, anyone can install with the `curl … | bash` line above, and the repo itself can also be *your* running pinger — just run `./install.sh` in it to add your token.

## License

MIT — see [LICENSE](LICENSE).
