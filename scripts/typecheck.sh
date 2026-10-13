#!/usr/bin/env bash
# Optional strict type check of every module against Roblox's API types, with luau-lsp.
# Not part of check.sh: the newer Luau solver reports some known false positives, listed in
# docs/TESTING.md. It catches what lint cannot: missing members, stale names, wrong arguments.
# Needs luau-lsp on PATH (or set LUAU_LSP to its path) and rojo. Roblox's type definitions
# are downloaded into build/ the first time.
set -euo pipefail
cd "$(dirname "$0")/.."
LSP="${LUAU_LSP:-luau-lsp}"
DEFS=build/globalTypes.d.luau
mkdir -p build
if [ ! -f "$DEFS" ]; then
	curl -sSfL -o "$DEFS" \
		https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
rojo sourcemap default.project.json -o build/sourcemap.json
"$LSP" analyze --platform=roblox --sourcemap=build/sourcemap.json \
	--definitions="@roblox=$DEFS" "${@:-src}"
