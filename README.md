# omp-config

An optimized, batteries-included configuration for [**omp**](https://omp.sh) (Oh My Pi) — the terminal-first AI coding agent — wired entirely through **OpenRouter**.

A single, opinionated setup tuned for real agentic coding work: a frontier reasoning model for planning, a fast workhorse for execution, and a cheap high-throughput model for tool loops — with automatic fallback chains so a provider outage never stalls your session.

## What's inside

| File | Purpose |
|------|---------|
| `config.yml` | Agent settings: model roles, thinking budgets, retry/fallback chains, compaction, tools |
| `models.yml` | OpenRouter provider overrides + per-model metadata (context, reasoning, routing) |
| `env.example` | Environment template (copy to `.env`, add your key) |
| `install.sh` | One-shot installer that symlinks everything into `~/.omp/agent/` |

## Model lineup

| Role | Model | Why |
|------|-------|-----|
| **default** | `anthropic/claude-sonnet-5` | Best coding-per-dollar; adaptive thinking, 1M context |
| **slow** | `anthropic/claude-opus-5:high` | Frontier reasoning for hard problems and deep debugging |
| **plan** | `anthropic/claude-opus-5` | Scoping and architecture |
| **smol** | `deepseek/deepseek-v4-flash-0731` | Near-zero cost, high throughput for background/tool-loop turns |
| **vision** | `google/gemini-3.7-flash` | Image understanding |
| **advisor** | `anthropic/claude-sonnet-5:medium` | Second model that reviews each turn |

Every role has a **fallback chain** (see `config.yml` → `retry.fallbackChains`), so if a model errors or rate-limits, omp automatically steps down to the next model instead of failing.

## Install

### 1. Install omp

```bash
curl -fsSL https://omp.sh/install | sh
```

### 2. Clone and link this config

```bash
git clone https://github.com/jesseoue/omp-config.git ~/omp-config
cd ~/omp-config
./install.sh
```

`install.sh` symlinks `config.yml` and `models.yml` into `~/.omp/agent/` (backing up anything already there).

### 3. Add your OpenRouter key

```bash
cp env.example ~/.omp/agent/.env
# edit ~/.omp/agent/.env and paste your key
```

Get a key at <https://openrouter.ai/keys>.

### 4. Run

```bash
omp
```

## Customizing

- **Change the default model** — edit `config.yml` → `modelRoles.default`.
- **Tune thinking** — append a `:level` suffix to any role value (`:minimal`, `:low`, `:medium`, `:high`, `:xhigh`, `:max`), or set `defaultThinkingLevel`.
- **Add a model** — add an entry under `models.yml` → `providers.openrouter.modelOverrides` (any OpenRouter model id works).
- **See every valid key** — run `omp config list`.

## Notes

- All model IDs are pinned to dated slugs (e.g. `deepseek-v4-flash-0731`) so behavior is reproducible; swap to `-latest` aliases if you prefer auto-updates.
- Keys never live in this repo — only `env.example` is committed.