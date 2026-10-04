#!/bin/bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/scripts/container/hooks/pre-startup/30_moria.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

FAKE_BIN="$TMP_ROOT/bin"
export WINEPREFIX="$TMP_ROOT/wine"
export MORIA_WINE_COMMAND="$FAKE_BIN/moria-wine"
export MORIA_WINESERVER_COMMAND="$FAKE_BIN/moria-wineserver"
export MORIA_WINETRICKS_CACHE="$TMP_ROOT/winetricks-cache"
export MORIA_TEST_WINETRICKS_LOG="$TMP_ROOT/winetricks.log"
export MORIA_CONFIG_TEMPLATE="$REPO_ROOT/scripts/container/moria-server-config.owned.ini.in"

mkdir -p "$FAKE_BIN" "$WINEPREFIX" "$MORIA_WINETRICKS_CACHE"

cat > "$FAKE_BIN/xvfb-run" <<'EOF'
#!/bin/bash
set -e
while [ "$#" -gt 0 ]; do
    case "$1" in
        --auto-servernum|--server-args=*)
            shift
            ;;
        *)
            break
            ;;
    esac
done
exec "$@"
EOF

cat > "$FAKE_BIN/winetricks" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$MORIA_TEST_WINETRICKS_LOG"
EOF

cat > "$FAKE_BIN/cabextract" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$MORIA_WINE_COMMAND" <<'EOF'
#!/bin/bash
exit 0
EOF

cat > "$MORIA_WINESERVER_COMMAND" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod 0755 \
    "$FAKE_BIN/xvfb-run" \
    "$FAKE_BIN/winetricks" \
    "$FAKE_BIN/cabextract" \
    "$MORIA_WINE_COMMAND" \
    "$MORIA_WINESERVER_COMMAND"
export PATH="$FAKE_BIN:$PATH"

export APP_FILES="$TMP_ROOT/app"
export WORLD_FILES="$TMP_ROOT/world"
export APP_EXECUTABLE="$APP_FILES/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe"

# Exercise every currently known INI setting with non-default values where
# practical. The API must reconcile these keys without erasing future/native
# settings it does not own.
export SERVER_LISTEN_ADDRESS="0.0.0.0"
export SERVER_PORT="17877"
export SERVER_ADVERTISE_ADDRESS="game.example.test"
export SERVER_ADVERTISE_PORT="27877"
export SERVER_INITIAL_CONNECTION_RETRY_TIME="75"
export SERVER_AFTER_DISCONNECTION_RETRY_TIME="675"
export SERVER_CONSOLE_ENABLED="true"
export SERVER_FPS="45"
export SERVER_LOADED_AREA_LIMIT="16"
export SERVER_PASS='friend "of" mine'
export WORLD_NAME='Khazad-dûm Docker World'
export WORLD_FILE='MW_TEST_WORLD.sav'
export WORLD_TYPE="sandbox"
export WORLD_SEED="424242"
export WORLD_DIFFICULTY_PRESET="custom"
export WORLD_DIFFICULTY_COMBAT="high"
export WORLD_DIFFICULTY_ENEMY_AGGRESSION="veryhigh"
export WORLD_DIFFICULTY_SURVIVAL="low"
export WORLD_DIFFICULTY_MINING_DROPS="high"
export WORLD_DIFFICULTY_WORLD_DROPS="veryhigh"
export WORLD_DIFFICULTY_HORDE_FREQUENCY="low"
export WORLD_DIFFICULTY_SIEGE_FREQUENCY="high"
export WORLD_DIFFICULTY_PATROL_FREQUENCY="verylow"
export WORLD_OPTIONAL_DLC="DurinsFolk,FutureDLC"
export WORLD_UPGRADE_OPTIONAL_DLC=""
export SERVER_WORKER_THREADS="3"

log() {
    :
}

mkdir -p \
    "$APP_FILES/Moria/Saved/SaveGamesDedicated" \
    "$APP_FILES/Moria/Binaries/Win64" \
    "$WORLD_FILES"

printf 'save-data\n' > "$APP_FILES/Moria/Saved/SaveGamesDedicated/MW_TEST_WORLD.sav"
printf 'permissions\n' > "$APP_FILES/MoriaServerPermissions.txt"
printf 'rules\n' > "$APP_FILES/MoriaServerRules.txt"

cat > "$APP_FILES/MoriaServerConfig.ini" <<'EOF'
[Main]
OptionalPassword=old

[World]
Name="Old World"
OptionalWorldFilename=

[World.Create]
Type=campaign
Seed=random
Difficulty.Preset=normal
Difficulty.Custom.CombatDifficulty=default
Difficulty.Custom.EnemyAggression=high
Difficulty.Custom.SurvivalDifficulty=default
Difficulty.Custom.MiningDrops=default
Difficulty.Custom.WorldDrops=default
Difficulty.Custom.HordeFrequency=default
Difficulty.Custom.SiegeFrequency=default
Difficulty.Custom.PatrolFrequency=default
OptionalDLC.Array="DurinsFolk"
UpgradeOptionalDLC.Array=""

[Host]
ListenAddress=127.0.0.1
ListenPort=1
AdvertiseAddress=auto
AdvertisePort=-1
InitialConnectionRetryTime=60
AfterDisconnectionRetryTime=600

[Console]
Enabled=false

[Performance]
ServerFPS=30
LoadedAreaLimit=12

