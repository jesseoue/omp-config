#!/usr/bin/env bash
# install.sh — 1-step omp-config installer
#
# Pinned, batteries-included config for omp (Oh My Pi) · OpenRouter · Context7.
#
# Preferred (already cloned):
#   ./install.sh [--dir PATH] [--yes] [--skip-verify]
#
# Fresh machine:
#   curl -fsSL https://raw.githubusercontent.com/jesseoue/omp-config/main/install.sh | bash
#
# Safety:
#   • Refuses root; umask 077 for secret files
#   • Never deletes omp sessions (~/.omp/sessions)
#   • Backs up config.yml/models.yml/mcp.json/.env before replacing
#   • Idempotent — safe to re-run; never clobbers your .env values
#   • Safe .env key writes (no sed injection)
#   • Migrates allowlisted keys from a previous config
#   • Scrubs runtime strays from the config dir
#   • main() wrapper so curl|bash cannot partial-execute mid-download
#
# After: add your key to ~/.omp/agent/.env, then run: omp

# Entire body lives in main() so a truncated curl|bash pipe cannot run half a script.
install_main() {
set -euo pipefail

umask 077
unset CDPATH 2>/dev/null || true
IFS=$' \t\n'

# ── Flags ─────────────────────────────────────────────────────────
INSTALL_DIR_FLAG=""
ASSUME_YES=false
SKIP_VERIFY=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir|--prefix)
      INSTALL_DIR_FLAG="${2:-}"
      [[ -n "$INSTALL_DIR_FLAG" ]] || { echo "fatal: $1 needs a path" >&2; exit 1; }
      shift 2
      ;;
    --yes|-y|--quick|-q) ASSUME_YES=true; shift ;;
    --skip-verify) SKIP_VERIFY=true; shift ;;
    -h|--help)
      cat <<'EOF'
install.sh — omp-config installer

  Pinned config for omp (Oh My Pi) · OpenRouter · Context7.

  ./install.sh [--dir PATH] [--yes] [--skip-verify]

  # Fresh machine:
  curl -fsSL https://raw.githubusercontent.com/jesseoue/omp-config/main/install.sh | bash

Flags:
  --dir PATH      install/clone location (default: repo dir if local, else ~/omp-config)
  --yes, -y       non-interactive: accept defaults, seed keys from env
  --skip-verify   skip the OpenRouter key HTTP check

Env (pre-seed keys, no paste needed):
  OPENROUTER_API_KEY  CONTEXT7_API_KEY

Safety: refuses root; never deletes sessions; backs up replaced configs.
After install: add your key to ~/.omp/agent/.env, then run: omp
EOF
      exit 0
      ;;
    *)
      echo "fatal: unknown flag: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

# ── Early HOME harden ─────────────────────────────────────────────
if [[ "$(id -u)" -eq 0 ]]; then
  echo "fatal: refuse to run as root — install as your normal user" >&2
  exit 1
fi
if [[ -z "${HOME:-}" || "$HOME" != /* ]]; then
  HOME="$(cd ~ 2>/dev/null && pwd -P)" || { echo "fatal: cannot resolve HOME" >&2; exit 1; }
fi
while [[ -n "$HOME" && "$HOME" == */ && "$HOME" != "/" ]]; do HOME="${HOME%/}"; done
[[ "$HOME" == "/" ]] && { echo "fatal: refusing HOME=/" >&2; exit 1; }
[[ -d "$HOME" ]] || { echo "fatal: HOME is not a directory: $HOME" >&2; exit 1; }
export HOME

# ── Logging ───────────────────────────────────────────────────────
LOG_DIR="${HOME}/.omp/backups/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S)-$$.log"
umask 077
{
  echo "# omp-config install log"
  echo "# started: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  echo "# host: $(uname -n 2>/dev/null || echo unknown)"
  echo "# user: $(id -un 2>/dev/null || echo unknown)"
  echo "# pid: $$"
  echo "# ----"
} >"$LOG_FILE"
chmod 600 "$LOG_FILE" 2>/dev/null || true
ln -sfn "$LOG_FILE" "${LOG_DIR}/install-latest.log" 2>/dev/null || true

