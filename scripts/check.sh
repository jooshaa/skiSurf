#!/bin/sh
# Все проверки прототипа одной командой: формат, линтер, типы, тесты расчёта. Запуск: scripts/check.sh
set -e
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"
DEFS=build/globalTypes.d.luau
mkdir -p build
if [ ! -f "$DEFS" ]; then
	curl -fsSL -o "$DEFS" https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
fi
echo "== stylua" && stylua --check src/sled tests
echo "== selene" && selene src/sled
echo "== типы" && rojo sourcemap sled.project.json -o build/sled-sourcemap.json >/dev/null
OUT=$(luau-lsp analyze --platform roblox --definitions @roblox="$DEFS" --sourcemap build/sled-sourcemap.json src/sled 2>&1 | grep -v '^\[' || true)
if [ -n "$OUT" ]; then echo "$OUT"; exit 1; fi
echo "== тесты" && lune run tests/sled.luau
