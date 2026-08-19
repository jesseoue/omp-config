# AGENTS.md

Instructions for AI agents and human contributors working in `omp-config`.

## Mission

This repository is a portable, production-oriented configuration for [omp (Oh My Pi)](https://omp.sh). It manages model roles, fallback behavior, provider routing, MCP integration, and a safe installer. Prefer small, evidence-based changes that improve reliability, latency, cost control, or agent ergonomics without weakening secret handling.

## Repository map

| Path | Responsibility |
| --- | --- |
| `config.yml` | Agent behavior, roles, retries, tools, context, LSP, and compaction |
| `models.yml` | OpenRouter transport, model metadata, and provider pins |
| `mcp.json` | Project MCP server configuration |
| `install.sh` | Installer and maintenance CLI (`doctor`, `fix`, `status`, `verify`, etc.) |
| `env.example` | Documented environment-variable template; never put real secrets here |
| `.github/workflows/ci.yml` | Shell, config, secret-scan, installer smoke, and scheduled endpoint checks |
| `README.md` | User-facing installation, architecture, troubleshooting, and rationale |
| `LICENSE` | MIT license |

## Operating rules

1. **Inspect before editing.** Read the relevant YAML, shell code, workflow, and README sections before making a change. Do not infer unsupported omp keys or model IDs.
2. **Keep credentials out of git.** Real keys belong in `~/.omp/agent/.env` or a local untracked `.env`. Never print, commit, paste, or include them in diagnostics, examples, screenshots, or test output.
3. **Preserve installer safety.** Do not remove root refusal, restrictive `umask`, backups, idempotency, session preservation, safe `.env` handling, or redaction without a documented security reason and tests.
4. **Treat model/provider facts as time-sensitive.** Before changing a model ID, price, context limit, endpoint pin, or availability claim, verify it against the current OpenRouter catalog/endpoints and update the date and README rationale.
5. **Keep routing intentional.** A fallback should be compatible with the role's purpose, quality expectations, modality, and budget. The `uncensored` role must not silently fall back to a model that defeats its purpose.
6. **Minimize diffs.** Prefer localized edits. Keep comments useful, factual, and consistent with actual behavior.
7. **Avoid hidden machine-specific state.** Do not commit generated files, `~/.omp` contents, logs, backups, symlink targets, or local editor metadata.
8. **Do not make network checks mandatory for ordinary local tests.** Use `--skip-verify` for offline smoke tests; reserve live endpoint checks for `verify`, scheduled CI, or explicit manual validation.

## Standard agent workflow

### 1. Understand the request

- Identify whether the change affects behavior, model routing, security, installation, documentation, or CI.
- Check `git status --short` before editing.
- Search for existing keys, commands, model names, and README claims before adding duplicates.
- If the request depends on external provider facts, perform a fresh verification first.

### 2. Make the smallest coherent change

- Update the source of truth, then update documentation and tests when behavior or user-visible commands change.
- For YAML, preserve valid indentation and quote values when parsing could be ambiguous.
- For `install.sh`, use existing helpers and preserve `set -euo pipefail` compatibility. Avoid Bash features newer than the script's supported environment unless justified.
- For CI, keep push/PR checks deterministic and put live network checks behind scheduled/manual conditions.

### 3. Validate locally

Run the checks relevant to the change. The full baseline is:

```bash
shellcheck -S warning install.sh
bash -n install.sh
python3 -m pip install --quiet pyyaml  # if PyYAML is unavailable
python3 - <<'PY'
import json
import yaml

config = yaml.safe_load(open("config.yml"))
models = yaml.safe_load(open("models.yml"))
assert config["modelRoles"]
assert config["retry"]["fallbackChains"]
assert models["providers"]["openrouter"]["modelOverrides"]
json.load(open("mcp.json"))
print("configs parse OK")
PY

# Installer smoke test without network checks.
TMP_HOME="$(mktemp -d)"
HOME="$TMP_HOME" bash install.sh --yes --skip-verify
HOME="$TMP_HOME" bash install.sh fix
HOME="$TMP_HOME" bash install.sh status
HOME="$TMP_HOME" bash install.sh uninstall --yes
rm -rf "$TMP_HOME"

git diff --check
git status --short
```

Never run the smoke test against a real home directory. Use a temporary `HOME` and verify that the command under test cannot touch the real `~/.omp` state.

### 4. Review the diff

Before handing off:

- Confirm only intended files changed.
- Check that comments match the implementation.
- Confirm no secrets, absolute local paths, generated artifacts, or stale claims were introduced.
- Report tests that passed and any checks intentionally skipped (especially live endpoint checks).

## Change recipes

### Changing a model or provider pin

1. Verify the model exists in omp's usable catalog, not only on OpenRouter.
2. Query the current OpenRouter model and endpoint data.
3. Confirm context window, output limit, reasoning/modality support, quantization, uptime, and provider availability.
4. Update `models.yml`, the relevant fallback chain in `config.yml`, and the matching README table/rationale.
5. Run parse, shell, smoke, and `git diff --check` validation. Run `bash install.sh verify --no-ai` only when live verification is intended.

### Changing installer behavior

1. Read the command parser, path safety checks, backup logic, and relevant command implementation.
2. Preserve idempotency and never delete sessions or user secrets.
3. Add or update a sandbox smoke assertion in `.github/workflows/ci.yml` when practical.
4. Test success, repeat execution, and safe failure paths with a temporary `HOME`.

### Changing agent behavior

1. Confirm the key is supported by the installed omp version/schema.
2. Explain the tradeoff in the nearby YAML comment and README if user-visible.
3. Consider latency, token use, fallback behavior, context survival, and tool-call correctness.
4. Avoid enabling expensive or network-dependent behavior without an explicit reason.

### Changing MCP configuration

1. Keep the server URL and environment-variable expansion explicit.
2. Use optional credentials in a way that degrades cleanly when absent.
3. Never hard-code API keys or send secrets to diagnostics.
4. Update README setup/troubleshooting instructions if the server or required key changes.

## Commit and handoff conventions

- Use a concise imperative commit subject, for example: `Document agent contribution workflow`.
- Keep unrelated cleanup out of feature changes.
- In the final handoff, summarize the behavior change, list files touched, cite validation commands, and call out live checks not run.
- Do not claim a provider is healthy or a remote check passed unless it was actually run.

## Quick commands

```bash
./install.sh help
./install.sh doctor --no-ai
./install.sh status
./install.sh verify --no-ai
./install.sh update
```

`doctor`, `fix`, `status`, `verify`, and `update` are maintenance commands. `install` is rate-limited by design; use `--force` only when an intentional reinstall is needed.
