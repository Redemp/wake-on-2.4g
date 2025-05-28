#!/bin/bash

# Get the directory of the script (canonical path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install each file relative to script location
install -D -m 0755 "$SCRIPT_DIR/00-dongle-safe-suspend.sh" /userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh
install -D -m 0755 "$SCRIPT_DIR/register_2.4ghz_dongle.sh" /userdata/system/dongle_2_4g/register_2.4ghz_dongle.sh
install -D -m 0755 "$SCRIPT_DIR/force_usb_wakeup_dongles" /usr/share/batocera/services/force_usb_wakeup_dongles

# Save changes to overlay (for Batocera persistence)
batocera-save-overlay
