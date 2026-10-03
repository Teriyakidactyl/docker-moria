#!/bin/bash

set -Eeuo pipefail

HOOK_NAME="30_moria.sh"

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

validate_single_line() {
    local name="$1"
    local value="$2"

    if [[ "$value" == *quote_ini_string() {
    local value="$1"
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        fail "INI string values may not contain newlines"
        return 1
    fi
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

    tmp="$(mktemp)"
    MORIA_INI_VALUE="$value" awk -v target="[$section]" -v key="$key" '
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
            in_target = ($0 == target)
            if (in_target) {
                section_seen = 1
            }
            print
            next
        }

        {
            if (in_target && $0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
                if (!key_written) {
                    print key "=" value
                    key_written = 1
                }
                next
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
    mv "$tmp" "$file"
}

persist_path() {
    local source_path="$1"
    local target_path="$2"
    local source_parent

    source_parent="$(dirname "$source_path")"
    mkdir -p "$source_parent" "$(dirname "$target_path")"

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

patch_console_subsystem() {
    local executable="$1"
    local pe_offset magic subsystem_offset subsystem

    [ -f "$executable" ] || {
        fail "Moria executable not found at $executable"
        return 1
    }

    pe_offset="$(od -An -t u4 -j 60 -N 4 "$executable" | tr -d '[:space:]')"
    [[ "$pe_offset" =~ ^[0-9]+$ ]] || {
        fail "could not read PE header offset"
        return 1
    }

    local signature
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

validate_integer_range SERVER_PORT "${SERVER_PORT:-7777}" 1 65535
validate_integer_range SERVER_ADVERTISE_PORT "${SERVER_ADVERTISE_PORT:-7777}" 1 65535
validate_integer_range SERVER_WORKER_THREADS "${SERVER_WORKER_THREADS:-4}" 1 4
validate_single_line SERVER_LISTEN_ADDRESS "${SERVER_LISTEN_ADDRESS:-0.0.0.0}"
validate_single_line SERVER_ADVERTISE_ADDRESS "${SERVER_ADVERTISE_ADDRESS:-}"

saved_target="$WORLD_FILES/Saved"
persist_path "$APP_FILES/Moria/Saved" "$saved_target"

for filename in MoriaServerConfig.ini MoriaServerPermissions.txt MoriaServerRules.txt; do
    persist_path "$APP_FILES/$filename" "$WORLD_FILES/$filename"
done

config_file="$WORLD_FILES/MoriaServerConfig.ini"
if [ ! -f "$config_file" ]; then
    log "Creating initial Moria server configuration" "$HOOK_NAME"
    cat > "$config_file" <<'EOF'
[Main]
OptionalPassword=""

[World]
Name="Moria Docker World"
OptionalWorldFilename=""

[Host]
ListenAddress=0.0.0.0
ListenPort=7777
AdvertisePort=7777

[Console]
Enabled=true
EOF
fi

password_value="$(quote_ini_string "${SERVER_PASS:-}")"
world_name_value="$(quote_ini_string "${WORLD_NAME:-Moria Docker World}")"
world_file_value="$(quote_ini_string "${WORLD_FILE:-}")"

set_ini_value "$config_file" Main OptionalPassword "$password_value"
set_ini_value "$config_file" World Name "$world_name_value"
set_ini_value "$config_file" World OptionalWorldFilename "$world_file_value"
set_ini_value "$config_file" Host ListenAddress "${SERVER_LISTEN_ADDRESS:-0.0.0.0}"
set_ini_value "$config_file" Host ListenPort "${SERVER_PORT:-7777}"
set_ini_value "$config_file" Host AdvertisePort "${SERVER_ADVERTISE_PORT:-7777}"

if [ -n "${SERVER_ADVERTISE_ADDRESS:-}" ]; then
    set_ini_value "$config_file" Host AdvertiseAddress "${SERVER_ADVERTISE_ADDRESS}"
fi

# Console input must remain enabled for SIGINT to save and close the online session.
set_ini_value "$config_file" Console Enabled true

patch_console_subsystem "${APP_EXECUTABLE:-$APP_FILES/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe}"

log "Moria persistence and configuration are ready" "$HOOK_NAME"
\n'* || "$value" == *quote_ini_string() {
    local value="$1"
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        fail "INI string values may not contain newlines"
        return 1
    fi
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

    tmp="$(mktemp)"
    MORIA_INI_VALUE="$value" awk -v target="[$section]" -v key="$key" '
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
            in_target = ($0 == target)
            if (in_target) {
                section_seen = 1
            }
            print
            next
        }

        {
            if (in_target && $0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
                if (!key_written) {
                    print key "=" value
                    key_written = 1
                }
                next
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
    mv "$tmp" "$file"
}

persist_path() {
    local source_path="$1"
    local target_path="$2"
    local source_parent

    source_parent="$(dirname "$source_path")"
    mkdir -p "$source_parent" "$(dirname "$target_path")"

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

patch_console_subsystem() {
    local executable="$1"
    local pe_offset magic subsystem_offset subsystem

    [ -f "$executable" ] || {
        fail "Moria executable not found at $executable"
        return 1
    }

    pe_offset="$(od -An -t u4 -j 60 -N 4 "$executable" | tr -d '[:space:]')"
    [[ "$pe_offset" =~ ^[0-9]+$ ]] || {
        fail "could not read PE header offset"
        return 1
    }

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

validate_integer_range SERVER_PORT "${SERVER_PORT:-7777}" 1 65535
validate_integer_range SERVER_ADVERTISE_PORT "${SERVER_ADVERTISE_PORT:-7777}" 1 65535
validate_integer_range SERVER_WORKER_THREADS "${SERVER_WORKER_THREADS:-4}" 1 4

saved_target="$WORLD_FILES/Saved"
persist_path "$APP_FILES/Moria/Saved" "$saved_target"

for filename in MoriaServerConfig.ini MoriaServerPermissions.txt MoriaServerRules.txt; do
    persist_path "$APP_FILES/$filename" "$WORLD_FILES/$filename"
done

config_file="$WORLD_FILES/MoriaServerConfig.ini"
if [ ! -f "$config_file" ]; then
    log "Creating initial Moria server configuration" "$HOOK_NAME"
    cat > "$config_file" <<'EOF'
[Main]
OptionalPassword=""

[World]
Name="Moria Docker World"
OptionalWorldFilename=""

[Host]
ListenAddress=0.0.0.0
ListenPort=7777
AdvertisePort=7777

[Console]
Enabled=true
EOF
fi

password_value="$(quote_ini_string "${SERVER_PASS:-}")"
world_name_value="$(quote_ini_string "${WORLD_NAME:-Moria Docker World}")"
world_file_value="$(quote_ini_string "${WORLD_FILE:-}")"

set_ini_value "$config_file" Main OptionalPassword "$password_value"
set_ini_value "$config_file" World Name "$world_name_value"
set_ini_value "$config_file" World OptionalWorldFilename "$world_file_value"
set_ini_value "$config_file" Host ListenAddress "${SERVER_LISTEN_ADDRESS:-0.0.0.0}"
set_ini_value "$config_file" Host ListenPort "${SERVER_PORT:-7777}"
set_ini_value "$config_file" Host AdvertisePort "${SERVER_ADVERTISE_PORT:-7777}"

if [ -n "${SERVER_ADVERTISE_ADDRESS:-}" ]; then
    set_ini_value "$config_file" Host AdvertiseAddress "${SERVER_ADVERTISE_ADDRESS}"
fi

# Console input must remain enabled for SIGINT to save and close the online session.
set_ini_value "$config_file" Console Enabled true

patch_console_subsystem "${APP_EXECUTABLE:-$APP_FILES/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe}"

log "Moria persistence and configuration are ready" "$HOOK_NAME"
\r'* ]]; then
        fail "$name may not contain newlines"
        return 1
    fi
}

quote_ini_string() {
    local value="$1"
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        fail "INI string values may not contain newlines"
        return 1
    fi
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

    tmp="$(mktemp)"
    MORIA_INI_VALUE="$value" awk -v target="[$section]" -v key="$key" '
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
            in_target = ($0 == target)
            if (in_target) {
                section_seen = 1
            }
            print
            next
        }

        {
            if (in_target && $0 ~ "^[[:space:]]*" key "[[:space:]]*=") {
                if (!key_written) {
                    print key "=" value
                    key_written = 1
                }
                next
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
    mv "$tmp" "$file"
}

persist_path() {
    local source_path="$1"
    local target_path="$2"
    local source_parent

    source_parent="$(dirname "$source_path")"
    mkdir -p "$source_parent" "$(dirname "$target_path")"

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

patch_console_subsystem() {
    local executable="$1"
    local pe_offset magic subsystem_offset subsystem

    [ -f "$executable" ] || {
        fail "Moria executable not found at $executable"
        return 1
    }

    pe_offset="$(od -An -t u4 -j 60 -N 4 "$executable" | tr -d '[:space:]')"
    [[ "$pe_offset" =~ ^[0-9]+$ ]] || {
        fail "could not read PE header offset"
        return 1
    }

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

validate_integer_range SERVER_PORT "${SERVER_PORT:-7777}" 1 65535
validate_integer_range SERVER_ADVERTISE_PORT "${SERVER_ADVERTISE_PORT:-7777}" 1 65535
validate_integer_range SERVER_WORKER_THREADS "${SERVER_WORKER_THREADS:-4}" 1 4

saved_target="$WORLD_FILES/Saved"
persist_path "$APP_FILES/Moria/Saved" "$saved_target"

for filename in MoriaServerConfig.ini MoriaServerPermissions.txt MoriaServerRules.txt; do
    persist_path "$APP_FILES/$filename" "$WORLD_FILES/$filename"
done

config_file="$WORLD_FILES/MoriaServerConfig.ini"
if [ ! -f "$config_file" ]; then
    log "Creating initial Moria server configuration" "$HOOK_NAME"
    cat > "$config_file" <<'EOF'
[Main]
OptionalPassword=""

[World]
Name="Moria Docker World"
OptionalWorldFilename=""

[Host]
ListenAddress=0.0.0.0
ListenPort=7777
AdvertisePort=7777

[Console]
Enabled=true
EOF
fi

password_value="$(quote_ini_string "${SERVER_PASS:-}")"
world_name_value="$(quote_ini_string "${WORLD_NAME:-Moria Docker World}")"
world_file_value="$(quote_ini_string "${WORLD_FILE:-}")"

set_ini_value "$config_file" Main OptionalPassword "$password_value"
set_ini_value "$config_file" World Name "$world_name_value"
set_ini_value "$config_file" World OptionalWorldFilename "$world_file_value"
set_ini_value "$config_file" Host ListenAddress "${SERVER_LISTEN_ADDRESS:-0.0.0.0}"
set_ini_value "$config_file" Host ListenPort "${SERVER_PORT:-7777}"
set_ini_value "$config_file" Host AdvertisePort "${SERVER_ADVERTISE_PORT:-7777}"

if [ -n "${SERVER_ADVERTISE_ADDRESS:-}" ]; then
    set_ini_value "$config_file" Host AdvertiseAddress "${SERVER_ADVERTISE_ADDRESS}"
fi

# Console input must remain enabled for SIGINT to save and close the online session.
set_ini_value "$config_file" Console Enabled true

patch_console_subsystem "${APP_EXECUTABLE:-$APP_FILES/Moria/Binaries/Win64/MoriaServer-Win64-Shipping.exe}"

log "Moria persistence and configuration are ready" "$HOOK_NAME"
