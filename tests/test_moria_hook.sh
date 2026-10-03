#!/bin/bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/container/hooks/pre-startup/30_moria.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

export APP_FILES="$TMP_ROOT/app"
export WORLD_FILES="$TMP_ROOT/world"
export APP_EXECUTABLE="$APP_FILES/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe"
export SERVER_LISTEN_ADDRESS="0.0.0.0"
export SERVER_PORT="17877"
export SERVER_ADVERTISE_ADDRESS="game.example.test"
export SERVER_ADVERTISE_PORT="27877"
export SERVER_PASS='friend "of" mine'
export WORLD_NAME='Khazad-dûm Docker World'
export WORLD_FILE='MW_TEST_WORLD.sav'
export SERVER_WORKER_THREADS="3"

log() {
    :
}

mkdir -p "$APP_FILES/Moria/Saved/SaveGamesDedicated"          "$APP_FILES/Moria/Binaries/Win64"          "$WORLD_FILES"

printf 'save-data\n' > "$APP_FILES/Moria/Saved/SaveGamesDedicated/MW_TEST_WORLD.sav"
printf 'permissions\n' > "$APP_FILES/MoriaServerPermissions.txt"
printf 'rules\n' > "$APP_FILES/MoriaServerRules.txt"

cat > "$APP_FILES/MoriaServerConfig.ini" <<'EOF'
[Main]
OptionalPassword=old

[World]
Name="Old World"
OptionalWorldFilename=

[Host]
ListenAddress=127.0.0.1
ListenPort=1
AdvertiseAddress=auto
AdvertisePort=-1

[Console]
Enabled=false

[Performance]
ServerFPS=30
LoadedAreaLimit=12
EOF

truncate -s 256 "$APP_EXECUTABLE"
printf '\x80\x00\x00\x00' | dd of="$APP_EXECUTABLE" bs=1 seek=60 conv=notrunc status=none
printf 'PE\x00\x00' | dd of="$APP_EXECUTABLE" bs=1 seek=128 conv=notrunc status=none
printf '\x0b\x02' | dd of="$APP_EXECUTABLE" bs=1 seek=152 conv=notrunc status=none
printf '\x02\x00' | dd of="$APP_EXECUTABLE" bs=1 seek=220 conv=notrunc status=none

source "$HOOK"

test -L "$APP_FILES/Moria/Saved"
test "$(readlink "$APP_FILES/Moria/Saved")" = "$WORLD_FILES/Saved"
test -f "$WORLD_FILES/Saved/SaveGamesDedicated/MW_TEST_WORLD.sav"

for filename in MoriaServerConfig.ini MoriaServerPermissions.txt MoriaServerRules.txt; do
    test -L "$APP_FILES/$filename"
    test "$(readlink "$APP_FILES/$filename")" = "$WORLD_FILES/$filename"
done

config="$WORLD_FILES/MoriaServerConfig.ini"
grep -Fqx 'OptionalPassword="friend \"of\" mine"' "$config"
grep -Fqx 'Name="Khazad-dûm Docker World"' "$config"
grep -Fqx 'OptionalWorldFilename="MW_TEST_WORLD.sav"' "$config"
grep -Fqx 'ListenAddress=0.0.0.0' "$config"
grep -Fqx 'ListenPort=17877' "$config"
grep -Fqx 'AdvertiseAddress=game.example.test' "$config"
grep -Fqx 'AdvertisePort=27877' "$config"
grep -Fqx 'Enabled=true' "$config"
grep -Fqx 'ServerFPS=30' "$config"
grep -Fqx 'LoadedAreaLimit=12' "$config"

subsystem="$(od -An -t u2 -j 220 -N 2 "$APP_EXECUTABLE" | tr -d '[:space:]')"
test "$subsystem" = "3"

config_before="$(sha256sum "$config" | awk '{print $1}')"
source "$HOOK"
config_after="$(sha256sum "$config" | awk '{print $1}')"
test "$config_before" = "$config_after"

echo "Moria hook contract test passed"
