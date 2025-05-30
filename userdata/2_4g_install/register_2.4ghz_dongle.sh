#!/bin/bash

CONFIG_FILE="/userdata/system/configs/dongles.conf"
UDEV_DIR="/etc/udev/rules.d"
DEFAULT_TIMEOUT=15

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Ensure config file exists
mkdir -p "$(dirname "$CONFIG_FILE")"
[[ -f "$CONFIG_FILE" ]] || touch "$CONFIG_FILE"

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
read -rp "Are you sure no 2.4GHz dongles are connected? [y/N]: " confirm
[[ "${confirm,,}" != "y" ]] && { echo -e "${RED}Exiting.${NC}"; exit 1; }

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

vendor_d=$(read_field "$dongle_path/idVendor")
product_d=$(read_field "$dongle_path/idProduct")
manufacturer_d=$(read_field "$dongle_path/manufacturer")
product_name_d=$(read_field "$dongle_path/product")
serial_d=$(read_field "$dongle_path/serial")
class_d=$(read_field "$dongle_path/bDeviceClass")
subclass_d=$(read_field "$dongle_path/bDeviceSubClass")
protocol_d=$(read_field "$dongle_path/bDeviceProtocol")
wakeup_d=$(get_wakeup_state "$dongle_path")

echo -e "\n${GREEN}[Step 3] Turn on and pair your controller with the dongle.${NC}"
read -rp "Is the controller connected? [y/N]: " confirm_pair
[[ "${confirm_pair,,}" != "y" ]] && { echo -e "${RED}Exiting.${NC}"; exit 1; }
sleep 2

vendor_c=$(read_field "$dongle_path/idVendor")
product_c=$(read_field "$dongle_path/idProduct")
manufacturer_c=$(read_field "$dongle_path/manufacturer")
product_name_c=$(read_field "$dongle_path/product")
serial_c=$(read_field "$dongle_path/serial")
class_c=$(read_field "$dongle_path/bDeviceClass")
subclass_c=$(read_field "$dongle_path/bDeviceSubClass")
protocol_c=$(read_field "$dongle_path/bDeviceProtocol")
wakeup_c=$(get_wakeup_state "$dongle_path")

safe_manufacturer=$(echo "$manufacturer_c" | tr -cd '[:alnum:]' | sed 's/ /_/g')
timestamp=$(date +"%Y%m%d_%H%M%S")
base_name="${safe_manufacturer}_${vendor_d}_${product_d}_${serial_c}_usb_2.4ghz_dongle"
export_dir="./dongles"
mkdir -p "$export_dir"
export_file="${export_dir}/${base_name}_${timestamp}.json"
counter=1
while [[ -e "$export_file" ]]; do
    export_file="${export_dir}/${base_name}_${timestamp}_$counter.json"
    ((counter++))
done

jq -n --arg path "$dongle_path" --arg vendor_d "$vendor_d" --arg product_d "$product_d" --arg manufacturer "$manufacturer_c" --arg product_name_d "$product_name_d" --arg serial_d "$serial_d" --arg class_d "$class_d" --arg subclass_d "$subclass_d" --arg protocol_d "$protocol_d" --arg wakeup_d "$wakeup_d" --arg vendor_c "$vendor_c" --arg product_c "$product_c" --arg product_name_c "$product_name_c" --arg serial_c "$serial_c" --arg class_c "$class_c" --arg subclass_c "$subclass_c" --arg protocol_c "$protocol_c" --arg wakeup_c "$wakeup_c" '{
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
        manufacturer: $manufacturer, product_name: $product_name_c, serial: $serial_c,
        device_class: $class_c, device_subclass: $subclass_c, device_protocol: $protocol_c,
        wakeup_support: $wakeup_c
    }
}' > "$export_file"

echo -e "\n${GREEN}✅ JSON export complete: ${export_file}${NC}"

read -rp "Default suspend wait timeout is ${DEFAULT_TIMEOUT} seconds. Enter custom timeout (or press Enter to use default): " custom_timeout
if [[ -n "$custom_timeout" && "$custom_timeout" =~ ^[0-9]+$ ]]; then
    TIMEOUT_VALUE="$custom_timeout"
else
    TIMEOUT_VALUE="$DEFAULT_TIMEOUT"
fi

conf_serial=""
[[ "$serial_c" != "unknown" && "$serial_d" != "unknown" && -n "$serial_c" && -n "$serial_d" ]] && conf_serial=":$serial_c"

# Combine product names if different
if [[ "$product_name_c" != "$product_name_d" && "$product_name_d" != "unknown" ]]; then
    product_name_full="${product_name_c}, ${product_name_d}"
else
    product_name_full="${product_name_c}"
fi

# Combine manufacturers if different
if [[ "$manufacturer_c" != "$manufacturer_d" && "$manufacturer_d" != "unknown" ]]; then
    manufacturer_full="${manufacturer_c}, ${manufacturer_d}"
else
    manufacturer_full="${manufacturer_c}"
fi

conf_line="${vendor_c}:${product_c}${conf_serial}:waitdock:idle=${product_d}:timeout=${TIMEOUT_VALUE}"
{
    echo "# Manufacturer : $manufacturer_full"
    echo "# Product Name : $product_name_full"
    echo "$conf_line"
} >> "$CONFIG_FILE"

echo -e "${GREEN}Entry added to $CONFIG_FILE:${NC}"
echo "# Manufacturer : $manufacturer_full"
echo "# Product Name : $product_name_full"
echo "$conf_line"

udev_file="$UDEV_DIR/30-wake-on-${base_name}.rules"
if [[ ! -e "$udev_file" ]]; then
    cat <<EOF > "$udev_file"
# $base_name

ACTION=="add|change", SUBSYSTEMS=="usb", ATTRS{idVendor}=="${vendor_c}", ATTRS{idProduct}=="${product_c}", TEST=="power/wakeup", RUN+="/bin/sh -c 'echo enabled > /sys/\$env{DEVPATH}/power/wakeup'"
ACTION=="add|change", SUBSYSTEMS=="usb", ATTRS{idVendor}=="${vendor_d}", ATTRS{idProduct}=="${product_d}", TEST=="power/wakeup", RUN+="/bin/sh -c 'echo disabled > /sys/\$env{DEVPATH}/power/wakeup'"
EOF
    echo -e "${GREEN}Created udev rule: $udev_file${NC}"
fi

udevadm control --reload-rules
udevadm trigger

echo -e "${GREEN}Enabling and starting service: force_usb_wakeup_dongles${NC}"
batocera-services enable force_usb_wakeup_dongles
batocera-services start force_usb_wakeup_dongles

read -rp "Would you like to save the overlay now to make changes permanent? [y/N]: " persist
if [[ "${persist,,}" == "y" ]]; then
    echo -e "${GREEN}Saving overlay...${NC}"
    batocera-save-overlay
else
    echo -e "${YELLOW}⚠️  You must run batocera-save-overlay manually or your changes will be lost after reboot!${NC}"
fi

echo
read -rp "Press 'y' to exit: " choice
[[ "${choice,,}" == "y" ]] && echo -e "${GREEN}Done.${NC}"
exit 0
