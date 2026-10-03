#!/bin/bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_ROOT/scripts/container/moria-wine-wrapper.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
export WINE_PATH="$TMP_ROOT/wine-bin"
export MORIA_WRAPPER_TRACE="$TMP_ROOT/trace.log"

mkdir -p "$BIN_DIR" "$WINE_PATH"

cat > "$WINE_PATH/wine" <<'EOF'
#!/bin/bash
printf 'wine:%s\n' "$*" >> "$MORIA_WRAPPER_TRACE"
EOF

cat > "$WINE_PATH/wineserver" <<'EOF'
#!/bin/bash
printf 'wineserver:%s\n' "$*" >> "$MORIA_WRAPPER_TRACE"
EOF

cat > "$BIN_DIR/box64" <<'EOF'
#!/bin/bash
printf 'box64:%s\n' "$*" >> "$MORIA_WRAPPER_TRACE"
exec "$@"
EOF

install -m 0755 "$WRAPPER" "$BIN_DIR/moria-wine"
ln -s moria-wine "$BIN_DIR/moria-wine64"
ln -s moria-wine "$BIN_DIR/moria-wineserver"
chmod 0755 "$WINE_PATH/wine" "$WINE_PATH/wineserver" "$BIN_DIR/box64"

: > "$MORIA_WRAPPER_TRACE"
unset ARCH_COMMAND_PREFIX
"$BIN_DIR/moria-wine" --version
grep -Fqx 'wine:--version' "$MORIA_WRAPPER_TRACE"
test "$(wc -l < "$MORIA_WRAPPER_TRACE")" -eq 1

: > "$MORIA_WRAPPER_TRACE"
ARCH_COMMAND_PREFIX="$BIN_DIR/box64" "$BIN_DIR/moria-wine64" server.exe -log
grep -Fqx "box64:$WINE_PATH/wine server.exe -log" "$MORIA_WRAPPER_TRACE"
grep -Fqx 'wine:server.exe -log' "$MORIA_WRAPPER_TRACE"
test "$(wc -l < "$MORIA_WRAPPER_TRACE")" -eq 2

: > "$MORIA_WRAPPER_TRACE"
ARCH_COMMAND_PREFIX="$BIN_DIR/box64" "$BIN_DIR/moria-wineserver" -w
grep -Fqx "box64:$WINE_PATH/wineserver -w" "$MORIA_WRAPPER_TRACE"
grep -Fqx 'wineserver:-w' "$MORIA_WRAPPER_TRACE"
test "$(wc -l < "$MORIA_WRAPPER_TRACE")" -eq 2

echo "Moria Wine wrapper contract test passed"
