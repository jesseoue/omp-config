# omp-config

> **A highly optimized, batteries-included config for [omp](https://omp.sh) (Oh My Pi) · [OpenRouter](https://openrouter.ai) · [Context7](https://context7.com).** OpenRouter-only model gateway, curated model roles, automatic fallback chains, tuned thinking budgets, lazy MCP discovery, Context7 library-docs MCP, and a hardened one-step installer — one install, zero drift, maximum speed.

**Keywords:** omp config · Oh My Pi · OpenRouter gateway · Context7 MCP · AI agent config · LLM model routing · multi-agent coding · Claude · DeepSeek · Gemini · fallback chains · cost-aware routing · deployment protection · lazy tool discovery · snapcompact · throughput routing · low-latency · speed-optimized · adaptive thinking · open-weight frontier · toggleable frontier model · self-hostable LLM · one-step installer · idempotent install · hardened installer · dotfiles · developer tooling · coding agent · terminal AI · model roles · thinking budgets · context compaction · MCP server · library docs

---

## What this repo gives you

Everything below is **already wired in** — the installer symlinks it into `~/.omp/agent/` and the config is ready to run.

### 1. Model roles (`config.yml` → `modelRoles`)

Six roles, each with a purpose and a thinking suffix where it matters:

| Role | Model | Purpose |
|------|-------|---------|
| `default` | `anthropic/claude-sonnet-5` | General turns + main agent loop |
| `smol` | `deepseek/deepseek-v4-flash-0731` | Lightweight background tasks (titles, memory) |
| `slow` | `deepseek/deepseek-v4-pro-0813:high` *(toggleable)* | Hard problems, deep reasoning |
| `plan` | `deepseek/deepseek-v4-pro-0813` *(toggleable)* | Scoping + architecture |
| `vision` | `google/gemini-3.7-flash` | Image understanding |
| `advisor` | `anthropic/claude-sonnet-5:medium` | Second model that reviews each turn |

Plus a `cycleOrder` (`smol → default → slow`) for the model switcher.

> **Frontier reasoning is toggleable.** The `slow`/`plan` roles default to the
> **open-weight** `deepseek/deepseek-v4-pro-0813` (cheaper, self-hostable, near-Opus
> reasoning). Flip to the closed frontier `anthropic/claude-opus-5` by setting
> `FRONTIER_MODEL=opus` in `~/.omp/agent/.env` (or choose it during install).

### 2. Thinking budgets (`config.yml` → `thinkingBudgets`)

`defaultThinkingLevel: high`, with per-level token budgets from `minimal: 1024` up to `max: 32768`. Append a `:level` suffix to any role to override (`:minimal :low :medium :high :xhigh :max`).

### 3. Retry + fallback chains (`config.yml` → `retry`)

- `maxRetries: 10`, exponential backoff `500ms → 300s`
- `modelFallback: true` with `fallbackRevertPolicy: cooldown-expiry`
- **Per-role fallback chains** — if a model errors or rate-limits, omp steps down automatically instead of failing:
  - `default`: Sonnet → DeepSeek Pro → DeepSeek Flash
  - `slow`: DeepSeek Pro → Opus → Sonnet *(open-weight first; Opus as fallback)*
  - `plan`: DeepSeek Pro → Opus → Sonnet *(open-weight first; Opus as fallback)*
  - `smol`: Flash → Pro
  - `vision`: Gemini Flash → Sonnet

### 4. Tools + approvals (`config.yml` → `tools`)

- **Lazy MCP discovery** (`discoveryMode: mcp-only`) — discover MCP tools lazily to keep prompts small and tool calls fast
- `approvalMode: yolo` — no per-tool confirmation prompts
- `intentTracing: true`, `maxTimeout: 0` (no artificial cap)
- Built-in tools enabled: `bash`, `eval` (py+js), `lsp` (lazy, diagnostics-on-write), `edit` (hashline + fuzzy match), `read` (summarize), `grep`, `glob`, `fetch`, `web_search`, `browser`

### 4b. Message queue (`config.yml` → steering/follow-up/interrupt)

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

- `baseUrl: https://openrouter.ai/api/v1`, `api: openai-completions`
- API key read from `OPENROUTER_API_KEY` (never committed)
- **Performance routing** (`compat.openRouterRouting`):
  - `allowFallbacks: true` — provider failover retained
  - `sort.by: throughput` — prefer fast, healthy endpoints
  - `preferredMaxLatency.p90: 3` — target P90 latency
  - `preferredMinThroughput.p50: 50` — target P50 throughput
- **Per-model overrides** pin context windows, token caps, reasoning support, and provider routing (`only: [anthropic|deepseek]`):
  - `anthropic/claude-opus-5` — 1M ctx, 32k max, reasoning *(closed frontier — `FRONTIER_MODEL=opus`)*
  - `anthropic/claude-sonnet-5` — 1M ctx, 16k max, reasoning
  - `deepseek/deepseek-v4-pro-0813` — 1M ctx, 16k max, reasoning *(open-weight frontier — default)*
  - `deepseek/deepseek-v4-flash-0731` — 1.3M ctx, 8k max, no thinking (fast tool loops)
  - Optional alternates (commented): `anthropic/claude-opus-5-fast`, `anthropic/claude-sonnet-5-fast`, `openai/gpt-5.6-luna-pro`, `google/gemini-3.7-flash`

### 7. Context7 MCP (`mcp.json`)

A remote HTTP MCP server that gives omp **up-to-date library documentation** on demand (React, Next.js, Prisma, etc.) — so the agent never codes against stale docs.

- Endpoint: `https://mcp.context7.com/mcp`
- Auth: `CONTEXT7_API_KEY` header (read from `.env`)
- Optional but recommended — get a key at <https://context7.com/dashboard>

### 8. Environment template (`env.example`)

- `OPENROUTER_API_KEY` (required)
- `CONTEXT7_API_KEY` (recommended)
- `OPENROUTER_APP_TITLE` / `OPENROUTER_HTTP_REFERER` (attribution)
- Optional OpenRouter performance env vars (commented): `OPENROUTER_PROVIDER_SORT`, `OPENROUTER_PREFERRED_MAX_LATENCY_P90`, `OPENROUTER_PREFERRED_MIN_THROUGHPUT_P50`

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

### Flags

| Flag | Effect |
|------|--------|
| `--dir PATH` | Install/clone location (default: repo dir if local, else `~/omp-config`) |
| `--yes`, `-y` | Non-interactive — accept defaults, seed keys from env |
| `--skip-verify` | Skip the OpenRouter key HTTP check |
| `--help` | Usage |

Pre-seed keys without pasting:

```bash
OPENROUTER_API_KEY=sk-or-... CONTEXT7_API_KEY=ctx-... ./install.sh --yes
```

---

## What the installer does (cleanup + safety)

The installer is hardened and idempotent — safe to re-run any time. It:

- **Refuses root** and hardens `HOME`/`umask 077` for secret files
- **Never deletes omp sessions** (`~/.omp/sessions` is left untouched)
- **Backs up before replacing** — `config.yml`, `models.yml`, `mcp.json`, and `.env` are moved to `~/.omp/backups/` (timestamped, never overwritten) before being symlinked
- **Idempotent symlinks** — re-links only when the target changed; already-correct links are left alone
- **Preserves your `.env` values** — never clobbers existing keys; only adds *missing* keys from `env.example`
- **Safe `.env` writes** — awk-based key get/set (no `sed` injection; values may contain any characters)
- **Seeds keys from env** — imports `OPENROUTER_API_KEY` / `CONTEXT7_API_KEY` from the process environment if `.env` is empty
- **Verifies the OpenRouter key** — a real HTTP `200` check against the API (skippable)
- **Scrubs config strays** — removes runtime junk (`.DS_Store`) from the config dir
- **Logs everything** — timestamped log at `~/.omp/backups/logs/install-*.log` (rotated, latest symlinked)
- **`main()` wrapper** — the whole body runs inside `main()` so a truncated `curl | bash` can't half-execute

### Files managed

| File | Target | Notes |
|------|--------|-------|
| `config.yml` | `~/.omp/agent/config.yml` | symlinked |
| `models.yml` | `~/.omp/agent/models.yml` | symlinked |
| `mcp.json` | `~/.omp/agent/mcp.json` | symlinked |
| `env.example` | `~/.omp/agent/.env` | copied once (never overwritten) |

---

## Customizing

- **Change the default model** — edit `config.yml` → `modelRoles.default`.
- **Tune thinking** — append a `:level` suffix to any role value (`:minimal`, `:low`, `:medium`, `:high`, `:xhigh`, `:max`), or change `defaultThinkingLevel`.
- **Add a model** — add a `modelOverrides` entry in `models.yml` and reference it in a role or fallback chain.
- **Disable Context7** — remove `mcp.json` or set `CONTEXT7_API_KEY` empty.

---

## Security

- **Keys never live in this repo** — only `env.example` (empty values) is committed; `.env` is gitignored.
- `.env` is written `chmod 600`.
- The installer never logs key values (redacted in logs).
- Backups are stored under `~/.omp/backups/` with `umask 077`.