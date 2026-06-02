# claude-min-max

**Start your Claude 5-hour usage window on a schedule — automatically, even with your laptop closed.**

Claude Pro/Max usage resets on a **rolling 5-hour window**. The clock starts on your *first* message, not at a fixed time. So if you quickly check something at 7am, your window runs 7am–12pm and resets mid-afternoon — rarely lined up with your actual workday.

`claude-min-max` sends a tiny ping at the time(s) you pick (say **8am**), so your window starts *then*. Add a second ping (e.g. **1pm**) and you get two back-to-back windows covering 8am–6pm. You decide when the clock starts instead of stumbling into it.

It runs as a **GitHub Action**, so:

- ✅ It fires **even when your laptop is closed or off** (it's on GitHub's servers, not yours).
- ✅ It's **free** on public repos (unlimited Actions minutes).
- ✅ Anyone can use it by **forking + adding one secret**.

> **This uses your subscription, not the API.** The ping runs Claude Code in headless mode authenticated with a Pro/Max token, so it counts against your *real* account window. The Anthropic API is pay-per-token and has no 5-hour window — pinging it would do nothing for this. You need a **Claude Pro or Max** plan.

---

## Install — the one-liner (≈2 min)

Needs the [GitHub CLI](https://cli.github.com) (`brew install gh`) and [Node.js](https://nodejs.org). It's safe to pipe into bash — every prompt reads from your terminal.

```bash
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/claude-min-max/main/install.sh | bash
```

The installer creates your own copy from the template, logs you into GitHub, generates a Claude token, stores it as a secret, asks for your timezone + hour, and fires a test run. Done.

### Or, step by step with the CLI

```bash
gh repo create my-claude-pinger --template PatrickJaiin/claude-min-max --public --clone
cd my-claude-pinger
./install.sh            # configures the repo you're in
```

## Install — no scripts (UI only)

No `gh` needed; you only run Claude Code locally to mint the token.

1. Click **“Use this template” → Create a new repository** (keep it **public** for free Actions minutes).
2. **Generate a token** on your machine:
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude setup-token          # log in with Pro/Max, copy the sk-ant-oat… token
   ```
3. **Add the secret:** your repo → **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `CLAUDE_CODE_OAUTH_TOKEN`
   - Value: the token you copied
4. **Set your schedule** (same page, **Variables** tab → New repository variable):

   | Variable      | Example         | Default        | Meaning |
   |---------------|-----------------|----------------|---------|
   | `PING_TZ`     | `Asia/Kolkata`  | `Asia/Kolkata` | Your [IANA timezone](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) |
   | `PING_HOUR`   | `8` or `8,13,18`| `8`            | Hour(s) to ping, 24h clock, comma-separated |
   | `PING_PROMPT` | `say hi`        | `Reply with only the single word: ready` | What to send |
   | `PING_MODEL`  | `haiku`         | `haiku`        | Model for the ping (haiku = smallest footprint) |

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
  Install Claude Code  →  claude -p "…" with your subscription token
        │
        ▼
  Your account's 5-hour window starts. ✓
```

The cron fires every 30 minutes, but the gate exits immediately unless it's your chosen hour in your timezone. Resolving the timezone live means **DST and half-hour offsets (India, etc.) just work** — no UTC math, no twice-a-year edits.

The ping itself is a single Haiku turn (a few tokens) — a negligible slice of your window's budget.

---

## Notes & caveats

- **Timing is approximate.** GitHub's scheduled workflows are best-effort and can be delayed several minutes (occasionally longer) during peak load. Fine for "start my window around 8am"; not a second-accurate alarm.
- **Keep the repo active.** GitHub **disables scheduled workflows after 60 days with no commits.** A push every couple of months (or any commit) keeps it alive.
- **Public vs private.** Public repos get unlimited Actions minutes — recommended. On a **private** repo the 30-min cron uses ~48 short runs/day against your free minutes; if you care, switch to a single precise daily run (see below).
- **Your token is a credential.** It lives only in *your* repo's encrypted secrets and authenticates as your Claude account. Don't paste it anywhere else. Revoke/rotate any time with `claude setup-token`.
- **It's just normal usage.** A small scheduled message is ordinary product use — nothing exotic.

### Want one precise run/day instead of the 30-min gate? (good for private repos)

Replace the `schedule:` block in `.github/workflows/ping.yml` with a single UTC time and drop the gate. For **8:00am IST (UTC+5:30)** that's **2:30 UTC**:

```yaml
on:
  schedule:
    - cron: "30 2 * * *"   # 08:00 Asia/Kolkata — adjust for your timezone
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