[Future]
Experimental.FutureSetting=keep-me
DifficultyXCustomXCombatDifficulty=do-not-touch
EOF

truncate -s 256 "$APP_EXECUTABLE"
printf '\x80\x00\x00\x00' | dd of="$APP_EXECUTABLE" bs=1 seek=60 conv=notrunc status=none
printf 'PE\x00\x00' | dd of="$APP_EXECUTABLE" bs=1 seek=128 conv=notrunc status=none
printf '\x0b\x02' | dd of="$APP_EXECUTABLE" bs=1 seek=152 conv=notrunc status=none
printf '\x02\x00' | dd of="$APP_EXECUTABLE" bs=1 seek=220 conv=notrunc status=none

source "$HOOK"

test -f "$WINEPREFIX/.moria-vcrun2022"
test "$(wc -l < "$MORIA_TEST_WINETRICKS_LOG")" -eq 1
grep -Fqx -- '-q vcrun2022' "$MORIA_TEST_WINETRICKS_LOG"

test -L "$APP_FILES/Moria/Saved"
test "$(readlink "$APP_FILES/Moria/Saved")" = "$WORLD_FILES/Saved"
test -f "$WORLD_FILES/Saved/SaveGamesDedicated/MW_TEST_WORLD.sav"

for filename in MoriaServerConfig.ini MoriaServerPermissions.txt MoriaServerRules.txt; do
    test -L "$APP_FILES/$filename"
    test "$(readlink "$APP_FILES/$filename")" = "$WORLD_FILES/$filename"
done

config="$WORLD_FILES/MoriaServerConfig.ini"
for expected in \
    'OptionalPassword="friend \"of\" mine"' \
    'Name="Khazad-dûm Docker World"' \
    'OptionalWorldFilename="MW_TEST_WORLD.sav"' \
    'Type=sandbox' \
    'Seed=424242' \
    'Difficulty.Preset=custom' \
    'Difficulty.Custom.CombatDifficulty=high' \
    'Difficulty.Custom.EnemyAggression=veryhigh' \
    'Difficulty.Custom.SurvivalDifficulty=low' \
    'Difficulty.Custom.MiningDrops=high' \
    'Difficulty.Custom.WorldDrops=veryhigh' \
    'Difficulty.Custom.HordeFrequency=low' \
    'Difficulty.Custom.SiegeFrequency=high' \
    'Difficulty.Custom.PatrolFrequency=verylow' \
    'OptionalDLC.Array="DurinsFolk,FutureDLC"' \
    'UpgradeOptionalDLC.Array=""' \
    'ListenAddress=0.0.0.0' \
    'ListenPort=17877' \
    'AdvertiseAddress=game.example.test' \
    'AdvertisePort=27877' \
    'InitialConnectionRetryTime=75' \
    'AfterDisconnectionRetryTime=675' \
    'Enabled=true' \
    'ServerFPS=45' \
    'LoadedAreaLimit=16' \
    'Experimental.FutureSetting=keep-me' \
    'DifficultyXCustomXCombatDifficulty=do-not-touch'
do
    grep -Fqx "$expected" "$config"
done

subsystem="$(od -An -t u2 -j 220 -N 2 "$APP_EXECUTABLE" | tr -d '[:space:]')"
test "$subsystem" = "3"

# Same API + same native state must not replace the persistent INI. Content
# equality alone would miss a pointless atomic rewrite, so retain the inode too.
config_before="$(sha256sum "$config" | awk '{print $1}')"
inode_before="$(stat -c %i "$config")"
source "$HOOK"
config_after="$(sha256sum "$config" | awk '{print $1}')"
inode_after="$(stat -c %i "$config")"
test "$config_before" = "$config_after"
test "$inode_before" = "$inode_after"
test "$(wc -l < "$MORIA_TEST_WINETRICKS_LOG")" -eq 1

# Optional DLC is opt-in. Unsetting the variable must converge to an empty
# native value so a newly created world does not unexpectedly require an
# expansion. Explicit DLC remains supported when the operator chooses it.
unset WORLD_OPTIONAL_DLC
source "$HOOK"
grep -Fqx 'OptionalDLC.Array=""' "$config"
export WORLD_OPTIONAL_DLC="DurinsFolk"
source "$HOOK"
grep -Fqx 'OptionalDLC.Array="DurinsFolk"' "$config"

# Reproduce the production failure where /app survives with the correct Saved
# symlink but /world is fresh or incomplete. The hook must repair the target
# directory without touching an already-converged INI.
rm -rf "$WORLD_FILES/Saved"
test -L "$APP_FILES/Moria/Saved"
test "$(readlink "$APP_FILES/Moria/Saved")" = "$WORLD_FILES/Saved"
test ! -e "$WORLD_FILES/Saved"

inode_before="$(stat -c %i "$config")"
source "$HOOK"

test -d "$WORLD_FILES/Saved"
test -L "$APP_FILES/Moria/Saved"
test "$(readlink "$APP_FILES/Moria/Saved")" = "$WORLD_FILES/Saved"
touch "$WORLD_FILES/Saved/.write-probe"
rm -f "$WORLD_FILES/Saved/.write-probe"
test "$(stat -c %i "$config")" = "$inode_before"
test "$(wc -l < "$MORIA_TEST_WINETRICKS_LOG")" -eq 1

echo "Moria hook contract test passed"
