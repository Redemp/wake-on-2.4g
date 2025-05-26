#!/bin/bash

CONFIG_FILE="/userdata/system/configs/dongles.conf"
UDEV_DIR="/etc/udev/rules.d"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Utility
read_field() { cat "$1" 2>/dev/null || echo "unknown"; }
get_wakeup_state() { [[ -f "$1/power/wakeup" ]] && cat "$1/power/wakeup" || echo "unsupported"; }
get_usb_path_by_id() {
    local id="$1"
    for dev in /sys/bus/usb/devices/*; do
        [[ -f "$dev/idVendor" && -f "$dev/idProduct" ]] || continue
        local v=$(<"$dev/idVendor")
        local p=$(<"$dev/idProduct")
        [[ "${v,,}:${p,,}" == "$id" ]] && echo "$dev" && return
    done
    echo ""
}

echo -e "${YELLOW}[Step 1] Unplug all 2.4GHz dongles.${NC}"
read -rp "Press Enter once unplugged..."

read -rp "Are you sure no 2.4GHz dongles are connected? [yes/NO]: " confirm
[[ "${confirm,,}" != "yes" ]] && { echo -e "${RED}Exiting.${NC}"; exit 1; }

before=$(mktemp)
lsusb | awk '{ print tolower($6) }' | sort > "$before"

echo -e "${GREEN}[Step 2] Plug in your 2.4GHz dongle (not via hub).${NC}"
read -rp "Press Enter after connecting..."
sleep 2

after=$(mktemp)
lsusb | awk '{ print tolower($6) }' | sort > "$after"
new_id=$(comm -13 "$before" "$after" | head -n 1)
rm "$before" "$after"

[[ -z "$new_id" ]] && { echo -e "${RED}No new device detected. Exiting.${NC}"; exit 1; }

dongle_path=$(get_usb_path_by_id "$new_id")
[[ ! -d "$dongle_path" ]] && { echo -e "${RED}Could not locate sysfs path. Exiting.${NC}"; exit 1; }

# Disconnected state
vendor_d=$(read_field "$dongle_path/idVendor")
product_d=$(read_field "$dongle_path/idProduct")
manufacturer=$(read_field "$dongle_path/manufacturer")
product_name_d=$(read_field "$dongle_path/product")
serial_d=$(read_field "$dongle_path/serial")
class_d=$(read_field "$dongle_path/bDeviceClass")
subclass_d=$(read_field "$dongle_path/bDeviceSubClass")
protocol_d=$(read_field "$dongle_path/bDeviceProtocol")
wakeup_d=$(get_wakeup_state "$dongle_path")

echo -e "\n${GREEN}[Step 3] Turn on and pair your controller with the dongle.${NC}"
read -rp "Is the controller connected? [yes/NO]: " confirm_pair
[[ "${confirm_pair,,}" != "yes" ]] && { echo -e "${RED}Exiting.${NC}"; exit 1; }
sleep 2

# Connected state
vendor_c=$(read_field "$dongle_path/idVendor")
product_c=$(read_field "$dongle_path/idProduct")
manufacturer_c=$(read_field "$dongle_path/manufacturer")
product_name_c=$(read_field "$dongle_path/product")
serial_c=$(read_field "$dongle_path/serial")
class_c=$(read_field "$dongle_path/bDeviceClass")
subclass_c=$(read_field "$dongle_path/bDeviceSubClass")
protocol_c=$(read_field "$dongle_path/bDeviceProtocol")
wakeup_c=$(get_wakeup_state "$dongle_path")

# Base name
safe_manufacturer=$(echo "$manufacturer" | tr -cd '[:alnum:]' | sed 's/ /_/g')
timestamp=$(date +"%Y%m%d_%H%M%S")
base_name="${safe_manufacturer}_${vendor_d}_${product_d}_usb_2.4ghz_dongle"
export_dir="./dongles"
mkdir -p "$export_dir"

# Unique JSON filename
export_file="${export_dir}/${base_name}_${timestamp}.json"
counter=1
while [[ -e "$export_file" ]]; do
    export_file="${export_dir}/${base_name}_${timestamp}_$counter.json"
    ((counter++))
done

# Export JSON
jq -n \
    --arg path "$dongle_path" \
    --arg vendor_d "$vendor_d" --arg product_d "$product_d" --arg manufacturer "$manufacturer" \
    --arg product_name_d "$product_name_d" --arg serial_d "$serial_d" \
    --arg class_d "$class_d" --arg subclass_d "$subclass_d" --arg protocol_d "$protocol_d" --arg wakeup_d "$wakeup_d" \
    --arg vendor_c "$vendor_c" --arg product_c "$product_c" --arg manufacturer_c "$manufacturer_c" \
    --arg product_name_c "$product_name_c" --arg serial_c "$serial_c" \
    --arg class_c "$class_c" --arg subclass_c "$subclass_c" --arg protocol_c "$protocol_c" --arg wakeup_c "$wakeup_c" \
    '{
        disconnected: {
            path: $path,
            vendor_id: $vendor_d, product_id: $product_d,
            manufacturer: $manufacturer, product_name: $product_name_d, serial: $serial_d,
            device_class: $class_d, device_subclass: $subclass_d, device_protocol: $protocol_d,
            wakeup_support: $wakeup_d
        },
        connected: {
            path: $path,
            vendor_id: $vendor_c, product_id: $product_c,
            manufacturer: $manufacturer_c, product_name: $product_name_c, serial: $serial_c,
            device_class: $class_c, device_subclass: $subclass_c, device_protocol: $protocol_c,
            wakeup_support: $wakeup_c
        }
    }' > "$export_file"

echo -e "\n${GREEN}✅ JSON export complete: ${export_file}${NC}"

# === dongles.conf entry ===
conf_line="${vendor_c}:${product_c}:${serial_c}"

# Ask about :waitdock
read -rp $'\nWould you like to prevent suspend while the controller is still connected?\nThis adds ":waitdock" to the dongle entry. [y/N]: ' waitdock
[[ "${waitdock,,}" == "y" || "${waitdock,,}" == "yes" ]] && conf_line="${conf_line}:waitdock"

# Append dongles.conf entry (with comment)
if ! grep -qi "^${vendor_c}:${product_c}:${serial_c}" "$CONFIG_FILE" 2>/dev/null; then
    echo "$conf_line  # $base_name" >> "$CONFIG_FILE"
    echo -e "${GREEN}Appended to dongles.conf: $conf_line  # $base_name${NC}"
else
    echo -e "${YELLOW}dongles.conf entry already exists.${NC}"
fi

# Fallback entry (commented out)
fallback_line="# ${vendor_c}:${product_c}"
if ! grep -q "$fallback_line" "$CONFIG_FILE" 2>/dev/null; then
    echo -e "\n# Optional fallback for any similar dongle:" >> "$CONFIG_FILE"
    echo "$fallback_line" >> "$CONFIG_FILE"
    echo -e "${GREEN}Added optional fallback entry (commented out) to dongles.conf${NC}"
fi

# === Generate UDEV rule ===
udev_file="$UDEV_DIR/30-wake-on-${base_name}.rules"
if [[ -e "$udev_file" ]]; then
    echo -e "${YELLOW}Udev rule already exists: $udev_file${NC}"
else
    cat <<EOF > "$udev_file"
# $base_name

# Enable wakeup when controller is active
ACTION=="add|change", SUBSYSTEMS=="usb", ATTRS{idVendor}=="${vendor_c}", ATTRS{idProduct}=="${product_c}", TEST=="power/wakeup", RUN+="/bin/sh -c 'echo enabled > /sys/\$env{DEVPATH}/power/wakeup'"

# Disable wakeup when dongle switches to IDLE
ACTION=="add|change", SUBSYSTEMS=="usb", ATTRS{idVendor}=="${vendor_d}", ATTRS{idProduct}=="${product_d}", TEST=="power/wakeup", RUN+="/bin/sh -c 'echo disabled > /sys/\$env{DEVPATH}/power/wakeup'"
EOF

    echo -e "${GREEN}Created udev rule: $udev_file${NC}"
fi

read -rp "Press 'y' to exit: " choice
[[ "${choice,,}" == "y" ]] && echo -e "${GREEN}Done.${NC}"
