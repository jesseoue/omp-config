#!/usr/bin/env bash
# install.sh — omp-config installer + maintenance CLI
#
# Pinned, batteries-included config for omp (Oh My Pi) · OpenRouter · Context7.
#
# Commands (default: install):
#   ./install.sh [install]     install/update symlinks, seed keys, verify
#   ./install.sh doctor        full health check (perms, links, keys, endpoints)
#                              + AI-written fix plan when problems are found
#   ./install.sh fix           auto-repair everything safe (relink, chmod, keys)
#   ./install.sh status        one-screen status: links, keys, omp, repo
#   ./install.sh verify        live OpenRouter key check + pinned endpoint health
#   ./install.sh update        git pull + relink (bypasses the weekly rate limit)
#   ./install.sh uninstall     remove symlinks only (keeps .env, sessions, backups)
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
#   • AI diagnostics never see key values — only redacted check results
#   • main() wrapper so curl|bash cannot partial-execute mid-download
#
# After install: add your key to ~/.omp/agent/.env, then run: omp

# Entire body lives in main() so a truncated curl|bash pipe cannot run half a script.
install_main() {
set -euo pipefail

umask 077
unset CDPATH 2>/dev/null || true
IFS=$' \t\n'

# ── Command + flags ───────────────────────────────────────────────
COMMAND=""
INSTALL_DIR_FLAG=""
ASSUME_YES=false
SKIP_VERIFY=false
NO_AI=false
# Default before parsing: without this, `set -u` kills every run that does
# not pass --force at the rate-limit check. FORCE_INSTALL=1 in the
# environment also works.
FORCE_INSTALL="${FORCE_INSTALL:-0}"

usage() {
  cat <<'EOF'
install.sh — omp-config installer + maintenance CLI

  Pinned config for omp (Oh My Pi) · OpenRouter · Context7.

Usage:
  ./install.sh [command] [flags]

Commands:
  install      (default) symlink configs into ~/.omp/agent, seed keys, verify
  doctor       health check: perms, symlinks, keys, omp binary, endpoint
               uptime — plus an AI-written fix plan when problems are found
  fix          auto-repair what is safe: relink, chmod 600/700, add missing
               .env keys, scrub strays
  status       one-screen status of links, keys (redacted), omp, repo
  verify       live OpenRouter key check + pinned provider endpoint health
  update       git pull --ff-only + relink (bypasses weekly rate limit)
  uninstall    remove the three symlinks; keeps .env, sessions, and backups
  help         this text

Flags:
  --dir PATH      install/clone location (default: repo dir if local, else ~/omp-config)
  --yes, -y       non-interactive: accept defaults, seed keys from env
  --skip-verify   skip network checks (key ping, endpoint health)
  --no-ai         doctor: skip the AI-generated fix plan
  --force         install: bypass the once-per-week rate limit

Env (pre-seed keys, no paste needed):
  OPENROUTER_API_KEY  CONTEXT7_API_KEY

Fresh machine:
  curl -fsSL https://raw.githubusercontent.com/jesseoue/omp-config/main/install.sh | bash

Safety: refuses root; never deletes sessions; backs up replaced configs.
After install: add your key to ~/.omp/agent/.env, then run: omp
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    install|doctor|fix|status|verify|update|uninstall|help)
      [[ -z "$COMMAND" ]] || { echo "fatal: multiple commands: $COMMAND and $1" >&2; exit 1; }
      COMMAND="$1"; shift
      ;;
    --dir|--prefix)
      INSTALL_DIR_FLAG="${2:-}"
      [[ -n "$INSTALL_DIR_FLAG" ]] || { echo "fatal: $1 needs a path" >&2; exit 1; }
      shift 2
      ;;
    --yes|-y|--quick|-q) ASSUME_YES=true; shift ;;
    --skip-verify) SKIP_VERIFY=true; shift ;;
    --no-ai) NO_AI=true; shift ;;
    --force) FORCE_INSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "fatal: unknown argument: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done
COMMAND="${COMMAND:-install}"
[[ "$COMMAND" == "help" ]] && { usage; exit 0; }

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
  echo "# omp-config ${COMMAND} log"
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
  printf '  %bomp-config%b · %s\n' "${c_p}" "${c_0}" "$COMMAND"
  printf '  %bPinned config for omp · OpenRouter · Context7%b\n\n' "${c_dim}" "${c_0}"
}

