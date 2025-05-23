#!/bin/bash

CONFIG="/userdata/system/configs/dongles.conf"
DRIVER_PATH="/sys/bus/usb/drivers/usb"
MATCHED_DEVICES=()
TIMEOUT=15

# Load known dongles
if [[ ! -f "$CONFIG" ]]; then
    echo "[DongleSuspend] No config file found at $CONFIG"
    exit 1
fi

# Strip comments, trim whitespace, lowercase
mapfile -t known_entries < <(
    grep -vE '^\s*#' "$CONFIG" | sed 's/#.*//' | tr -d ' \t' | tr '[:upper:]' '[:lower:]'
)

# Parse config into match tables
declare -A SERIAL_MATCHES
declare -A GENERIC_MATCHES
declare -A WAITDONGLE

for line in "${known_entries[@]}"; do
    [[ "$line" =~ ^([a-f0-9]{4}):([a-f0-9]{4})(:([^:]+))?(:([a-z]+))?$ ]] || continue
    vendor="${BASH_REMATCH[1]}"
    product="${BASH_REMATCH[2]}"
    serial="${BASH_REMATCH[4]}"
    option="${BASH_REMATCH[6]}"

    key="${vendor}:${product}"
    [[ -n "$serial" ]] && key="$key:$serial"

    if [[ -n "$serial" ]]; then
        SERIAL_MATCHES["$key"]=1
    else
        GENERIC_MATCHES["$vendor:$product"]=1
    fi

    [[ "$option" == "waitdock" ]] && WAITDONGLE["$key"]=1
done

# Find matching USB devices
for device in /sys/bus/usb/devices/*; do
    [[ -f "$device/idVendor" && -f "$device/idProduct" ]] || continue

    vendor=$(cat "$device/idVendor" | tr '[:upper:]' '[:lower:]')
    product=$(cat "$device/idProduct" | tr '[:upper:]' '[:lower:]')
    serial=""
    [[ -f "$device/serial" ]] && serial=$(cat "$device/serial" | tr '[:upper:]' '[:lower:]')

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

# Unbind matched devices
for entry in "${MATCHED_DEVICES[@]}"; do
    IFS="|" read -r DONGLE DEVKEY <<< "$entry"
    echo "[DongleSuspend] Unbinding $DONGLE..."
    [[ -e "$DRIVER_PATH/$DONGLE" ]] && echo "$DONGLE" > "$DRIVER_PATH/unbind"
done

# Wait for :waitdock if configured
for entry in "${MATCHED_DEVICES[@]}"; do
    IFS="|" read -r DONGLE DEVKEY <<< "$entry"
    [[ -z "${WAITDONGLE[$DEVKEY]}" ]] && continue

    echo "[DongleSuspend] Waiting for $DONGLE to report docked (ID 3109)..."
    timeout=$TIMEOUT
    while [[ $timeout -gt 0 ]]; do
        current_product=$(cat "/sys/bus/usb/devices/$DONGLE/idProduct" 2>/dev/null)
        if [[ "$current_product" == "3109" ]]; then
            echo "[DongleSuspend] Docked state confirmed (3109)"
            break
        fi
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
