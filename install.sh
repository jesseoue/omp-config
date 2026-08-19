#!/usr/bin/env bash
# omp-config installer — symlinks config into ~/.omp/agent/
set -euo pipefail

AGENT_DIR="${OMP_AGENT_DIR:-$HOME/.omp/agent}"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> omp-config installer"
echo "    source: $SRC_DIR"
echo "    target: $AGENT_DIR"

mkdir -p "$AGENT_DIR"

# Symlink config files, backing up any existing ones.
for f in config.yml models.yml; do
  src="$SRC_DIR/$f"
  dst="$AGENT_DIR/$f"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "    backing up existing $dst -> $dst.bak"
    mv "$dst" "$dst.bak"
  fi
  ln -sfn "$src" "$dst"
  echo "    linked $f"
done

# Copy env template if no .env exists yet.
if [ ! -f "$AGENT_DIR/.env" ]; then
  if [ -f "$SRC_DIR/env.example" ]; then
    cp "$SRC_DIR/env.example" "$AGENT_DIR/.env"
    echo "    created $AGENT_DIR/.env (edit it to add OPENROUTER_API_KEY)"
  fi
else
  echo "    $AGENT_DIR/.env already exists — leaving it untouched"
fi

echo "==> Done. Add your key to $AGENT_DIR/.env, then run: omp"