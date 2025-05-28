#!/bin/bash

exec > >(tee -a "/userdata/system/logs/dongle_suspend.log") 2>&1

CONFIG="/userdata/system/configs/dongles.conf"
DRIVER_PATH="/sys/bus/usb/drivers/usb"
LOGFILE="/userdata/system/logs/dongle_suspend.log"
MAX_LOG_SIZE=102400  # 100KB

rotate_log() {
    [[ -f "$LOGFILE" && $(stat -c%s "$LOGFILE") -gt $MAX_LOG_SIZE ]] && mv "$LOGFILE" "$LOGFILE.old"
}

cleanup() {
    local status=$?
    [[ $status -ne 0 ]] && echo "[ERROR] Script exited unexpectedly (status: $status)"
    echo "[EXIT] Script ended."
}
trap cleanup EXIT INT TERM

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $*"
}

log_cmd_output() {
    local header="$1"
    shift
    log "$header"
    "$@" 2>&1 | while IFS= read -r line; do log "  $line"; done
}

rotate_log
log "== Dongle Suspend Script Started =="

[[ ! -f "$CONFIG" ]] && log "[ERROR] No config file found at $CONFIG" && exit 1

mapfile -t known_entries < <(
    grep -vE '^[ \t]*#' "$CONFIG" | sed 's/#.*//' | sed 's/[ \t]*$//' | tr '[:upper:]' '[:lower:]'
)

declare -A SERIAL_MATCHES GENERIC_MATCHES WAITDONGLE DONGLE_TIMEOUT IDLE_PID_LIST SERIAL_BY_KEY
MATCHED_DEVICES=()
DEFAULT_TIMEOUT=15

for line in "${known_entries[@]}"; do
    IFS=':' read -ra parts <<< "$line"
    vendor="${parts[0]}" product="${parts[1]}" serial="${parts[2]}"
    key="$vendor:$product"
    [[ -n "$serial" ]] && key+=":$serial" && SERIAL_BY_KEY["$key"]="$serial"

    options=("${parts[@]:3}")
    for opt in "${options[@]}"; do
        [[ "$opt" == "waitdock" ]] && WAITDONGLE["$key"]=1
        [[ "$opt" =~ ^timeout=([0-9]+)$ ]] && DONGLE_TIMEOUT["$key"]="${BASH_REMATCH[1]}"
        [[ "$opt" =~ ^idle=([a-f0-9,]+)$ ]] && IDLE_PID_LIST["$key"]="${BASH_REMATCH[1]}"
    done

    [[ -z "${DONGLE_TIMEOUT[$key]}" ]] && DONGLE_TIMEOUT["$key"]="$DEFAULT_TIMEOUT"
    [[ -z "${IDLE_PID_LIST[$key]}" ]] && IDLE_PID_LIST["$key"]="$product"
    [[ -n "$serial" ]] && SERIAL_MATCHES["$key"]=1 || GENERIC_MATCHES["$vendor:$product"]=1
done

for device in /sys/bus/usb/devices/*; do
    [[ -f "$device/idVendor" && -f "$device/idProduct" ]] || continue
    vendor=$(<"$device/idVendor" tr '[:upper:]' '[:lower:]')
    product=$(<"$device/idProduct" tr '[:upper:]' '[:lower:]')
    serial=""
    [[ -f "$device/serial" ]] && serial=$(<"$device/serial" tr '[:upper:]' '[:lower:]')
    key_exact="$vendor:$product:$serial" key_generic="$vendor:$product"

    if [[ -n "${SERIAL_MATCHES[$key_exact]}" ]]; then
        log "[MATCH] Exact: $key_exact"
        MATCHED_DEVICES+=("$(basename "$device")|$key_exact")
    elif [[ -n "${GENERIC_MATCHES[$key_generic]}" ]]; then
        log "[MATCH] Fallback: $key_generic (serial: $serial)"
        MATCHED_DEVICES+=("$(basename "$device")|$key_generic")
    fi
done

[[ ${#MATCHED_DEVICES[@]} -eq 0 ]] && log "[INFO] No matching 2.4G dongles found" && exit 0

for entry in "${MATCHED_DEVICES[@]}"; do
    IFS="|" read -r DONGLE DEVKEY <<< "$entry"
    log "[UNBIND] $DONGLE"
    [[ -e "$DRIVER_PATH/$DONGLE" ]] && echo "$DONGLE" > "$DRIVER_PATH/unbind"
    sleep 1

    log_cmd_output "udevadm info before waitdock:" udevadm info --name="/dev/bus/usb/${DONGLE//-//}" --attribute-walk

    [[ -z "${WAITDONGLE[$DEVKEY]}" ]] && continue
    timeout="${DONGLE_TIMEOUT[$DEVKEY]:-$DEFAULT_TIMEOUT}"
    IFS=',' read -ra idle_pids <<< "${IDLE_PID_LIST[$DEVKEY]}"
    vendor="${DEVKEY%%:*}" pid="${DEVKEY#*:}" pid="${pid%%:*}" serial="${SERIAL_BY_KEY[$DEVKEY]}"

    log "[WAITDOCK] Vendor: $vendor, Idle PIDs: ${IDLE_PID_LIST[$DEVKEY]}, Serial: $serial, Timeout: ${timeout}s"

    while [[ $timeout -gt 0 ]]; do
        for device in /sys/bus/usb/devices/*; do
            [[ -f "$device/idVendor" && -f "$device/idProduct" ]] || continue
            dev_vendor=$(<"$device/idVendor" tr '[:upper:]' '[:lower:]')
            dev_product=$(<"$device/idProduct" tr '[:upper:]' '[:lower:]')
            dev_serial=""
            [[ -f "$device/serial" ]] && dev_serial=$(<"$device/serial" tr '[:upper:]' '[:lower:]')

            for idle_pid in "${idle_pids[@]}"; do
                if [[ "$dev_vendor" == "$vendor" && "$dev_product" == "$idle_pid" && ( -z "$serial" || "$dev_serial" == "$serial" ) ]]; then
                    base=$(basename "$device")
                    log "[DOCKED] Detected $base (Product ID: $idle_pid)"

                    [[ -f "$device/power/wakeup" ]] && \
                        log "[WAKEUP] was: $(cat "$device/power/wakeup")" && \
                        echo enabled > "$device/power/wakeup" && \
                        log "[WAKEUP] enabled for $base"

                    log_cmd_output "udevadm info for $base:" udevadm info --name="/dev/bus/usb/${base//-//}" --attribute-walk

                    sleep 1
                    break 3
                fi
            done
        done
        sleep 1
        ((timeout--))
    done
done

for entry in "${MATCHED_DEVICES[@]}"; do
    IFS="|" read -r DONGLE _ <<< "$entry"
    log "[REBIND] $DONGLE"
    if [[ -e "/sys/bus/usb/devices/$DONGLE" && ! -e "$DRIVER_PATH/$DONGLE" ]]; then
        echo "$DONGLE" > "$DRIVER_PATH/bind"
    else
        log "[REBIND] Already bound or busy: $DONGLE"
    fi
done

log "[DONE] Suspend preparation complete."
exit 0