# ── Paths ─────────────────────────────────────────────────────────
AGENT_DIR="${OMP_AGENT_DIR:-$HOME/.omp/agent}"
BACKUP_ROOT="${HOME}/.omp/backups"
SESSIONS_DIR="${HOME}/.omp/sessions"
ENV_FILE="$AGENT_DIR/.env"
MANAGED_FILES="config.yml models.yml mcp.json"

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

# ── Shared helpers ────────────────────────────────────────────────
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

# Safe .env key get/set (no sed injection; values may contain any chars)
env_get_key() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  awk -F= -v k="$key" '$1 == k { sub(/^[^=]*=/,""); print; exit }' "$file"
}
env_set_key() {
  local file="$1" key="$2" val="$3"
  if [[ -f "$file" ]] && grep -qE "^${key}=" "$file" 2>/dev/null; then
    # Replace in place via awk (safe for special characters in values).
    # -F= is load-bearing: with the default whitespace separator, $1 of
    # "KEY=" is "KEY=" (including the =) and never matches, so the write
    # silently no-ops against template lines.
    # Use a unique temporary file so concurrent installers cannot collide.
    local tmp_file="${file}.tmp.$$"
    awk -F= -v k="$key" -v v="$val" '
      $1 == k { print k "=" v; next }
      { print }
    ' "$file" >"$tmp_file" && mv "$tmp_file" "$file"
  else
    printf '%s=%s\n' "$key" "$val" >>"$file"
  fi
  chmod 600 "$file" 2>/dev/null || true
}

# Redact a secret for display: length + last 4 chars only.
redact_key() {
  local v="$1"
  local n=${#v}
  if (( n <= 4 )); then printf 'set (%d chars)' "$n"; else printf 'set (%d chars, …%s)' "$n" "${v: -4}"; fi
}

# Minimal JSON string escaper (backslash, quote, newline, tab, CR).
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//$'\r'/}
  printf '%s' "$s"
}

# Resolve the OpenRouter key: .env first, then process environment.
get_or_key() {
  local k
  k="$(env_get_key "$ENV_FILE" OPENROUTER_API_KEY 2>/dev/null || true)"
  [[ -z "$k" ]] && k="${OPENROUTER_API_KEY:-}"
  printf '%s' "$k"
}

# Interactive input helper
read_line() {
  REPLY=""
  if [[ -r /dev/tty && -w /dev/tty ]]; then
    IFS= read -r REPLY </dev/tty || true
  elif [[ -t 0 ]]; then
    IFS= read -r REPLY || true
  fi
}
CAN_PROMPT=false
if ! $ASSUME_YES && [[ -r /dev/tty && -w /dev/tty ]]; then
  CAN_PROMPT=true
elif ! $ASSUME_YES && [[ -t 0 ]]; then
  CAN_PROMPT=true
fi

# ── Check framework (doctor / fix / status share these) ───────────
CHECK_FAILS=0
CHECK_WARNS=0
CHECK_REPORT=""
chk_ok()   { ok "$*";  CHECK_REPORT="${CHECK_REPORT}OK: $*"$'\n'; }
chk_warn() { opt "$*"; CHECK_REPORT="${CHECK_REPORT}WARN: $*"$'\n'; CHECK_WARNS=$((CHECK_WARNS + 1)); }
chk_bad()  { bad "$*"; CHECK_REPORT="${CHECK_REPORT}FAIL: $*"$'\n'; CHECK_FAILS=$((CHECK_FAILS + 1)); }

# omp binary present?
check_omp_binary() {
  if command -v omp >/dev/null 2>&1; then
    local v
    v="$(omp --version 2>/dev/null | head -1 || true)"
    chk_ok "omp binary on PATH${v:+ ($v)}"
  else
    chk_bad "omp binary not found — install it: curl -fsSL https://omp.sh/install | sh  (or: brew install can1357/tap/omp)"
  fi
}

