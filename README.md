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
3. auto-detects your timezone, computes the exact UTC cron times for your daily **9:30am** ping, and commits them to the workflow,
4. fires a test run so you can see it work.

**Re-running it is safe** — it updates your existing setup instead of starting over. `ROTATE=1` forces a fresh token, `PING_TZ`/`REPO_NAME` override the detected timezone / repo name:

```bash
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | ROTATE=1 bash
```

## Changing the ping time

Re-run the installer with the time(s) you want — it recomputes the UTC crons and commits them for you:

```bash
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | PING_HOUR=9:30,14:30 bash
```

**Format:** 24-hour clock, any minute (`H` or `H:MM`), comma-separated for multiple pings a day. Times are in your local timezone (auto-detected; override with `PING_TZ=…`). Keep times at least 40 minutes apart — closer ones get swallowed by the retry-dedupe window.

| You want | Run with |
|---|---|
| 9:30am (default) | `PING_HOUR=9:30` |
| 8am sharp | `PING_HOUR=8` |
| 9:30am + 2:30pm (back-to-back windows, 9:30am–7:30pm) | `PING_HOUR=9:30,14:30` |
| morning, afternoon, evening | `PING_HOUR=8,13,18` |

**No terminal?** Edit the workflow in the browser instead: your repo → `.github/workflows/ping.yml` → ✏️ → change the `- cron:` lines between the `CRON-BEGIN`/`CRON-END` markers. Cron times are **UTC**, so subtract your UTC offset (9:30am IST − 5:30 = `"0 4 * * *"`); keep the second line 20 minutes later as the retry.

> Note: the `PING_TZ`/`PING_HOUR` repo *variables* are inputs the installer reads — editing them alone doesn't change the schedule; the committed cron lines are what GitHub runs.

## Install — no terminal (web UI only)

You only need Claude Code locally to mint the token.

1. Click **“Use this template” → Create a new repository** (keep it **public** for free Actions minutes).
2. On your machine, run `claude setup-token`, log in with Pro/Max, and copy the `sk-ant-oat…` token.
3. In your new repo: **Settings → Secrets and variables → Actions → New repository secret** — name `CLAUDE_CODE_OAUTH_TOKEN`, value the token.
4. The default schedule is **9:30am IST**. For a different time, edit `.github/workflows/ping.yml` in the browser — see [Changing the ping time](#changing-the-ping-time).
5. Optional tweaks, under **Settings → Secrets and variables → Actions → Variables**:

   | Variable      | Example  | Default        | Meaning |
   |---------------|----------|----------------|---------|
   | `PING_PROMPT` | `say hi` | `Reply with only the single word ready` | What to send |
   | `PING_MODEL`  | `haiku`  | `haiku`        | Model for the ping (haiku = smallest footprint) |

6. **Test:** Actions tab → *Morning Claude Ping* → **Run workflow**.

---

## How it works

```
GitHub cron at your exact ping time (UTC), ×2 — primary + a retry 20 min later
        │
        ▼
  Dedupe ── did a sibling run already ping in the last 40 min? ── yes ──▶ exit
        │ no
        ▼
  Install Claude Code (native installer)  →  claude -p "…" with your subscription token
        │
        ▼
  Your account's 5-hour window starts. ✓   (old no-op runs are auto-deleted)
```

GitHub's scheduled workflows are best-effort — firings can be delayed or occasionally dropped (high-frequency crons especially: an earlier version of this project polled every 30 minutes and **~85% of firings were silently dropped**). So the installer commits your exact UTC firing time plus a retry 20 minutes later; the dedupe step guarantees at most one real ping per slot, and a cleanup step deletes old no-op runs so the Actions tab only shows actual pings.

The ping itself is a single Haiku turn (a few tokens) — a negligible slice of your window's budget.

---

## Notes & caveats

- **Timing is approximate.** GitHub's scheduled workflows are best-effort and can be delayed several minutes (occasionally longer) during peak load. The built-in retry covers dropped firings; still, treat it as "start my window around 9:30", not a second-accurate alarm.
- **DST: re-run the installer after clock changes.** Cron times are fixed in UTC, computed from your timezone's offset *on install day*. If your timezone observes DST, your ping drifts by an hour when the clocks change — one installer re-run fixes it. (India has no DST: set-and-forget.)
- **Keep the repo active.** GitHub **disables scheduled workflows after 60 days with no commits.** Any commit resets the timer — re-running the installer with a schedule change counts.
- **Public vs private.** Public repos get unlimited Actions minutes — recommended. Even on a private repo, 2–4 one-minute runs/day is well within the free tier.
- **Your token is a credential.** It lives only in *your* repo's encrypted secrets and authenticates as your Claude account. Don't paste it anywhere else. Rotate it any time by re-running the installer with `ROTATE=1`.
- **No third-party actions.** The workflow uses zero marketplace actions — just GitHub's runner and the official Claude Code installer. Less supply chain to trust.
- **It's just normal usage.** A small scheduled message is ordinary product use — nothing exotic.

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
