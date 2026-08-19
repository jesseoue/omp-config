# omp-config

> **A highly optimized, batteries-included config for [omp](https://omp.sh) (Oh My Pi) · [OpenRouter](https://openrouter.ai) · [Context7](https://context7.com).** OpenRouter-only model gateway, curated model roles, automatic fallback chains, tuned thinking budgets, health-verified provider pinning, Context7 library-docs MCP, and a hardened one-step installer — one install, zero drift, maximum speed.

**Keywords:** omp config · Oh My Pi · OpenRouter gateway · Context7 MCP · AI agent config · LLM model routing · multi-agent coding · Claude · DeepSeek · GLM · Z.ai · Gemini · Hermes 4 · uncensored model role · Exa web search · fallback chains · cost-aware routing · provider pinning · fp8 endpoints · lazy tool discovery · snapcompact · low-latency · speed-optimized · adaptive thinking · open-weight frontier · self-hostable LLM · one-step installer · idempotent install · hardened installer · AI-driven doctor · dotfiles · developer tooling · coding agent · terminal AI · model roles · thinking budgets · context compaction · MCP server · library docs

---

## What this repo gives you

Everything below is **already wired in** — the installer symlinks it into `~/.omp/agent/` and the config is ready to run. Every model ID, provider slug, and endpoint pin was verified against the **live OpenRouter catalog on 2026-08-19**.

### 1. Model roles (`config.yml` → `modelRoles`)

Ten pinned roles (plus `task`, deliberately left to inherit the session model):

| Role | Model | Purpose |
|------|-------|---------|
| `default` | `anthropic/claude-sonnet-5` | General turns + main agent loop ($2/$10 per M) |
| `smol` | `deepseek/deepseek-v4-flash-0731` | Background tasks — titles, memory (~$0.1/$0.2 per M) |
| `slow` | `deepseek/deepseek-v4-pro-0813:high` | Hard problems, deep reasoning ($1.32/$3.96 per M) |
| `plan` | `deepseek/deepseek-v4-pro-0813` | Scoping + architecture |
| `vision` | `google/gemini-3.7-flash` | Image/video/PDF understanding ($0.38/$1.88 per M) |
| `advisor` | `deepseek/deepseek-v4-pro-0813:low` | Second-opinion reviewer for each turn |
| `designer` | `anthropic/claude-sonnet-5` | Design/frontend work (vision + UI taste) |
| `commit` | `@smol` | Commit messages on the cheap model |
| `tiny` | `@smol` | Micro-tasks (classifiers, online titles) |
| `uncensored` | `nousresearch/hermes-4-70b` | Custom role: steerable, low-refusal writing + analysis ($0.13/$0.40 per M) |

Plus a `cycleOrder` (`smol → default → slow`) for the model switcher. The
`uncensored` role appears in the model picker as **Uncensored** (via
`modelTags`) and never falls back to an aligned frontier model that would
refuse the prompts the role exists for.

> **Why 70B and not the 405B flagship?** omp resolves models from its bundled
> catalog plus the models.dev feed, and `nousresearch/hermes-4-405b` is not
> materialized in omp's usable catalog — it errors with "Model not found".
> Hermes 4 **70B** is bundled, resolves
> deterministically, and was verified with a live completion. If omp's catalog
> picks up the 405B later, it's a one-line role swap. Prefer the Dolphin line?
> `cognitivecomputations/dolphin-mistral-24b-venice-edition` is a commented
> alternate in `models.yml` (also catalog-absent today — same caveat).

> **Why the advisor is not Sonnet:** the advisor reviews the default model's turns.
> A reviewer from a *different* model family catches mistakes a same-model reviewer
> rubber-stamps — and DeepSeek V4 Pro at `:low` costs less than running Sonnet twice.

> **Frontier reasoning is a one-line swap.** `slow`/`plan` default to the
> **open-weight** `deepseek/deepseek-v4-pro-0813` (near-Opus reasoning at ~1/6 the
> price, self-hostable). Prefer the closed frontier? Set both roles to
> `anthropic/claude-opus-5` in `config.yml` — it is already pinned in `models.yml`
> and wired as their first fallback.

### 2. Thinking budgets (`config.yml` → `thinkingBudgets`)

`defaultThinkingLevel: high`, with per-level token budgets from `minimal: 1024` up to `max: 32768`. Claude 5 models use adaptive effort levels; the budgets apply to budget-based models (DeepSeek, GLM). Append a `:level` suffix to any role to override (`:minimal :low :medium :high :xhigh :max`).

### 3. Retry + fallback chains (`config.yml` → `retry`)

- `maxRetries: 10`, exponential backoff `500ms → 300s`
- `modelFallback: true` with `fallbackRevertPolicy: cooldown-expiry`
- **Per-role fallback chains** — if a model errors or rate-limits, omp steps down automatically instead of failing. Every "DeepSeek V4 Pro" below is the pinned **0813 GA build** (`deepseek/deepseek-v4-pro-0813`) — the rolling un-suffixed alias is never used:
  - `default`: Sonnet 5 → DeepSeek V4 Pro 0813 → GLM 5.3 *(never below a real coding model)*
  - `slow` / `plan`: DeepSeek V4 Pro 0813 → Opus 5 → Sonnet 5
  - `advisor`: DeepSeek V4 Pro 0813 → Sonnet 5
  - `smol` / `commit` / `tiny`: DeepSeek Flash → Gemini 3.7 Flash *(background work never silently burns frontier money)*
  - `vision`: Gemini 3.7 Flash → Sonnet 5
  - `uncensored`: Hermes 4 70B only *(uncensored stays uncensored — it hard-fails rather than falling back to an aligned model)*
  - Any other role inherits the `default` chain.

### 4. Tools + approvals (`config.yml` → `tools`, `mcp`)

- `approvalMode: yolo` — no per-tool confirmation prompts
- `intentTracing: true`, `maxTimeout: 0` (no artificial cap)
- `bash.autoBackground` — commands running >60s (builds, test suites) are backgrounded automatically so the agent keeps working
- MCP: `enableProjectConfig: true` (project `.omp/mcp.json` respected), `renderMarkdownResults: true`; MCP tools are discovered on demand by omp's default behavior
- Built-in tools enabled: `bash`, `eval` (py+js), `lsp` (lazy, diagnostics-on-write), `edit` (hashline + fuzzy match), `read` (summarize), `grep`, `glob`, `fetch`, `web_search`, `browser`

### 4b. Web search (`config.yml` → `providers.webSearchOrder`)

The `web_search` tool is wired to real providers instead of omp's last-resort
scrapers (which get bot-challenged on shared IPs):

1. **Exa** — agent-grade search; works **keyless** out of the box via Exa's MCP
   fallback, and upgrades automatically when `EXA_API_KEY` is set in `.env`
2. **Startpage → Ecosia → DuckDuckGo** — credential-free backups, in order

No OAuth or extra accounts required; one optional env key upgrades quality.

### 4c. Message queue (`config.yml` → steering/follow-up/interrupt)

Keeps the agent focused and avoids racing tool calls for lower latency:

- `steeringMode: one-at-a-time` — drain steering messages serially
- `followUpMode: one-at-a-time` — drain follow-ups serially
- `interruptMode: immediate` — interrupts fire instantly

### 5. Context compaction (`config.yml` → `compaction`)

Tuned for long-running sessions without blowing the context window:

- `strategy: snapcompact`
- `reserveTokens: 16384` — headroom reserved for the model's reply
- `keepRecentTokens: 20000` — recent context always retained
- `autoContinue: true` — resume automatically after compaction
- `idleEnabled: false` — no idle compaction churn
- `midTurnEnabled: true`, `thresholdPercent: 80`, `remoteEnabled: true`

### 6. OpenRouter gateway (`models.yml` → `providers.openrouter`)

OpenRouter is the **only** provider — every model routes through it.

- `api: openai-completions` + `authHeader: true` — omp's built-in OpenRouter entry
  defaults to the OpenAI Responses API, which OpenRouter does not serve with
  bearer-key auth (requests 401 with "No cookie auth credentials found"). These
  two keys route every call to `/chat/completions` with a proper
  `Authorization: Bearer` header.
- API key read from `OPENROUTER_API_KEY` (never committed). omp sends OpenRouter
  prompt-cache and attribution headers on its own.
- **Health-verified provider pinning** (`compat.openRouterRouting.only`) — each
  model is pinned to full-precision, high-uptime endpoints (verified 2026-08-19):
  - `anthropic/claude-sonnet-5` — 1M ctx, 32K out → first-party `anthropic` *(workhorse)*
  - `anthropic/claude-opus-5` — 1M ctx, 32K out → first-party `anthropic` *(closed frontier)*
  - `deepseek/deepseek-v4-pro-0813` — 1M ctx, 64K out → fp8 hosts (`siliconflow fireworks novita parasail alibaba`); the native `deepseek` endpoint is deranked with 0% uptime, and fp4 quants are excluded
  - `deepseek/deepseek-v4-flash-0731` — 1M ctx, 16K out, thinking off → fp8 hosts (`deepinfra baseten novita siliconflow parasail`)
  - `google/gemini-3.7-flash` — 1M ctx, 16K out → first-party Google (`google-ai-studio`, `google-vertex`)
  - `z-ai/glm-5.3` — 1M ctx, 32K out, always-on reasoning → `z-ai` *(open-weight coding fallback)*
  - `nousresearch/hermes-4-70b` — 131K ctx, 32K out → `nebius` *(uncensored role, primary)*
  - Commented alternates, verified live: `anthropic/claude-opus-5-fast`, `openai/gpt-5.6-sol-pro`, `openai/gpt-5.6-luna-pro`, `x-ai/grok-4.20` (2M ctx), `moonshotai/kimi-k3`, `cognitivecomputations/dolphin-mistral-24b-venice-edition` *(uncensored alternate)*

### 7. Context7 MCP (`mcp.json`)

A remote HTTP MCP server that gives omp **up-to-date library documentation** on demand (React, Next.js, Prisma, etc.) — so the agent never codes against stale docs.

- Endpoint: `https://mcp.context7.com/mcp`
- Auth: `CONTEXT7_API_KEY` header, expanded from `.env` (`${CONTEXT7_API_KEY:-}` degrades cleanly to anonymous access when unset)
- Optional but recommended — get a key at <https://context7.com/dashboard>

### 8. Environment template (`env.example`)

- `OPENROUTER_API_KEY` (required)
- `CONTEXT7_API_KEY` (recommended)
- `EXA_API_KEY` (optional, commented) — upgrades web search; Exa already works keyless

That's the whole file — attribution headers, prompt caching, and provider routing are handled by omp and `models.yml`, so no other env vars are needed.

---

## Install

### Already cloned

```bash
./install.sh
```

### Fresh machine

```bash
curl -fsSL https://raw.githubusercontent.com/jesseoue/omp-config/main/install.sh | bash
```

### Maintenance CLI

`install.sh` doubles as a maintenance tool — all commands are idempotent and never touch your `.env` values or omp sessions:

| Command | What it does |
|---------|--------------|
| `./install.sh doctor` | Full health check: omp/bun/jq binaries, repo state, symlinks, key presence, `.env`/dir permissions, live key ping, **pinned-endpoint uptime** — and when problems are found, an **AI-written fix plan** (DeepSeek Flash via your own key, ~$0.0001; report is redacted, key values are never sent) |
| `./install.sh fix` | Auto-repair everything safe: relink dangling/wrong symlinks (with backup), `chmod 600` `.env` + `700` state dirs, add missing `.env` keys from the template, scrub strays |
| `./install.sh status` | One-screen status: links, keys (redacted), omp version, repo commit |
| `./install.sh verify` | Live OpenRouter key check + per-model pinned provider endpoint health |
| `./install.sh update` | `git pull --ff-only` + relink — bypasses the weekly rate limit |
| `./install.sh uninstall` | Remove the three symlinks only; keeps `.env`, sessions, backups |

### Flags

| Flag | Effect |
|------|--------|
| `--dir PATH` | Install/clone location (default: repo dir if local, else `~/omp-config`) |
| `--yes`, `-y` | Non-interactive — accept defaults, seed keys from env |
| `--skip-verify` | Skip network checks (key ping, endpoint health) |
| `--no-ai` | `doctor`/`verify`: skip the AI-generated fix plan |
| `--force` | `install`: bypass the once-per-week rate limit |
| `--help` | Usage |

Pre-seed keys without pasting:

```bash
OPENROUTER_API_KEY=sk-or-... CONTEXT7_API_KEY=ctx-... ./install.sh --yes
```

> Re-running `install` within 7 days of a successful install is a no-op (prints
> when the next run is allowed); pass `--force` to override. Maintenance
> commands (`doctor`, `fix`, `status`, `verify`, `update`) are never rate-limited.

---

## Known omp × OpenRouter issues this config works around

If you found this repo by searching one of these errors — yes, it's a real issue, and this config carries the fix:

1. **`401 — "No cookie auth credentials found"` on every request.** omp's built-in
   `openrouter` provider can dispatch through the OpenAI Responses API
   (`/api/v1/responses`), which OpenRouter does not serve with plain bearer-key
   auth, and the Authorization header is not attached for that transport. Fix
   (in `models.yml`): `api: openai-completions` + `authHeader: true`. The
   Responses path on OpenRouter is also broken upstream for tool calls — see
   [oh-my-pi#8020](https://github.com/can1357/oh-my-pi/issues/8020).
2. **DeepSeek requests failing or slow despite "12 providers".** The native
   `deepseek` endpoint on OpenRouter is deranked with **0% recent uptime**
   (verified 2026-08-19), and several third-party hosts serve fp4 quants with a
   truncated 262K context. Fix: pin `openRouterRouting.only` to healthy fp8
   full-context hosts (already done in `models.yml`); re-check any time with
   `./install.sh verify`.
3. **Provider routing isn't exposed in omp's Settings UI** — pinning must live in
   `models.yml` `compat.openRouterRouting` ([oh-my-pi#7209](https://github.com/can1357/oh-my-pi/issues/7209)).
   This repo is that file, kept healthy by CI.
4. **`Model "…" not found` for a model OpenRouter clearly serves.** omp only
   resolves models from its bundled catalog plus the models.dev feed;
   `modelOverrides` cannot conjure a missing one (e.g.
   `nousresearch/hermes-4-405b` — currently absent from omp's usable catalog).
   Pick a bundled sibling, or wait for
   omp/models.dev to carry it. Also prefer **provider-qualified selectors**
   (`openrouter/vendor/model`) everywhere — bare ids can silently shadow onto
   other providers ([oh-my-pi#8832](https://github.com/can1357/oh-my-pi/issues/8832));
   this config uses the qualified form throughout.

---

## What the installer does (cleanup + safety)

The installer is hardened and idempotent — safe to re-run any time. It:

- **Refuses root** and hardens `HOME`/`umask 077` for secret files
- **Never deletes omp sessions** (`~/.omp/sessions` is left untouched)
- **Rate-limits itself** — at most one install per week unless `--force`
- **Backs up before replacing** — `config.yml`, `models.yml`, `mcp.json`, and `.env` are moved to `~/.omp/backups/` (timestamped, never overwritten) before being symlinked
- **Idempotent symlinks** — re-links only when the target changed; already-correct links are left alone
- **Preserves your `.env` values** — never clobbers existing keys; only adds *missing* keys from `env.example`
- **Safe `.env` writes** — awk-based key get/set (no `sed` injection; values may contain any characters)
- **Seeds keys from env** — imports `OPENROUTER_API_KEY` / `CONTEXT7_API_KEY` from the process environment if `.env` is empty
- **Verifies the OpenRouter key** — a real HTTP `200` check against the API (skippable)
- **Scrubs config strays** — removes runtime junk (`.DS_Store`) from the config dir
- **Logs everything** — timestamped log at `~/.omp/backups/logs/install-*.log` (rotated, latest symlinked)
- **`main()` wrapper** — the whole body runs inside `main()` so a truncated `curl | bash` can't half-execute
- **Works on stock macOS bash 3.2** — no bash-4-isms, so `curl | bash` behaves on a fresh Mac

### CI (`.github/workflows/ci.yml`)

- **Every push/PR:** shellcheck + bash syntax + YAML/JSON structural validation + a full install → fix → status → uninstall smoke test in a sandbox `$HOME`
- **Weekly (and on demand):** `./install.sh verify` against the live OpenRouter endpoints API — if any pinned provider goes unhealthy, the scheduled run fails and GitHub notifies you before your agent starts erroring

### Files managed

| File | Target | Notes |
|------|--------|-------|
| `config.yml` | `~/.omp/agent/config.yml` | symlinked |
| `models.yml` | `~/.omp/agent/models.yml` | symlinked |
| `mcp.json` | `~/.omp/agent/mcp.json` | symlinked |
| `env.example` | `~/.omp/agent/.env` | copied once (never overwritten) |

> **Heads-up on drift:** when you change settings inside omp (or its setup
> wizard runs), omp saves back **through the symlink** — stripping comments and
> normalizing this repo's `config.yml`. That shows up as a dirty git diff:
> commit the parts you meant to change, or restore the curated file with
> `git checkout config.yml`. `./install.sh doctor` warns when the tree has
> drifted, and omp's `*.lock` strays are gitignored.

---

## Customizing

- **Change the default model** — edit `config.yml` → `modelRoles.default`.
- **Use Opus for deep reasoning** — set `modelRoles.slow` and `modelRoles.plan` to `anthropic/claude-opus-5` (already pinned in `models.yml`).
- **Tune thinking** — append a `:level` suffix to any role value (`:minimal`, `:low`, `:medium`, `:high`, `:xhigh`, `:max`), or change `defaultThinkingLevel`.
- **Add a model** — add a `modelOverrides` entry in `models.yml` (or uncomment an alternate) and reference it in a role or fallback chain.
- **Swap the uncensored model** — point `modelRoles.uncensored` at `nousresearch/hermes-4-70b` (cheaper) or uncomment the Dolphin Venice alternate in `models.yml`.
- **Add your own role** — any new key under `modelRoles` becomes a selectable role; give it a picker name/color under `modelTags`.
- **Re-verify endpoint health** — provider pins were checked 2026-08-19; re-check with `curl -s https://openrouter.ai/api/v1/models/<author>/<slug>/endpoints | jq`.
- **Disable Context7** — remove `mcp.json` or leave `CONTEXT7_API_KEY` empty.

---

## Security

- **Keys never live in this repo** — only `env.example` (empty values) is committed; `.env` is gitignored.
- `.env` is written `chmod 600`.
- The installer never logs key values (redacted in logs).
- Backups are stored under `~/.omp/backups/` with `umask 077`.