# Symlinks present and pointing into this checkout?
check_symlinks() {
  local f dst cur
  for f in $MANAGED_FILES; do
    dst="$AGENT_DIR/$f"
    if [[ -L "$dst" ]]; then
      cur="$(readlink "$dst" 2>/dev/null || true)"
      if [[ "$cur" == "$INSTALL_DIR/$f" && -f "$dst" ]]; then
        chk_ok "$f → linked to this checkout"
      elif [[ ! -e "$dst" ]]; then
        chk_bad "$f symlink is dangling ($cur) — run: ./install.sh fix"
      else
        chk_warn "$f links to a different checkout ($cur) — run: ./install.sh fix"
      fi
    elif [[ -e "$dst" ]]; then
      chk_warn "$f is a plain file, not a symlink (edits will drift from the repo) — run: ./install.sh fix"
    else
      chk_bad "$f missing from $AGENT_DIR — run: ./install.sh"
    fi
  done
}

# .env exists with sane permissions and required keys?
check_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    chk_bad ".env missing at $ENV_FILE — run: ./install.sh"
    return 0
  fi
  local perms
  perms="$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE" 2>/dev/null || echo '?')"
  if [[ "$perms" == "600" ]]; then
    chk_ok ".env permissions are 600"
  else
    chk_warn ".env permissions are $perms (want 600) — run: ./install.sh fix"
  fi
  local or_key c7_key
  or_key="$(env_get_key "$ENV_FILE" OPENROUTER_API_KEY 2>/dev/null || true)"
  c7_key="$(env_get_key "$ENV_FILE" CONTEXT7_API_KEY 2>/dev/null || true)"
  if [[ -n "$or_key" ]]; then
    chk_ok "OPENROUTER_API_KEY $(redact_key "$or_key")"
  else
    chk_bad "OPENROUTER_API_KEY empty — every model routes through OpenRouter; add it to $ENV_FILE"
  fi
  if [[ -n "$c7_key" ]]; then
    chk_ok "CONTEXT7_API_KEY $(redact_key "$c7_key")"
  else
    chk_warn "CONTEXT7_API_KEY empty (optional) — Context7 library-docs MCP runs anonymous/rate-limited"
  fi
}

# Directory permissions: nothing group/world-writable around secrets.
check_dir_perms() {
  local d perms
  for d in "$AGENT_DIR" "$BACKUP_ROOT"; do
    [[ -d "$d" ]] || continue
    perms="$(stat -f '%Lp' "$d" 2>/dev/null || stat -c '%a' "$d" 2>/dev/null || echo '?')"
    case "$perms" in
      700) chk_ok "$(basename "$d")/ permissions are 700" ;;
      7?0|7?5|7?1|7??)
        if [[ "${perms:2:1}" =~ [2367] || "${perms:1:1}" =~ [2367] ]]; then
          chk_warn "$d permissions are $perms (group/world-writable) — run: ./install.sh fix"
        else
          chk_ok "$d permissions are $perms (not writable by others)"
        fi
        ;;
      *) chk_warn "$d permissions are $perms — run: ./install.sh fix" ;;
    esac
  done
}

# Repo sanity: right remote, clean-ish tree, parseable configs.
check_repo() {
  if [[ ! -f "$INSTALL_DIR/config.yml" ]]; then
    chk_bad "no omp-config checkout at $INSTALL_DIR — run: ./install.sh"
    return 0
  fi
  chk_ok "checkout present at $INSTALL_DIR"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    local remote dirty
    remote="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
    case "$remote" in
      *jesseoue/omp-config*) chk_ok "git origin is jesseoue/omp-config" ;;
      "") chk_warn "no git origin configured (updates disabled)" ;;
      *) chk_warn "git origin is $remote (expected …/jesseoue/omp-config)" ;;
    esac
    dirty="$(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if [[ "$dirty" == "0" ]]; then
      chk_ok "working tree clean"
    else
      chk_warn "working tree has $dirty uncommitted change(s) — local edits will not survive ./install.sh update"
    fi
  fi
  local f
  for f in config.yml models.yml; do
    if grep -qE '^(modelRoles|providers):' "$INSTALL_DIR/$f" 2>/dev/null; then
      chk_ok "$f looks sane"
    else
      chk_bad "$f is missing its top-level section — file corrupt?"
    fi
  done
}

