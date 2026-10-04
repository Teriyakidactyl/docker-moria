#!/bin/bash

set -Eeuo pipefail

HOOK_NAME="30_moria.sh"
MORIA_CONFIG_TEMPLATE="${MORIA_CONFIG_TEMPLATE:-/usr/local/share/moria/moria-server-config.owned.ini.in}"

fail() {
    log "ERROR: $*" "$HOOK_NAME"
    return 1
}

validate_integer_range() {
    local name="$1"
    local value="$2"
    local min="$3"
    local max="$4"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < min || value > max )); then
        fail "$name must be an integer from $min through $max; got '$value'"
        return 1
    fi
}

validate_nonnegative_integer() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        fail "$name must be a non-negative integer; got '$value'"
        return 1
    fi
}

validate_positive_integer() {
    local name="$1"
    local value="$2"

    if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 )); then
        fail "$name must be a positive integer; got '$value'"
        return 1
    fi
}

validate_port_or_default() {
    local name="$1"
    local value="$2"

    if [ "$value" = "-1" ]; then
        return 0
    fi
    validate_integer_range "$name" "$value" 1 65535
}

validate_choice() {
    local name="$1"
    local value="$2"
    shift 2
    local candidate

    for candidate in "$@"; do
        if [ "$value" = "$candidate" ]; then
            return 0
        fi
    done

    fail "$name must be one of: $*; got '$value'"
    return 1
}

validate_boolean() {
    local name="$1"
    local value="${2,,}"

    validate_choice "$name" "$value" true false
}

validate_seed() {
    local value="$1"

    if [ "$value" = "random" ] || [[ "$value" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi

    fail "WORLD_SEED must be 'random' or an integer; got '$value'"
    return 1
}

validate_single_line() {
    local name="$1"
    local value="$2"

    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        fail "$name may not contain newlines"
        return 1
    fi
}

quote_ini_string() {
    local value="$1"

    validate_single_line "INI string value" "$value"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

set_ini_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    local tmp

    # Match the key text exactly instead of interpreting it as a regex. Moria
    # uses dotted keys such as Difficulty.Custom.CombatDifficulty; treating
    # those dots as regex wildcards can update an unrelated future key.
    tmp="$(mktemp "${file}.rewrite.XXXXXX")"
    MORIA_INI_VALUE="$value" awk -v target="[$section]" -v key="$key" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }

        BEGIN {
            value = ENVIRON["MORIA_INI_VALUE"]
            in_target = 0
            section_seen = 0
            key_written = 0
        }

        /^\[[^]]+\][[:space:]]*$/ {
            if (in_target && !key_written) {
                print key "=" value
                key_written = 1
            }

            header = $0
            sub(/[[:space:]]+$/, "", header)
            in_target = (header == target)
            if (in_target) {
                section_seen = 1
            }
            print
            next
        }

        {
            if (in_target) {
                separator = index($0, "=")
                if (separator > 0) {
                    existing_key = trim(substr($0, 1, separator - 1))
                    if (existing_key == key) {
                        if (!key_written) {
                            print key "=" value
                            key_written = 1
                        }
                        next
                    }
                }
            }
            print
        }

        END {
            if (in_target && !key_written) {
                print key "=" value
            } else if (!section_seen) {
                print ""
                print target
                print key "=" value
            }
        }
    ' "$file" > "$tmp"
    chmod --reference="$file" "$tmp" 2>/dev/null || true
    mv "$tmp" "$file"
}

reconcile_ini() {
    local file="$1"
    local desired="$2"
    local candidate section line key value

    if [ ! -f "$file" ]; then
        log "Creating initial Moria server configuration" "$HOOK_NAME"
        install -m 0600 "$desired" "$file"
        return 0
    fi

    candidate="$(mktemp "${file}.candidate.XXXXXX")"
    cp "$file" "$candidate"
    chmod --reference="$file" "$candidate" 2>/dev/null || true

    section=""
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \[*\])
                section="${line#\[}"
                section="${section%\]}"
                ;;
            ""|\;*|\#*)
                ;;
            *=*)
                [ -n "$section" ] || {
                    rm -f "$candidate"
                    fail "desired Moria INI key appeared before a section: $line"
                    return 1
                }
                key="${line%%=*}"
                value="${line#*=}"
                set_ini_value "$candidate" "$section" "$key" "$value"
                ;;
        esac
    done < "$desired"

    # The persisted file is operator/game state. Do not replace it merely
    # because startup ran again. Only move the candidate into place when one of
    # the API-owned values actually changed; unknown settings remain untouched.
    if cmp -s "$candidate" "$file"; then
        rm -f "$candidate"
    else
        mv "$candidate" "$file"
        log "Updated container-owned Moria server settings" "$HOOK_NAME"
    fi
}