_log_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
_log_strip() { printf '%s' "$*" | sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g'; }
_log() {
  local level="${1:-INFO}"; shift || true
  printf '%s [%s] %s\n' "$(_log_ts)" "$level" "$(_log_strip "$*")" >>"$LOG_FILE" 2>/dev/null || true
}
_log_section() { _log "----" "$*"; }
_install_exit_ec=0
_install_finish() {
  local ec="${_install_exit_ec:-0}"
  {
    echo "# ----"
    echo "# finished: $(_log_ts)"
    echo "# exit: $ec"
    echo "# log: $LOG_FILE"
  } >>"$LOG_FILE" 2>/dev/null || true
  # shellcheck disable=SC2012
  ls -1t "$LOG_DIR"/install-*.log 2>/dev/null | tail -n +31 | while IFS= read -r old; do
    rm -f "$old" 2>/dev/null || true
  done
}
trap '_install_exit_ec=$?; _install_finish' EXIT

# Colors only on TTY
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  c_g=$'\033[32m'; c_y=$'\033[33m'; c_r=$'\033[31m'; c_b=$'\033[36m'; c_p=$'\033[35m'
  c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_0=$'\033[0m'
else
  c_g=""; c_y=""; c_r=""; c_b=""; c_p=""; c_bold=""; c_dim=""; c_0=""
fi
ok(){ printf "  ${c_g}✓${c_0} %s\n" "$*"; _log "OK" "$*"; }
opt(){ printf "  ${c_y}⚠${c_0} %s\n" "$*"; _log "WARN" "$*"; }
bad(){ printf "  ${c_r}✗${c_0} %s\n" "$*"; _log "ERR" "$*"; }
info(){ printf "  ${c_b}•${c_0} %s\n" "$*"; _log "INFO" "$*"; }
die(){
  printf "  ${c_r}✗${c_0} %s\n" "$*" >&2
  _log "FATAL" "$*"
  _install_exit_ec=1
  exit 1
}

# ── Banner ────────────────────────────────────────────────────────
_install_banner() {
  printf '%b\n' "${c_b}${c_bold}"
  cat <<'ASCII'
   ___  __  __ ____    ____             __ _
  / _ \|  \/  |  _ \  / ___|___  _ __  / _(_) __ _
 | | | | |\/| | |_) | | |   / _ \| '_ \| |_| |/ _` |
 | |_| | |  | |  __/  | |__| (_) | | | |  _| | (_| |
  \___/|_|  |_|_|     \____\___/|_| |_|_| |_|\__, |
                                             |___/
ASCII
  printf '%b' "${c_0}"
  printf '  %bomp-config%b\n' "${c_p}" "${c_0}"
  printf '  %bPinned config for omp · OpenRouter · Context7%b\n\n' "${c_dim}" "${c_0}"
}

# ── Paths ─────────────────────────────────────────────────────────
AGENT_DIR="${OMP_AGENT_DIR:-$HOME/.omp/agent}"
BACKUP_ROOT="${HOME}/.omp/backups"
SESSIONS_DIR="${HOME}/.omp/sessions"

# Resolve source dir (repo checkout) vs install dir (clone target)
_script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  _script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || true)"
fi
if [[ -n "$INSTALL_DIR_FLAG" ]]; then
  INSTALL_DIR="$INSTALL_DIR_FLAG"
elif [[ -n "${OMP_CONFIG_DIR:-}" ]]; then
  INSTALL_DIR="$OMP_CONFIG_DIR"
elif [[ -n "$_script_dir" && -f "$_script_dir/config.yml" ]]; then
  INSTALL_DIR="$_script_dir"
else
  INSTALL_DIR="$HOME/omp-config"
fi
unset _script_dir
while [[ -n "$INSTALL_DIR" && "$INSTALL_DIR" == */ && "$INSTALL_DIR" != "/" ]]; do
  INSTALL_DIR="${INSTALL_DIR%/}"
