#!/bin/bash

CONFIG="/userdata/system/configs/dongles.conf"
DRIVER_PATH="/sys/bus/usb/drivers/usb"
MATCHED_DEVICES=()
DEFAULT_TIMEOUT=15

# Load known dongles
if [[ ! -f "$CONFIG" ]]; then
    echo "[DongleSuspend] No config file found at $CONFIG"
    exit 1
fi

# Strip comments, trim whitespace, lowercase
mapfile -t known_entries < <(
    grep -vE '^[ \t]*#' "$CONFIG" | sed 's/#.*//' | tr -d ' \t' | tr '[:upper:]' '[:lower:]'
)

# Parse config into match tables
declare -A SERIAL_MATCHES
declare -A GENERIC_MATCHES
declare -A WAITDONGLE
declare -A DONGLE_TIMEOUT
declare -A IDLE_PID_LIST

declare -A SERIAL_BY_KEY

temp_serial=""
for line in "${known_entries[@]}"; do
    IFS=':' read -ra parts <<< "$line"
    vendor="${parts[0]}"
    product="${parts[1]}"
    serial="${parts[2]}"

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

    if [[ -n "$serial" ]]; then
        SERIAL_MATCHES["$key"]=1
    else
        GENERIC_MATCHES["$vendor:$product"]=1
    fi

done

# Find matching USB devices
for device in /sys/bus/usb/devices/*; do
    [[ -f "$device/idVendor" && -f "$device/idProduct" ]] || continue

    vendor=$(<"$device/idVendor" tr '[:upper:]' '[:lower:]')
    product=$(<"$device/idProduct" tr '[:upper:]' '[:lower:]')
    serial=""
    [[ -f "$device/serial" ]] && serial=$(<"$device/serial" tr '[:upper:]' '[:lower:]')

    key_exact="$vendor:$product:$serial"
    key_generic="$vendor:$product"

    if [[ -n "${SERIAL_MATCHES[$key_exact]}" ]]; then
        echo "[DongleSuspend] Exact match: $key_exact"
        MATCHED_DEVICES+=("$(basename "$device")|$key_exact")
    elif [[ -n "${GENERIC_MATCHES[$key_generic]}" ]]; then
        echo "[DongleSuspend] Fallback match: $key_generic (serial: $serial)"
        MATCHED_DEVICES+=("$(basename "$device")|$key_generic")
    fi

done

if [[ ${#MATCHED_DEVICES[@]} -eq 0 ]]; then
    echo "[DongleSuspend] No matching 2.4G dongles found"
    exit 0
fi

# Unbind matched devices and wait for re-enumeration
for entry in "${MATCHED_DEVICES[@]}"; do
    IFS="|" read -r DONGLE DEVKEY <<< "$entry"
    echo "[DongleSuspend] Unbinding $DONGLE..."
    [[ -e "$DRIVER_PATH/$DONGLE" ]] && echo "$DONGLE" > "$DRIVER_PATH/unbind"

    sleep 1  # allow kernel to process

    [[ -z "${WAITDONGLE[$DEVKEY]}" ]] && continue

    timeout="${DONGLE_TIMEOUT[$DEVKEY]:-$DEFAULT_TIMEOUT}"
    IFS=',' read -ra idle_pids <<< "${IDLE_PID_LIST[$DEVKEY]}"
    vendor="${DEVKEY%%:*}"
    pid="${DEVKEY#*:}"
    pid="${pid%%:*}"
    serial="${SERIAL_BY_KEY[$DEVKEY]}"

    echo "[DongleSuspend] Waiting for dongle reattach (Vendor: $vendor, Idle PIDs: ${IDLE_PID_LIST[$DEVKEY]}, Serial: $serial, Timeout: ${timeout}s)..."

    while [[ $timeout -gt 0 ]]; do
        for device in /sys/bus/usb/devices/*; do
            [[ -f "$device/idVendor" && -f "$device/idProduct" ]] || continue
            dev_vendor=$(<"$device/idVendor" tr '[:upper:]' '[:lower:]')
            dev_product=$(<"$device/idProduct" tr '[:upper:]' '[:lower:]')
            dev_serial=""
            [[ -f "$device/serial" ]] && dev_serial=$(<"$device/serial" tr '[:upper:]' '[:lower:]')

            for idle_pid in "${idle_pids[@]}"; do
                if [[ "$dev_vendor" == "$vendor" && "$dev_product" == "$idle_pid" && "$dev_serial" == "$serial" ]]; then
                    echo "[DongleSuspend] Docked state confirmed on new device ($(basename "$device"), Product ID: $idle_pid)"
                    echo "[DongleSuspend] Waiting 1 second to ensure wakeup rules apply..."

                    # ✅ Re-enable wakeup on re-detected device if supported
                    if [[ -f "$device/power/wakeup" ]]; then
                        echo enabled > "$device/power/wakeup"
                        echo "[DongleSuspend] Wakeup re-enabled for $(basename "$device")"
                    fi

                    sleep 1
                    break 3
                fi
            done
        done
        sleep 1
        ((timeout--))
    done

    if [[ $timeout -le 0 ]]; then
        echo "[DongleSuspend] Timeout waiting for dock. Suspend canceled."
        exit 0
    fi

done

# Rebind if not already bound
for entry in "${MATCHED_DEVICES[@]}"; do
    IFS="|" read -r DONGLE _ <<< "$entry"
    echo "[DongleSuspend] Rebinding $DONGLE..."
    if [[ -e "/sys/bus/usb/devices/$DONGLE" && ! -e "$DRIVER_PATH/$DONGLE" ]]; then
        echo "$DONGLE" > "$DRIVER_PATH/bind"
    else
        echo "[DongleSuspend] Already bound or busy: $DONGLE"
    fi

done

echo "[DongleSuspend] Ready for suspend. External suspend call may now proceed."
exit 0
