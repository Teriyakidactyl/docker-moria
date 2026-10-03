#!/bin/bash

set -Eeuo pipefail

[ -f /etc/environment ] && source /etc/environment

: "${WINE_PATH:?WINE_PATH is required}"

case "$(basename "$0")" in
    moria-wine|moria-wine64)
        target="$WINE_PATH/wine"
        ;;
    moria-wineserver)
        target="$WINE_PATH/wineserver"
        ;;
    *)
        echo "Unsupported Moria Wine wrapper name: $(basename "$0")" >&2
        exit 1
        ;;
esac

if [ ! -x "$target" ]; then
    echo "Wine tool not found or not executable: $target" >&2
    exit 1
fi

if [ -n "${ARCH_COMMAND_PREFIX:-}" ]; then
    read -r -a arch_prefix <<< "$ARCH_COMMAND_PREFIX"
    exec "${arch_prefix[@]}" "$target" "$@"
fi

exec "$target" "$@"