# Live: does the OpenRouter key actually work?
check_openrouter_key_live() {
  local or_key http_code
  or_key="$(get_or_key)"
  if [[ -z "$or_key" ]]; then
    chk_warn "skipping live key check (no OPENROUTER_API_KEY yet)"
    return 0
  fi
  http_code="$(curl -sS --connect-timeout 10 --max-time 30 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $or_key" \
    -H "Content-Type: application/json" \
    -d '{"model":"deepseek/deepseek-v4-flash-0731","messages":[{"role":"user","content":"ping"}],"max_tokens":8}' \
    https://openrouter.ai/api/v1/chat/completions 2>/dev/null || echo "000")"
  if [[ "$http_code" == "200" ]]; then
    chk_ok "OpenRouter key verified (HTTP 200)"
  elif [[ "$http_code" == "000" ]]; then
    chk_warn "OpenRouter unreachable (network?) — could not verify key"
  else
    chk_bad "OpenRouter key returned HTTP $http_code — check https://openrouter.ai/keys and credits"
  fi
}

# Live: are the provider pins in models.yml still healthy? This is the check
# that catches endpoint rot (e.g. a pinned provider deranked to 0% uptime).
check_pinned_endpoints() {
  if ! command -v jq >/dev/null 2>&1; then
    chk_warn "jq not installed — skipping pinned-endpoint health (brew install jq)"
    return 0
  fi
  local models_file="$INSTALL_DIR/models.yml"
  [[ -f "$models_file" ]] || return 0
  local pairs
  pairs="$(awk '
    /^      [a-zA-Z0-9._\/-]+:$/ { model=$1; gsub(/:$/,"",model) }
    /^ *only: \[/ {
      line=$0
      sub(/.*only: \[/,"",line); sub(/\].*/,"",line); gsub(/[ \t]/,"",line)
      if (model != "") { print model "|" line; model="" }
    }
  ' "$models_file")"
  [[ -n "$pairs" ]] || { chk_warn "no provider pins found in models.yml"; return 0; }
  local pair model pins json healthy total
  while IFS= read -r pair; do
    model="${pair%%|*}"; pins="${pair##*|}"
    json="$(curl -sS --connect-timeout 10 --max-time 25 \
      "https://openrouter.ai/api/v1/models/${model}/endpoints" 2>/dev/null || true)"
    if [[ -z "$json" ]] || ! printf '%s' "$json" | jq -e '.data.endpoints' >/dev/null 2>&1; then
      chk_warn "$model: could not fetch endpoint health (offline or delisted?)"
      continue
    fi
    healthy=0; total=0
    local p
    IFS=',' read -ra _pins <<<"$pins"
    for p in "${_pins[@]}"; do
      [[ -n "$p" ]] || continue
      total=$((total + 1))
      if printf '%s' "$json" | jq -e --arg p "$p" \
        '[.data.endpoints[] | select((.tag == $p) or (.tag | startswith($p + "/"))) | select(.status >= 0 and (.uptime_last_30m // 0) >= 90)] | length > 0' \
        >/dev/null 2>&1; then
        healthy=$((healthy + 1))
      fi
    done
    if (( total == 0 )); then
      continue
    elif (( healthy == 0 )); then
      chk_bad "$model: 0/$total pinned providers healthy — re-pin in models.yml (curl …/models/$model/endpoints)"
    elif (( healthy < total )); then
      chk_warn "$model: $healthy/$total pinned providers healthy (failover still has room)"
    else
      chk_ok "$model: $healthy/$total pinned providers healthy"
    fi
  done <<<"$pairs"
}

# ── AI fix plan: explain doctor failures using the user's own key ─
# Sends ONLY the redacted check report (never key values) to a cheap model.
ai_fix_plan() {
  $NO_AI && return 0
  local or_key
  or_key="$(get_or_key)"
  [[ -n "$or_key" ]] || { info "AI fix plan skipped (no OpenRouter key yet)"; return 0; }
  command -v curl >/dev/null 2>&1 || return 0
  echo ""
  info "Asking DeepSeek Flash for a fix plan (uses your OpenRouter key, ~\$0.0001)…"
  local context prompt payload resp content
  context="platform=$(uname -s) arch=$(uname -m) agent_dir=$AGENT_DIR install_dir=$INSTALL_DIR"
  prompt="You are the maintenance assistant for omp-config (dotfiles for the omp AI coding agent; configs symlinked into ~/.omp/agent; secrets in ~/.omp/agent/.env chmod 600; installer commands: install, doctor, fix, status, verify, update, uninstall). Given this health-check report, write a terse numbered fix plan (max 6 steps) with exact shell commands where possible. Only address WARN/FAIL lines. No preamble.

Context: ${context}

Report:
${CHECK_REPORT}"
  payload="{\"model\":\"deepseek/deepseek-v4-flash-0731\",\"max_tokens\":400,\"temperature\":0.2,\"messages\":[{\"role\":\"user\",\"content\":\"$(json_escape "$prompt")\"}]}"
  resp="$(curl -sS --connect-timeout 10 --max-time 45 \
    -H "Authorization: Bearer $or_key" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    https://openrouter.ai/api/v1/chat/completions 2>/dev/null || true)"
  [[ -n "$resp" ]] || { opt "AI fix plan unavailable (network)"; return 0; }
  content=""
  if command -v jq >/dev/null 2>&1; then
    # Reasoning models (e.g. DeepSeek Flash) return content:null and put the
    # text in .reasoning — fall back to that before giving up.
    content="$(printf '%s' "$resp" | jq -r '.choices[0].message.content // .choices[0].message.reasoning // empty' 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    content="$(printf '%s' "$resp" | python3 -c 'import sys,json
try:
    m=json.load(sys.stdin)["choices"][0]["message"]
    print(m.get("content") or m.get("reasoning") or "")
except Exception: pass' 2>/dev/null || true)"
  fi
  if [[ -n "$content" ]]; then
    echo ""
    printf '%b\n' "  ${c_p}${c_bold}AI fix plan${c_0}"
    printf '%s\n' "$content" | sed 's/^/  /'
    _log "INFO" "ai fix plan delivered"
  else
    opt "AI fix plan unavailable (could not parse response; install jq for best results)"
  fi
}

# ── Repairs (fix / install share these) ───────────────────────────
fix_permissions() {
  local changed=false
  if [[ -f "$ENV_FILE" ]]; then
    chmod 600 "$ENV_FILE" 2>/dev/null && changed=true
  fi
  local d
  for d in "$HOME/.omp" "$AGENT_DIR" "$BACKUP_ROOT" "$LOG_DIR"; do
    [[ -d "$d" ]] && chmod 700 "$d" 2>/dev/null && changed=true
  done
  $changed && ok "permissions hardened (.env 600, state dirs 700)" || info "permissions already hardened"
}

fix_env_keys() {
  [[ -f "$INSTALL_DIR/env.example" ]] || return 0
  [[ -f "$ENV_FILE" ]] || return 0
  local merged="" line key
  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    key="${line%%=*}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ -n "$key" ]] || continue
    if ! grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
      if grep -qE "^${key}=" "$INSTALL_DIR/env.example" 2>/dev/null; then
        printf '%s=\n' "$key" >>"$ENV_FILE"
        merged="${merged}${merged:+ }${key}"
      fi
    fi
  done <"$INSTALL_DIR/env.example"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  [[ -n "$merged" ]] && ok "added missing .env keys from template: $merged" || info "no missing .env keys"
}

fix_strays() {
  local scrubbed=""
  # Remove known runtime junk that omp may drop next to config (never .env or symlinks)
  # shellcheck disable=SC2043  # single-item list kept as a loop for easy extension
  for stray in .DS_Store; do
    if [[ -f "$AGENT_DIR/$stray" ]]; then
      rm -f "$AGENT_DIR/$stray"
      scrubbed="${scrubbed}${scrubbed:+ }${stray}"
    fi
  done
  [[ -n "$scrubbed" ]] && ok "removed config strays: $scrubbed" || info "no strays to remove"
}

relink_all() {
  mkdir -p "$AGENT_DIR" "$BACKUP_ROOT"
  local f
  for f in $MANAGED_FILES; do
    [[ -f "$INSTALL_DIR/$f" ]] || { bad "missing $f in $INSTALL_DIR — skipping"; continue; }
    link_config "$INSTALL_DIR/$f" "$AGENT_DIR/$f" "$f"
  done
}

# ── Command: doctor ───────────────────────────────────────────────
cmd_doctor() {
  _log_section "doctor"
  printf '%b\n' "  ${c_bold}Binaries${c_0}"
  check_omp_binary
  if command -v bun >/dev/null 2>&1; then chk_ok "bun on PATH ($(bun --version 2>/dev/null || true))"; else chk_warn "bun not found (omp's runtime; the omp installer bundles it)"; fi
  command -v jq >/dev/null 2>&1 && chk_ok "jq on PATH" || chk_warn "jq not found — endpoint health + AI plan parsing degrade (brew install jq)"
  echo ""
  printf '%b\n' "  ${c_bold}Repo${c_0}"
  check_repo
  echo ""
  printf '%b\n' "  ${c_bold}Symlinks${c_0}"
  check_symlinks
  echo ""
  printf '%b\n' "  ${c_bold}Secrets + permissions${c_0}"
  check_env
  check_dir_perms
  if ! $SKIP_VERIFY; then
    echo ""
    printf '%b\n' "  ${c_bold}Network (live)${c_0}"
    check_openrouter_key_live
    check_pinned_endpoints
  fi
  echo ""
  if (( CHECK_FAILS == 0 && CHECK_WARNS == 0 )); then
    printf '%b\n' "${c_g}✓ doctor: everything healthy${c_0}"
  else
    printf '%b\n' "${c_y}doctor: ${CHECK_FAILS} problem(s), ${CHECK_WARNS} warning(s)${c_0}"
    info "auto-repair the safe ones with: ./install.sh fix"
    ai_fix_plan
  fi
  (( CHECK_FAILS == 0 )) || _install_exit_ec=1
  (( CHECK_FAILS == 0 )) || exit 1
}

# ── Command: fix ──────────────────────────────────────────────────
cmd_fix() {
  _log_section "fix"
  [[ -f "$INSTALL_DIR/config.yml" ]] || die "no checkout at $INSTALL_DIR — run: ./install.sh"
  info "repairing symlinks, permissions, and .env keys (values are never touched)"
  echo ""
  relink_all
  fix_permissions
  fix_env_keys
  fix_strays
  echo ""
  printf '%b\n' "${c_g}✓ fix complete${c_0} — verify with: ./install.sh doctor"
}

# ── Command: status ───────────────────────────────────────────────
cmd_status() {
  _log_section "status"
  local f dst cur or_key c7_key
  printf '%b\n' "  ${c_bold}Links${c_0}  ($AGENT_DIR)"
  for f in $MANAGED_FILES; do
    dst="$AGENT_DIR/$f"
    if [[ -L "$dst" && -f "$dst" ]]; then
      cur="$(readlink "$dst")"
      if [[ "$cur" == "$INSTALL_DIR/$f" ]]; then ok "$f → this checkout"; else opt "$f → $cur"; fi
    elif [[ -e "$dst" ]]; then
      opt "$f — plain file (not linked)"
    else
      bad "$f — missing"
    fi
  done
  echo ""
  printf '%b\n' "  ${c_bold}Keys${c_0}  ($ENV_FILE)"
  or_key="$(env_get_key "$ENV_FILE" OPENROUTER_API_KEY 2>/dev/null || true)"
  c7_key="$(env_get_key "$ENV_FILE" CONTEXT7_API_KEY 2>/dev/null || true)"
  if [[ -n "$or_key" ]]; then ok "OPENROUTER_API_KEY $(redact_key "$or_key")"; else bad "OPENROUTER_API_KEY empty"; fi
  if [[ -n "$c7_key" ]]; then ok "CONTEXT7_API_KEY $(redact_key "$c7_key")"; else info "CONTEXT7_API_KEY empty (optional)"; fi
  echo ""
  printf '%b\n' "  ${c_bold}Toolchain + repo${c_0}"
  if command -v omp >/dev/null 2>&1; then ok "omp $(omp --version 2>/dev/null | head -1 || true)"; else bad "omp not installed (curl -fsSL https://omp.sh/install | sh)"; fi
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "repo: $INSTALL_DIR @ $(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo '?') ($(git -C "$INSTALL_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ') dirty)"
  else
    info "repo: $INSTALL_DIR (not a git checkout)"
  fi
  info "sessions: $SESSIONS_DIR $( [[ -d "$SESSIONS_DIR" ]] && echo '(present, never touched)' || echo '(none yet)' )"
}

# ── Command: verify ───────────────────────────────────────────────
cmd_verify() {
  _log_section "verify"
  check_openrouter_key_live
  check_pinned_endpoints
  echo ""
  if (( CHECK_FAILS == 0 )); then
    printf '%b\n' "${c_g}✓ verify: key + pinned endpoints healthy${c_0}"
  else
    printf '%b\n' "${c_y}verify: ${CHECK_FAILS} problem(s), ${CHECK_WARNS} warning(s)${c_0}"
    ai_fix_plan
    _install_exit_ec=1
    exit 1
  fi
}

# ── Command: update ───────────────────────────────────────────────
cmd_update() {
  _log_section "update"
  [[ -d "$INSTALL_DIR/.git" ]] || die "$INSTALL_DIR is not a git checkout — run: ./install.sh"
  local remote
  remote="$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || true)"
  case "$remote" in
    *jesseoue/omp-config*) ;;
    "") die "no git origin — cannot update" ;;
    *) die "refusing to pull: origin is '$remote' (expected …/jesseoue/omp-config)" ;;
  esac
  info "updating ${INSTALL_DIR}…"
  if git -C "$INSTALL_DIR" pull --ff-only; then
    ok "repo updated ($(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || true))"
  else
    die "git pull failed (local changes or offline) — stash or commit local edits first"
  fi
  echo ""
  relink_all
  fix_env_keys
  fix_strays
  echo ""
  printf '%b\n' "${c_g}✓ update complete${c_0} — sanity-check with: ./install.sh doctor"
}

