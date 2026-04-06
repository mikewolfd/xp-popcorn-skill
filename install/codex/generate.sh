#!/usr/bin/env bash
# Materialize .codex/ for Codex discovery from platforms/codex/subagent/.
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
SRC="$ROOT/platforms/codex/subagent"
OUT="$ROOT/.codex"
mkdir -p "$OUT/agents"
cp "$SRC/manifests/hooks.json" "$OUT/hooks.json"
cp "$SRC/manifests/config.toml" "$OUT/config.toml"
cp "$SRC/agents/"*.toml "$OUT/agents/"