persist_path() {
    local source_path="$1"
    local target_path="$2"
    local target_kind="${3:-file}"
    local source_parent

    source_parent="$(dirname "$source_path")"
    mkdir -p "$source_parent" "$(dirname "$target_path")"

    # A persistent /app volume can retain the correct symlink while /world is
    # replaced, freshly restored, or otherwise lacks the directory it points
    # at. A symlink-only fast path would then preserve a dangling link and Moria
    # would fail when creating Saved/Config/Status.json or its first world save.
    # Directory callers must therefore materialize the target before we decide
    # that an already-correct symlink is converged. File targets are different:
    # the application may legitimately create the target file later.
    if [ "$target_kind" = "directory" ]; then
        mkdir -p "$target_path"
    fi

    if [ -L "$source_path" ]; then
        if [ "$(readlink "$source_path")" = "$target_path" ]; then
            return 0
        fi
        rm -f "$source_path"
    elif [ -d "$source_path" ]; then
        mkdir -p "$target_path"
        cp -a "$source_path/." "$target_path/"
        rm -rf "$source_path"
    elif [ -e "$source_path" ]; then
        if [ ! -e "$target_path" ]; then
            mv "$source_path" "$target_path"
        else
            rm -f "$source_path"
        fi
    fi

    ln -s "$target_path" "$source_path"
}

ensure_vcrun2022() {
    local marker
    local wine_command
    local wineserver_command
    local cache_dir

    : "${WINEPREFIX:?WINEPREFIX is required}"

    marker="$WINEPREFIX/.moria-vcrun2022"
    if [ -f "$marker" ]; then
        log "Visual C++ 2015-2022 runtime already installed" "$HOOK_NAME"
        return 0
    fi

    command -v winetricks >/dev/null 2>&1 || {
        fail "winetricks is required to install vcrun2022"
        return 1
    }
    command -v xvfb-run >/dev/null 2>&1 || {
        fail "xvfb-run is required to install vcrun2022"
        return 1
    }
    command -v cabextract >/dev/null 2>&1 || {
        fail "cabextract is required to install vcrun2022"
        return 1
    }

    wine_command="${MORIA_WINE_COMMAND:-/usr/local/bin/moria-wine}"
    wineserver_command="${MORIA_WINESERVER_COMMAND:-/usr/local/bin/moria-wineserver}"
    cache_dir="${MORIA_WINETRICKS_CACHE:-$WINEPREFIX/.winetricks-cache}"

    [ -x "$wine_command" ] || {
        fail "Moria Wine command is not executable: $wine_command"
        return 1
    }
    [ -x "$wineserver_command" ] || {
        fail "Moria wineserver command is not executable: $wineserver_command"
        return 1
    }

    mkdir -p "$cache_dir"

    log "Installing Visual C++ 2015-2022 runtime into $WINEPREFIX" "$HOOK_NAME"
    WINE="$wine_command" \
        WINE64="$wine_command" \
        WINESERVER="$wineserver_command" \
        W_CACHE="$cache_dir" \
        xvfb-run --auto-servernum \
            "--server-args=-screen 0 640x480x24:32 -nolisten tcp" \
            winetricks -q vcrun2022

    touch "$marker"
    log "Visual C++ 2015-2022 runtime is ready" "$HOOK_NAME"
}

patch_console_subsystem() {
    local executable="$1"
    local pe_offset signature magic subsystem_offset subsystem

    [ -f "$executable" ] || {
        fail "Moria executable not found at $executable"
        return 1
    }

    pe_offset="$(od -An -t u4 -j 60 -N 4 "$executable" | tr -d '[:space:]')"
    [[ "$pe_offset" =~ ^[0-9]+$ ]] || {
        fail "could not read PE header offset"
        return 1
    }

    signature="$(od -An -t u4 -j "$pe_offset" -N 4 "$executable" | tr -d '[:space:]')"
    if [ "$signature" != "17744" ]; then
        fail "unexpected PE signature: $signature"
        return 1
    fi

    magic="$(od -An -t x2 -j "$((pe_offset + 24))" -N 2 "$executable" | tr -d '[:space:]')"
    if [ "$magic" != "020b" ]; then
        fail "unexpected PE32+ optional-header magic: $magic"
        return 1
    fi

    subsystem_offset=$((pe_offset + 92))
    subsystem="$(od -An -t u2 -j "$subsystem_offset" -N 2 "$executable" | tr -d '[:space:]')"

    case "$subsystem" in
        3)
            log "Moria executable already uses the console subsystem" "$HOOK_NAME"
            ;;
        2)
            log "Patching Moria executable from GUI to console subsystem" "$HOOK_NAME"
            printf '\x03\x00' | dd of="$executable" bs=1 seek="$subsystem_offset" conv=notrunc status=none
            subsystem="$(od -An -t u2 -j "$subsystem_offset" -N 2 "$executable" | tr -d '[:space:]')"
            [ "$subsystem" = "3" ] || {
                fail "console-subsystem patch verification failed"
                return 1
            }
            ;;
        *)
            fail "unexpected PE subsystem value: $subsystem"
            return 1
            ;;
    esac
}

