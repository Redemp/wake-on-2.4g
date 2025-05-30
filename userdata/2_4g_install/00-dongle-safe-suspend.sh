#!/bin/bash
# 00-dongle-safe-suspend_v24-final.sh
# Prevents system suspend when a 2.4GHz gamepad dongle is still connected and active
# Supports `waitdock` to block suspend and `timeout=N` to delay suspend for disconnection
# Designed for Batocera or similar Linux systems

# === CONFIGURATION SWITCHES ===
ALLOW_SUSPEND_IF_NO_MATCH=false  # If no devices in config match, allow suspend?

CONFIG="/userdata/system/configs/dongles.conf"
DRIVER_PATH="/sys/bus/usb/drivers/usb"
LOGFILE="/userdata/system/logs/dongle_suspend.log"
MAX_LOG_SIZE=102400  # Rotate log if over 100KB

# === FUNCTIONS ===

rotate_log() {
    if [[ -f "$LOGFILE" ]]; then
        local size
        size=$(stat -c %s "$LOGFILE")
        if (( size > MAX_LOG_SIZE )); then
            mv "$LOGFILE" "$LOGFILE.old"
            echo "[LOG] Log rotated due to size > ${MAX_LOG_SIZE} bytes" > "$LOGFILE"
        fi
    fi
}

log() {
    echo "[{ $(date '+%F %T') }] $*"
}

is_controller_connected() {
    local vendor="$1"
    local product="$2"
    for dev in /sys/bus/usb/devices/*; do
        [[ -f "$dev/idVendor" && -f "$dev/idProduct" ]] || continue
        local v=$(<"$dev/idVendor" tr '[:upper:]' '[:lower:]')
        local p=$(<"$dev/idProduct" tr '[:upper:]' '[:lower:]')
        if [[ "$v" == "$vendor" && "$p" == "$product" ]]; then
            log "[ACTIVE CHECK] Controller is still connected (vendor=$vendor, product=$product)"
            return 0
        fi
    done
    return 1
}

# === MAIN LOGIC ===

rotate_log
exec > >(tee -a "$LOGFILE") 2>&1

matched_any=false

while IFS= read -r line; do
    line="${line%%#*}"                       # Remove comments
    line=$(echo "$line" | tr -d ' \t\n\r')  # Strip whitespace
    [[ -z "$line" ]] && continue            # Skip empty lines

    IFS=':' read -r vendor product serial_opt flags <<< "$line"
    [[ -z "$vendor" || -z "$product" ]] && continue

    serial="${serial_opt:-unknown}"
    controller_block_suspend=false
    timeout_secs=0

    IFS=':' read -ra flag_array <<< "$flags"
    for flag in "${flag_array[@]}"; do
        [[ "$flag" == waitdock* ]] && controller_block_suspend=true
        [[ "$flag" == timeout=* ]] && timeout_secs="${flag#timeout=}"
    done

    matched_any=true

    if $controller_block_suspend; then
        if is_controller_connected "$vendor" "$product"; then
            log "[SUSPEND] Controller is connected. Waiting up to ${timeout_secs}s for it to disconnect..."

            for ((i=0; i<timeout_secs; i++)); do
                sleep 1
                if ! is_controller_connected "$vendor" "$product"; then
                    log "[SUSPEND] Controller disconnected after $i seconds. Suspending allowed."
                    exit 0
                fi
            done

            log "[SUSPEND] Controller still connected after ${timeout_secs}s. Restarting EmulationStation instead of suspending..."
			batocera-es-swissknife --restart
			exit 0
        fi
    fi
done < "$CONFIG"

if ! $matched_any && ! $ALLOW_SUSPEND_IF_NO_MATCH; then
    log "[SUSPEND] No known devices matched and ALLOW_SUSPEND_IF_NO_MATCH=false. Suspend blocked."
    exit 1
fi

log "[SUSPEND] No blocking conditions met. Suspending allowed."
exit 0