done
[[ -z "$INSTALL_DIR" || "$INSTALL_DIR" == "/" ]] && die "refusing install dir ${INSTALL_DIR_FLAG:-/}"
[[ "$INSTALL_DIR" == /* ]] || INSTALL_DIR="$HOME/$INSTALL_DIR"
case "$INSTALL_DIR" in
  /|"$HOME"|"$HOME/.omp"|"$HOME/.omp"/*)
    die "refusing install dir $INSTALL_DIR (would clobber omp state)"
    ;;
esac

_install_banner
info "log → $LOG_FILE"
info "HOME=$HOME"
info "install → $INSTALL_DIR"
info "target → $AGENT_DIR"

# ── Prerequisites ─────────────────────────────────────────────────
_log_section "prerequisites"
missing=()
for c in curl git bash; do
  command -v "$c" >/dev/null 2>&1 || missing+=("$c")
done
[[ ${#missing[@]} -gt 0 ]] && die "missing required command(s): ${missing[*]}"
ok "required commands present (curl git bash)"

# ── 1. Clone or update repo ───────────────────────────────────────
_log_section "1. clone/update repo"
REPO_URL="https://github.com/jesseoue/omp-config.git"
clone_or_update() {
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Updating existing repo at $INSTALL_DIR..."
    local remote
    remote="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
    case "$remote" in
      *"jesseoue/omp-config"*) ;;
      "")
        opt "no git remote 'origin' — skipping pull"
        ;;
      *)
        die "refusing to pull: origin is '$remote' (expected …/jesseoue/omp-config)"
        ;;
    esac
    if [[ -n "$remote" ]]; then
      if git -C "$INSTALL_DIR" pull --ff-only 2>/dev/null; then
        ok "Repo updated (ff-only)"
      else
        opt "git pull skipped (local changes or offline) — using existing tree"
      fi
    else
      ok "Repo ready"
    fi
  elif [[ -f "$INSTALL_DIR/config.yml" ]]; then
    ok "Using existing checkout at $INSTALL_DIR (no .git)"
  elif [[ -e "$INSTALL_DIR" ]]; then
    if find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
      die "$INSTALL_DIR exists and is not an omp-config checkout — move it aside or set --dir"
    fi
    info "Cloning into empty directory $INSTALL_DIR..."
    git clone --depth 1 --branch main "$REPO_URL" "$INSTALL_DIR"
    ok "Repo cloned"
  else
    info "Cloning to $INSTALL_DIR..."
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth 1 --branch main "$REPO_URL" "$INSTALL_DIR"
    ok "Repo cloned"
  fi
}
clone_or_update

[[ -f "$INSTALL_DIR/config.yml" ]] || die "missing config.yml in $INSTALL_DIR — aborting"
[[ -f "$INSTALL_DIR/models.yml" ]] || die "missing models.yml in $INSTALL_DIR — aborting"
[[ -f "$INSTALL_DIR/mcp.json" ]] || die "missing mcp.json in $INSTALL_DIR — aborting"
echo ""

# ── 2. Sessions: never touch ──────────────────────────────────────
_log_section "2. sessions"
if [[ -d "$SESSIONS_DIR" ]]; then
  info "Leaving omp sessions intact at $SESSIONS_DIR (never deleted by installer)"
else
  info "No existing sessions dir yet (created by omp on first run)"
fi
echo ""

# ── 3. Config symlinks (backup real files; never rm sessions) ─────
_log_section "3. config symlinks"
mkdir -p "$AGENT_DIR" "$BACKUP_ROOT"

backup_path() {
  local src="$1" kind="$2" ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local dst="${BACKUP_ROOT}/${kind}-${ts}"
  local n=1
  while [[ -e "$dst" ]]; do
    dst="${BACKUP_ROOT}/${kind}-${ts}-${n}"
    n=$((n + 1))
  done
  mv "$src" "$dst"
  printf '%s' "$dst"
}

link_config() {
  local src="$1" dst="$2" label="$3"
  if [[ -L "$dst" ]]; then
    local cur
    cur="$(readlink "$dst" 2>/dev/null || true)"
    if [[ "$cur" == "$src" ]]; then
      ok "$label already linked"
      return 0
    fi
    # Wrong target — back up the link itself (not the target)
    local bp
    bp="$(backup_path "$dst" "$label")"
    ln -sfn "$src" "$dst"
    ok "$label relinked (old link backed up → $bp)"
    _log "INFO" "$label backup=$bp"
  elif [[ -e "$dst" ]]; then
    local bp
    bp="$(backup_path "$dst" "$label")"
    ln -sfn "$src" "$dst"
    ok "$label linked (previous backed up → $bp)"
    _log "INFO" "$label backup=$bp"
  else
    ln -sfn "$src" "$dst"
    ok "$label linked"
  fi
}

for f in config.yml models.yml mcp.json; do
  link_config "$INSTALL_DIR/$f" "$AGENT_DIR/$f" "$f"
done
echo ""

# ── 4. .env + key setup ───────────────────────────────────────────
_log_section "4. env keys"
ENV_FILE="$AGENT_DIR/.env"

# Safe .env key get/set (no sed injection; values may contain any chars)
env_get_key() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/,""); print; exit }' "$file"
}
env_set_key() {
  local file="$1" key="$2" val="$3"
  if [[ -f "$file" ]] && grep -qE "^${key}=" "$file" 2>/dev/null; then
    # Replace in place via awk (safe for special chars)
    awk -v k="$key" -v v="$val" '
      $1 == k { print k "=" v; next }
      { print }
    ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
  fi
  chmod 600 "$file" 2>/dev/null || true
}
env_set_if_unset() {
  local file="$1" key="$2" val="$3"
  if [[ -f "$file" ]] && grep -qE "^${key}=" "$file" 2>/dev/null; then
    printf 'preserved'
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
    chmod 600 "$file" 2>/dev/null || true
    printf 'set'
  fi
}

# Create .env from template if missing; otherwise leave untouched
if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$INSTALL_DIR/env.example" ]]; then
    cp "$INSTALL_DIR/env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    ok ".env created from template"
  else
    opt "no env.example found — creating empty .env"
    : >"$ENV_FILE"
    chmod 600 "$ENV_FILE"
  fi
else
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  ok ".env already exists — values preserved"
fi

# Upgrade path: add any new keys from env.example without clobbering values
if [[ -f "$INSTALL_DIR/env.example" ]]; then
  merged=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    key="${line%%=*}"
    key="${key#"${key%%[![:space:]]*}"}"   # trim leading
    key="${key%"${key##*[![:space:]]}"}"   # trim trailing
    [[ -n "$key" ]] || continue
    # Skip commented-out optional keys (start with #)
    if ! grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
      # Only add keys that are active (not commented) in the example
      if grep -qE "^${key}=" "$INSTALL_DIR/env.example" 2>/dev/null; then
        printf '%s=\n' "$key" >>"$ENV_FILE"
        merged="${merged}${merged:+ }${key}"
      fi
    fi
  done <"$INSTALL_DIR/env.example"
  [[ -n "$merged" ]] && ok "added missing .env keys from template: $merged"
fi

# Seed allowlisted keys from process environment if .env empty
seed_key_from_env() {
  local key="$1"
  local cur envval
  cur="$(env_get_key "$ENV_FILE" "$key" 2>/dev/null || true)"
  [[ -n "$cur" ]] && return 0
  envval="$(printenv "$key" 2>/dev/null || true)"
  [[ -n "$envval" ]] || return 0
  env_set_key "$ENV_FILE" "$key" "$envval"
  ok "$key imported from environment (value redacted)"
  _log "INFO" "$key seeded_from_env"
}
seed_key_from_env OPENROUTER_API_KEY
seed_key_from_env CONTEXT7_API_KEY
seed_key_from_env FRONTIER_MODEL

# Interactive key prompts (only when TTY and not --yes)
CAN_PROMPT=false
if ! $ASSUME_YES && [[ -r /dev/tty && -w /dev/tty ]]; then
  CAN_PROMPT=true
elif ! $ASSUME_YES && [[ -t 0 ]]; then
  CAN_PROMPT=true
fi
read_line() {
  REPLY=""
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    IFS= read -r REPLY </dev/tty || true
  elif [[ -t 0 ]]; then
    IFS= read -r REPLY || true
  fi
}
prompt_api_key() {
  local key="$1" label="$2" url="$3" required="${4:-false}"
  local cur val
  cur="$(env_get_key "$ENV_FILE" "$key" 2>/dev/null || true)"
  [[ -n "$cur" ]] && { ok "$key already set"; return 0; }
  if ! $CAN_PROMPT; then
    if [[ "$required" == "true" ]]; then
      opt "$key not set — edit $ENV_FILE or export $key and re-run"
    else
      opt "$key not set (optional) — skip for now"
    fi
    return 0
  fi
  echo ""
  printf "  %s\n" "$label"
  echo "  get one: $url"
  if [[ "$required" == "true" ]]; then
    printf "  paste key (required — Enter skips with warning): "
  else
    printf "  paste key (optional — Enter skips): "
  fi
  read_line
  val="${REPLY:-}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  if [[ -n "$val" ]]; then
    env_set_key "$ENV_FILE" "$key" "$val"
    ok "$key saved"
    _log "INFO" "$key written (value redacted)"
  elif [[ "$required" == "true" ]]; then
    opt "Skipped $key — add it before running omp"
  else
    info "skipped $key"
  fi
}

echo ""
printf '%b\n' "  ${c_b}API keys${c_0}  (Enter = skip optional · values never logged)"
echo "  File: $ENV_FILE (chmod 600, gitignored)"
prompt_api_key OPENROUTER_API_KEY \
  "OpenRouter (required — all models route through it)" \
  "https://openrouter.ai/keys" true
prompt_api_key CONTEXT7_API_KEY \
  "Context7 (recommended — library docs MCP)" \
  "https://context7.com/dashboard" false

# Frontier model toggle (plan/slow roles)
prompt_frontier_model() {
  local cur val
  cur="$(env_get_key "$ENV_FILE" FRONTIER_MODEL 2>/dev/null || true)"
  [[ -n "$cur" ]] && { ok "FRONTIER_MODEL=$cur"; return 0; }
  if ! $CAN_PROMPT; then
    env_set_if_unset "$ENV_FILE" FRONTIER_MODEL deepseek >/dev/null
    ok "FRONTIER_MODEL=deepseek (open-weight default)"
    return 0
  fi
  echo ""
  printf '%b\n' "  ${c_b}Frontier reasoning model${c_0}  (plan/slow roles)"
  echo "  1) deepseek  — deepseek/deepseek-v4-pro-0813 (open-weight, default)"
  echo "  2) opus      — anthropic/claude-opus-5        (closed frontier)"
  printf "  choose [1/2] (Enter = deepseek): "
  read_line
  val="${REPLY:-}"
  case "$val" in
    2|opus|Opus|OPUS) env_set_key "$ENV_FILE" FRONTIER_MODEL opus; ok "FRONTIER_MODEL=opus";;
    *) env_set_key "$ENV_FILE" FRONTIER_MODEL deepseek; ok "FRONTIER_MODEL=deepseek";;
  esac
}
prompt_frontier_model

# Verify OpenRouter when present
if ! $SKIP_VERIFY; then
  or_key="$(env_get_key "$ENV_FILE" OPENROUTER_API_KEY 2>/dev/null || true)"
  if [[ -n "$or_key" ]]; then
    http_code="$(curl -sS --connect-timeout 10 --max-time 30 -o /dev/null -w '%{http_code}' \
      -H "Authorization: Bearer $or_key" \
      -H "Content-Type: application/json" \
      -d '{"model":"deepseek/deepseek-chat","messages":[{"role":"user","content":"ping"}],"max_tokens":8}' \
      https://openrouter.ai/api/v1/chat/completions 2>/dev/null || echo "000")"
    if [[ "$http_code" == "200" ]]; then
      ok "OpenRouter key verified (HTTP 200)"
    else
      opt "OpenRouter key returned HTTP $http_code — check at https://openrouter.ai/keys"
    fi
  fi
  unset or_key
fi
echo ""

# ── 5. Scrub runtime strays from config dir ───────────────────────
_log_section "5. scrub strays"
# Remove known runtime junk that omp may drop next to config (never .env or symlinks)
scrubbed=""
for stray in .DS_Store; do
  if [[ -f "$AGENT_DIR/$stray" ]]; then
    rm -f "$AGENT_DIR/$stray"
    scrubbed="${scrubbed}${scrubbed:+ }${stray}"
  fi
done
[[ -n "$scrubbed" ]] && ok "removed config strays: $scrubbed" || info "no strays to remove"
echo ""

# ── Done ──────────────────────────────────────────────────────────
_log_section "done"
printf '%b\n' "${c_g}✓ omp-config installed${c_0}"
_log "OK" "omp-config installation complete"
echo ""
echo "  omp-config — pinned config for omp · OpenRouter · Context7"
echo ""
echo "Safety notes:"
echo "  • Sessions left untouched: $SESSIONS_DIR"
echo "  • Replacements backed up under: $BACKUP_ROOT"
echo "  • .env values never clobbered (chmod 600, gitignored)"
echo "  • Install log: $LOG_FILE"
echo "  • Latest log:  $LOG_DIR/install-latest.log"
echo ""
echo "Next:"
missing_or=false
if [[ -z "$(env_get_key "$ENV_FILE" OPENROUTER_API_KEY 2>/dev/null || true)" ]]; then
  missing_or=true
fi
step=1
if $missing_or; then
  echo "  $step. Edit $ENV_FILE — add OPENROUTER_API_KEY (required)"
  step=$((step + 1))
fi
echo "  $step. Run: omp"
echo ""
echo "  Docs: $INSTALL_DIR/README.md"
echo "  Secrets: only in $ENV_FILE (never committed). Repo ships env.example with empty values."
_install_exit_ec=0
} # end install_main

# Invoke only after the full script has been parsed (curl|bash safety).
install_main "$@"