render_desired_config() {
    local output="$1"
    local world_type world_seed difficulty_preset
    local difficulty_combat difficulty_enemy_aggression difficulty_survival
    local difficulty_mining_drops difficulty_world_drops difficulty_horde_frequency
    local difficulty_siege_frequency difficulty_patrol_frequency
    local console_enabled advertise_address

    command -v envsubst >/dev/null 2>&1 || {
        fail "envsubst is required by the Moria configuration projection"
        return 1
    }
    [ -f "$MORIA_CONFIG_TEMPLATE" ] || {
        fail "Moria configuration template not found at $MORIA_CONFIG_TEMPLATE"
        return 1
    }

    validate_integer_range SERVER_PORT "${SERVER_PORT:-7777}" 1 65535
    validate_port_or_default SERVER_ADVERTISE_PORT "${SERVER_ADVERTISE_PORT:-7777}"
    validate_integer_range SERVER_WORKER_THREADS "${SERVER_WORKER_THREADS:-4}" 1 4
    validate_nonnegative_integer SERVER_INITIAL_CONNECTION_RETRY_TIME "${SERVER_INITIAL_CONNECTION_RETRY_TIME:-60}"
    validate_nonnegative_integer SERVER_AFTER_DISCONNECTION_RETRY_TIME "${SERVER_AFTER_DISCONNECTION_RETRY_TIME:-600}"
    validate_positive_integer SERVER_FPS "${SERVER_FPS:-60}"
    validate_integer_range SERVER_LOADED_AREA_LIMIT "${SERVER_LOADED_AREA_LIMIT:-12}" 4 32

    validate_single_line SERVER_LISTEN_ADDRESS "${SERVER_LISTEN_ADDRESS:-0.0.0.0}"
    validate_single_line SERVER_ADVERTISE_ADDRESS "${SERVER_ADVERTISE_ADDRESS:-auto}"
    validate_single_line SERVER_PASS "${SERVER_PASS:-}"
    validate_single_line WORLD_NAME "${WORLD_NAME:-Moria Docker World}"
    validate_single_line WORLD_FILE "${WORLD_FILE:-}"
    validate_single_line WORLD_OPTIONAL_DLC "${WORLD_OPTIONAL_DLC:-}"
    validate_single_line WORLD_UPGRADE_OPTIONAL_DLC "${WORLD_UPGRADE_OPTIONAL_DLC:-}"

    world_type="${WORLD_TYPE:-campaign}"
    world_type="${world_type,,}"
    validate_choice WORLD_TYPE "$world_type" campaign sandbox

    world_seed="${WORLD_SEED:-random}"
    if [[ "${world_seed,,}" = "random" ]]; then
        world_seed="random"
    fi
    validate_seed "$world_seed"

    difficulty_preset="${WORLD_DIFFICULTY_PRESET:-normal}"
    difficulty_preset="${difficulty_preset,,}"
    validate_choice WORLD_DIFFICULTY_PRESET "$difficulty_preset" story solo normal hard custom

    difficulty_combat="${WORLD_DIFFICULTY_COMBAT:-default}"
    difficulty_enemy_aggression="${WORLD_DIFFICULTY_ENEMY_AGGRESSION:-high}"
    difficulty_survival="${WORLD_DIFFICULTY_SURVIVAL:-default}"
    difficulty_mining_drops="${WORLD_DIFFICULTY_MINING_DROPS:-default}"
    difficulty_world_drops="${WORLD_DIFFICULTY_WORLD_DROPS:-default}"
    difficulty_horde_frequency="${WORLD_DIFFICULTY_HORDE_FREQUENCY:-default}"
    difficulty_siege_frequency="${WORLD_DIFFICULTY_SIEGE_FREQUENCY:-default}"
    difficulty_patrol_frequency="${WORLD_DIFFICULTY_PATROL_FREQUENCY:-default}"

    difficulty_combat="${difficulty_combat,,}"
    difficulty_enemy_aggression="${difficulty_enemy_aggression,,}"
    difficulty_survival="${difficulty_survival,,}"
    difficulty_mining_drops="${difficulty_mining_drops,,}"
    difficulty_world_drops="${difficulty_world_drops,,}"
    difficulty_horde_frequency="${difficulty_horde_frequency,,}"
    difficulty_siege_frequency="${difficulty_siege_frequency,,}"
    difficulty_patrol_frequency="${difficulty_patrol_frequency,,}"

    local difficulty_name difficulty_value
    while IFS='=' read -r difficulty_name difficulty_value; do
        validate_choice "$difficulty_name" "$difficulty_value" verylow low default high veryhigh
    done <<EOF
WORLD_DIFFICULTY_COMBAT=$difficulty_combat
WORLD_DIFFICULTY_ENEMY_AGGRESSION=$difficulty_enemy_aggression
WORLD_DIFFICULTY_SURVIVAL=$difficulty_survival
WORLD_DIFFICULTY_MINING_DROPS=$difficulty_mining_drops
WORLD_DIFFICULTY_WORLD_DROPS=$difficulty_world_drops
WORLD_DIFFICULTY_HORDE_FREQUENCY=$difficulty_horde_frequency
WORLD_DIFFICULTY_SIEGE_FREQUENCY=$difficulty_siege_frequency
WORLD_DIFFICULTY_PATROL_FREQUENCY=$difficulty_patrol_frequency
EOF

    console_enabled="${SERVER_CONSOLE_ENABLED:-true}"
    console_enabled="${console_enabled,,}"
    validate_boolean SERVER_CONSOLE_ENABLED "$console_enabled"
    if [ "$console_enabled" = "false" ]; then
        # The upstream setting is exposed for completeness, but the container's
        # graceful stop path depends on Moria accepting SIGINT through its
        # console subsystem. False is therefore an explicit durability tradeoff.
        log "WARNING: SERVER_CONSOLE_ENABLED=false disables graceful console shutdown; container stop may escalate to SIGKILL" "$HOOK_NAME"
    fi

    advertise_address="${SERVER_ADVERTISE_ADDRESS:-auto}"

    export MORIA_CFG_OPTIONAL_PASSWORD
    export MORIA_CFG_WORLD_NAME MORIA_CFG_WORLD_FILE
    export MORIA_CFG_WORLD_TYPE MORIA_CFG_WORLD_SEED MORIA_CFG_DIFFICULTY_PRESET
    export MORIA_CFG_DIFFICULTY_COMBAT MORIA_CFG_DIFFICULTY_ENEMY_AGGRESSION
    export MORIA_CFG_DIFFICULTY_SURVIVAL MORIA_CFG_DIFFICULTY_MINING_DROPS
    export MORIA_CFG_DIFFICULTY_WORLD_DROPS MORIA_CFG_DIFFICULTY_HORDE_FREQUENCY
    export MORIA_CFG_DIFFICULTY_SIEGE_FREQUENCY MORIA_CFG_DIFFICULTY_PATROL_FREQUENCY
    export MORIA_CFG_OPTIONAL_DLC MORIA_CFG_UPGRADE_OPTIONAL_DLC
    export MORIA_CFG_LISTEN_ADDRESS MORIA_CFG_LISTEN_PORT
    export MORIA_CFG_ADVERTISE_ADDRESS MORIA_CFG_ADVERTISE_PORT
    export MORIA_CFG_INITIAL_CONNECTION_RETRY_TIME MORIA_CFG_AFTER_DISCONNECTION_RETRY_TIME
    export MORIA_CFG_CONSOLE_ENABLED MORIA_CFG_SERVER_FPS MORIA_CFG_LOADED_AREA_LIMIT

    MORIA_CFG_OPTIONAL_PASSWORD="$(quote_ini_string "${SERVER_PASS:-}")"
    MORIA_CFG_WORLD_NAME="$(quote_ini_string "${WORLD_NAME:-Moria Docker World}")"
    MORIA_CFG_WORLD_FILE="$(quote_ini_string "${WORLD_FILE:-}")"
    MORIA_CFG_WORLD_TYPE="$world_type"
    MORIA_CFG_WORLD_SEED="$world_seed"
    MORIA_CFG_DIFFICULTY_PRESET="$difficulty_preset"
    MORIA_CFG_DIFFICULTY_COMBAT="$difficulty_combat"
    MORIA_CFG_DIFFICULTY_ENEMY_AGGRESSION="$difficulty_enemy_aggression"
    MORIA_CFG_DIFFICULTY_SURVIVAL="$difficulty_survival"
    MORIA_CFG_DIFFICULTY_MINING_DROPS="$difficulty_mining_drops"
    MORIA_CFG_DIFFICULTY_WORLD_DROPS="$difficulty_world_drops"
    MORIA_CFG_DIFFICULTY_HORDE_FREQUENCY="$difficulty_horde_frequency"
    MORIA_CFG_DIFFICULTY_SIEGE_FREQUENCY="$difficulty_siege_frequency"
    MORIA_CFG_DIFFICULTY_PATROL_FREQUENCY="$difficulty_patrol_frequency"
    MORIA_CFG_OPTIONAL_DLC="$(quote_ini_string "${WORLD_OPTIONAL_DLC:-}")"
    MORIA_CFG_UPGRADE_OPTIONAL_DLC="$(quote_ini_string "${WORLD_UPGRADE_OPTIONAL_DLC:-}")"
    MORIA_CFG_LISTEN_ADDRESS="${SERVER_LISTEN_ADDRESS:-0.0.0.0}"
    MORIA_CFG_LISTEN_PORT="${SERVER_PORT:-7777}"
    MORIA_CFG_ADVERTISE_ADDRESS="$advertise_address"
    MORIA_CFG_ADVERTISE_PORT="${SERVER_ADVERTISE_PORT:-7777}"
    MORIA_CFG_INITIAL_CONNECTION_RETRY_TIME="${SERVER_INITIAL_CONNECTION_RETRY_TIME:-60}"
    MORIA_CFG_AFTER_DISCONNECTION_RETRY_TIME="${SERVER_AFTER_DISCONNECTION_RETRY_TIME:-600}"
    MORIA_CFG_CONSOLE_ENABLED="$console_enabled"
    MORIA_CFG_SERVER_FPS="${SERVER_FPS:-60}"
    MORIA_CFG_LOADED_AREA_LIMIT="${SERVER_LOADED_AREA_LIMIT:-12}"

    # Use an explicit allow-list. A bare envsubst would make every shell
    # variable name appearing in the template part of the container API.
    local substitution_vars
    substitution_vars='${MORIA_CFG_OPTIONAL_PASSWORD} ${MORIA_CFG_WORLD_NAME} ${MORIA_CFG_WORLD_FILE} ${MORIA_CFG_WORLD_TYPE} ${MORIA_CFG_WORLD_SEED} ${MORIA_CFG_DIFFICULTY_PRESET} ${MORIA_CFG_DIFFICULTY_COMBAT} ${MORIA_CFG_DIFFICULTY_ENEMY_AGGRESSION} ${MORIA_CFG_DIFFICULTY_SURVIVAL} ${MORIA_CFG_DIFFICULTY_MINING_DROPS} ${MORIA_CFG_DIFFICULTY_WORLD_DROPS} ${MORIA_CFG_DIFFICULTY_HORDE_FREQUENCY} ${MORIA_CFG_DIFFICULTY_SIEGE_FREQUENCY} ${MORIA_CFG_DIFFICULTY_PATROL_FREQUENCY} ${MORIA_CFG_OPTIONAL_DLC} ${MORIA_CFG_UPGRADE_OPTIONAL_DLC} ${MORIA_CFG_LISTEN_ADDRESS} ${MORIA_CFG_LISTEN_PORT} ${MORIA_CFG_ADVERTISE_ADDRESS} ${MORIA_CFG_ADVERTISE_PORT} ${MORIA_CFG_INITIAL_CONNECTION_RETRY_TIME} ${MORIA_CFG_AFTER_DISCONNECTION_RETRY_TIME} ${MORIA_CFG_CONSOLE_ENABLED} ${MORIA_CFG_SERVER_FPS} ${MORIA_CFG_LOADED_AREA_LIMIT}'
    envsubst "$substitution_vars" < "$MORIA_CONFIG_TEMPLATE" > "$output"
}

ensure_vcrun2022

saved_target="$WORLD_FILES/Saved"
persist_path "$APP_FILES/Moria/Saved" "$saved_target" directory

for filename in MoriaServerConfig.ini MoriaServerPermissions.txt MoriaServerRules.txt; do
    persist_path "$APP_FILES/$filename" "$WORLD_FILES/$filename"
done

desired_config="$(mktemp)"
render_desired_config "$desired_config"
reconcile_ini "$WORLD_FILES/MoriaServerConfig.ini" "$desired_config"
rm -f "$desired_config"

patch_console_subsystem "${APP_EXECUTABLE:-$APP_FILES/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe}"

log "Moria persistence and configuration are ready" "$HOOK_NAME"