# ── Command: uninstall ────────────────────────────────────────────
cmd_uninstall() {
  _log_section "uninstall"
  info "This removes the three config symlinks from $AGENT_DIR."
  info "Your .env (keys), sessions, and backups are kept."
  if ! $ASSUME_YES; then
    if $CAN_PROMPT; then
      printf "  proceed? [y/N]: "
      read_line
      case "${REPLY:-}" in y|Y|yes|YES) ;; *) info "aborted"; return 0 ;; esac
    else
      die "refusing to uninstall non-interactively without --yes"
    fi
  fi
  local f dst cur removed=0
  for f in $MANAGED_FILES; do
    dst="$AGENT_DIR/$f"
    if [[ -L "$dst" ]]; then
      cur="$(readlink "$dst" 2>/dev/null || true)"
      case "$cur" in
        "$INSTALL_DIR"/*)
          rm -f "$dst"
          ok "removed $f symlink"
          removed=$((removed + 1))
          ;;
        *)
          opt "left $f alone (links elsewhere: $cur)"
          ;;
      esac
    elif [[ -e "$dst" ]]; then
      opt "left $f alone (plain file, not our symlink)"
    fi
  done
  echo ""
  printf '%b\n' "${c_g}✓ uninstall complete${c_0} (${removed} link(s) removed)"
  info "kept: $ENV_FILE, $SESSIONS_DIR, $BACKUP_ROOT"
  info "restore any earlier config from $BACKUP_ROOT, or re-run ./install.sh"
}

# ── Command: install (default) ────────────────────────────────────
cmd_install() {
  # Rate limit: at most one install per week. Marker records the last
  # successful install; re-running within 7 days is a no-op unless --force.
  local RATE_LIMIT_MARKER="${HOME}/.omp/backups/.last-install"
  local RATE_LIMIT_SECONDS=$((7 * 24 * 60 * 60))
  if [[ "$FORCE_INSTALL" != "1" ]]; then
    if [[ -f "$RATE_LIMIT_MARKER" ]]; then
      local _last_ts _now_ts _elapsed _remaining _remaining_d _remaining_h
      _last_ts="$(cat "$RATE_LIMIT_MARKER" 2>/dev/null || true)"
      if [[ "$_last_ts" =~ ^[0-9]+$ ]]; then
        _now_ts="$(date +%s)"
        _elapsed=$((_now_ts - _last_ts))
        if (( _elapsed < RATE_LIMIT_SECONDS )); then
          _remaining=$((RATE_LIMIT_SECONDS - _elapsed))
          _remaining_d=$((_remaining / 86400))
          _remaining_h=$(((_remaining % 86400) / 3600))
          info "Already installed within the last week — skipping (re-run with --force to override)"
          info "Next allowed in ~${_remaining_d}d ${_remaining_h}h"
          info "Maintenance never rate-limits: ./install.sh doctor | fix | status | verify | update"
          _install_exit_ec=0
          exit 0
        fi
      fi
    fi
  fi

  # ── Prerequisites ──
  _log_section "prerequisites"
  local missing=()
  local c
  for c in curl git bash; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [[ ${#missing[@]} -gt 0 ]] && die "missing required command(s): ${missing[*]}"
  ok "required commands present (curl git bash)"

  # ── 1. Clone or update repo ──
  _log_section "1. clone/update repo"
  local REPO_URL="https://github.com/jesseoue/omp-config.git"
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

  [[ -f "$INSTALL_DIR/config.yml" ]] || die "missing config.yml in $INSTALL_DIR — aborting"
  [[ -f "$INSTALL_DIR/models.yml" ]] || die "missing models.yml in $INSTALL_DIR — aborting"
  [[ -f "$INSTALL_DIR/mcp.json" ]] || die "missing mcp.json in $INSTALL_DIR — aborting"
  echo ""

  # ── 2. Sessions: never touch ──
  _log_section "2. sessions"
  if [[ -d "$SESSIONS_DIR" ]]; then
    info "Leaving omp sessions intact at $SESSIONS_DIR (never deleted by installer)"
  else
    info "No existing sessions dir yet (created by omp on first run)"
  fi
  echo ""

  # ── 3. Config symlinks (backup real files; never rm sessions) ──
  _log_section "3. config symlinks"
  relink_all
  echo ""

  # ── 4. .env + key setup ──
  _log_section "4. env keys"

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
  fix_env_keys

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

  # Interactive key prompts (only when TTY and not --yes)
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

  # Verify OpenRouter when present
  if ! $SKIP_VERIFY; then
    check_openrouter_key_live
  fi
  echo ""

  # ── 5. Permissions + strays ──
  _log_section "5. permissions + strays"
  fix_permissions
  fix_strays
  echo ""

  # ── Done ──
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
  local missing_or=false step=1
  if [[ -z "$(env_get_key "$ENV_FILE" OPENROUTER_API_KEY 2>/dev/null || true)" ]]; then
    missing_or=true
  fi
  if $missing_or; then
    echo "  $step. Edit $ENV_FILE — add OPENROUTER_API_KEY (required)"
    step=$((step + 1))
  fi
  if ! command -v omp >/dev/null 2>&1; then
    echo "  $step. Install omp: curl -fsSL https://omp.sh/install | sh"
    step=$((step + 1))
  fi
  echo "  $step. Run: omp"
  step=$((step + 1))
  echo "  $step. Any time: ./install.sh doctor   (health check + AI fix plan)"
  echo ""
  echo "  Docs: $INSTALL_DIR/README.md"
  echo "  Secrets: only in $ENV_FILE (never committed). Repo ships env.example with empty values."
  date +%s >"$RATE_LIMIT_MARKER" 2>/dev/null || true
  chmod 600 "$RATE_LIMIT_MARKER" 2>/dev/null || true
}

# ── Dispatch ──────────────────────────────────────────────────────
_install_banner
info "log → $LOG_FILE"
info "HOME=$HOME"
info "checkout → $INSTALL_DIR"
info "target → $AGENT_DIR"
echo ""

case "$COMMAND" in
  install)   cmd_install ;;
  doctor)    cmd_doctor ;;
  fix)       cmd_fix ;;
  status)    cmd_status ;;
  verify)    cmd_verify ;;
  update)    cmd_update ;;
  uninstall) cmd_uninstall ;;
  *)         die "unknown command: $COMMAND" ;;
esac
_install_exit_ec=0
} # end install_main

# Invoke only after the full script has been parsed (curl|bash safety).
install_main "$@"
