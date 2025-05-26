#!/bin/bash

install -D -m 0755 /userdata/system/2_4g_install/00-dongle-safe-suspend.sh /userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh
install -D -m 0755 /userdata/system/2_4g_install/register_2.4ghz_dongle.sh /userdata/system/dongle_2_4g/register_2.4ghz_dongle.sh
install -D -m 0644 /userdata/system/2_4g_install/dongles.conf /userdata/system/configs/dongles.conf
install -D -m 0755 /userdata/system/2_4g_install/force_usb_wakeup_all /usr/share/batocera/services/force_usb_wakeup_all

batocera-save-overlay
