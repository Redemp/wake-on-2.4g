# wake-on-2.4g

A Bash script to safely suspend and resume Linux systems (such as Batocera) while keeping selected 2.4GHz USB dongles (e.g., wireless controllers, keyboards, mice) functional across suspend cycles.

## 🎯 Purpose

Many 2.4GHz USB dongles stop working after suspend/resume due to driver unbinding or improper wakeup settings. This script safely unbinds and rebinds only *known* devices during suspend and resume to prevent disconnection issues or missed input. It also enables USB wakeup support on all connected USB devices to improve compatibility with devices that do **not** natively support wake on USB.

## ✅ Features

- Suspend-safe handling for known 2.4GHz USB dongles
- **Mandatory**: Force-enables USB wakeup (`power/wakeup`) for all connected USB devices
- Uses a config file to define which dongles to unbind/rebind during suspend
- Compatible with Batocera, but works on most Linux distributions
- Includes a `force_usb_wakeup_all` service that can be enabled through EmulationStation
- Debug-friendly output with logging support
- Ensures safe driver rebinding using kernel paths

## 📁 File Structure

This repo already includes the correct folder layout. Simply copy the files to your system and ensure they have executable permissions where needed.

* `/usr/share/batocera/services/force_usb_wakeup_all`
* `/userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh`
* `/userdata/system/configs/emulationstation/dongles.conf`
* `/etc/udev/rules.d/30-wake-on-2dc8-3106-dongle-example-file.rules`


## 🛠️ Usage

1. **Copy all files** to their respective paths listed above.
2. **Make sure the scripts and config are executable**:
   ```bash
   chmod +x /usr/share/batocera/services/force_usb_wakeup_all
   chmod +x /userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh
   chmod +x /userdata/system/configs/emulationstation/dongles.conf

3. Enable the force_usb_wakeup_all service in EmulationStation:

* Go to Main Menu → System Settings

* Under the Advanced tab, go to Services

* Enable: force_usb_wakeup_all

4. (Optional) Test the suspend script manually:
```
bash -xv /userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh`
```

5. Save the system overlay so that all changes persist across reboots:

```
batocera-save-overlay`
```

⚡ Mandatory USB Wakeup Handling

Many 2.4GHz dongles do not officially support USB wakeup (i.e., they lack a power/wakeup entry or report it as unsupported). To improve compatibility and avoid disconnection after suspend/resume, this script and the included service automatically enable power/wakeup = enabled for all USB devices at runtime.

This behavior is required and ensures that devices with broken or missing wakeup support are still handled safely.

## 🧰 How to Get `VENDOR_ID`, `PRODUCT_ID`, and `SERIAL`

To configure `dongles.conf` accurately, you need the USB **Vendor ID**, **Product ID**, and optionally the **Serial Number**. These values help the suspend script uniquely identify your dongle and distinguish between different states (e.g., idle vs. active).

---

### ✅ Recommended: Use the USB Device Scanner Tool (Automated)

Instead of finding these values manually, you can use the companion script from this repository:

👉 **[USB Device Scanner with Wakeup Support & JSON Export](https://github.com/Redemp/USB-Device-Scanner-with-Wakeup-Support-JSON-Export)**

This tool simplifies the process by:

- ✅ Scanning and displaying all connected USB devices in a structured, tree-style layout  
- ✅ Highlighting important identifiers like:
  - `idVendor`
  - `idProduct`
  - `SerialNumber`
  - Product name and manufacturer
  - Device class, protocol, USB version, speed
  - Wakeup support status
- ✅ Showing USB hub/device hierarchy using visual connectors (├─, │, └─)
- ✅ Allowing optional **JSON export** of all device details for scripting and record-keeping

This is the easiest and most reliable way to get all the needed identifiers for your dongle without digging through logs manually.

---

### 🧪 Steps to Identify Your Dongle - Manual Method (Advanced Users)

1. **Disconnect your 2.4GHz dongle** from the system.

2. **Run** the following command in a terminal:
```
   dmesg -w
```
Press **Enter** a few times to create visual space.

3. Connect the dongle, and observe the new messages that appear.

You'll see output similar to:
```
[  607.703432] usb 1-1: new full-speed USB device number 10 using xhci_hcd
[  607.834879] usb 1-1: New USB device found, idVendor=2dc8, idProduct=3109, bcdDevice= 2.00
[  607.834887] usb 1-1: Product: IDLE
[  607.834889] usb 1-1: Manufacturer: 8BitDo
[  607.834890] usb 1-1: SerialNumber: E417D81715AD
```
This is the idle state of the dongle (no controller connected).

Now **turn on or pair your controller**, and you’ll see a second entry:
```
[  797.550778] usb 1-1: new full-speed USB device number 11 using xhci_hcd
[  797.683580] usb 1-1: New USB device found, idVendor=2dc8, idProduct=3106, bcdDevice= 1.14
[  797.683602] usb 1-1: Product: 8BitDo Ultimate wireless Controller for PC
[  797.683611] usb 1-1: SerialNumber: E417D81715AD
```

📌 What to Extract

From each connection state (idle and active), extract:

*    `idVendor` → Vendor ID (e.g., `2dc8`)

*    `idProduct` → Product ID (e.g., `3109` for idle, `3106` for active)

*    `SerialNumber` → Device serial (e.g., `E417D81715AD`)

You can now configure your `dongles.conf` like this:
```
# Strict match with serial (recommended)
2dc8:3106:e417d81715ad  # Active state
2dc8:3109:e417d81715ad  # Idle state

# With waitdock (only suspend if docked)
2dc8:3106:e417d81715ad:waitdock

# Fallback match (less specific)
2dc8:3106
2dc8:3109
```
✅ Note: All values must be in lowercase and must not include 0x.
This method ensures your dongle is handled correctly based on its connection state.

🔧 Example dongles.conf

This configuration file controls which dongles are managed during suspend/resume.

* Lines with a serial match only that exact dongle (strict match).
* If the serial is not found, and a fallback is provided, it will match any device with that vendor:product ID.
* You can add `:waitdock` to any entry to delay suspend until a dock state is detected.

**Format:**
```
VENDOR_ID:PRODUCT_ID[:SERIAL][:waitdock]
```

**Examples:**
```
# 🔒 Specific dongle (strict match)
2dc8:3106:e417d81715ad  # My 8BitDo Ultimate dock (connected)
2dc8:3109:e417d81715ad  # My 8BitDo Ultimate dock (idle mode)

# 🔒 Specific dongle (strict match) with docking requirement
2dc8:3106:e417d81715ad:waitdock  # Only suspend when docked
2dc8:3109:e417d81715ad           # Idle mode still listed

# 🔓 Fallback match for any similar 8BitDo dongle (non-strict match)
2dc8:3106
2dc8:3109

# 🎮 Generic Xbox 360 dongle (always match any & suspend immediately)
045e:028e
```

🛠️ Example Udev Rule (Dynamic Wakeup Based on State)

In some cases, a 2.4GHz dongle switches USB product ID when going idle or when a controller disconnects. You can dynamically enable or disable USB wakeup using a custom udev rule like this:

**File:**
```
/etc/udev/rules.d/30-wake-on-2dc8-3106-dongle-example-file.rules
```
**Contents:**
```
# Enable wakeup when controller is active
ACTION=="add|change", SUBSYSTEMS=="usb", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="3106", TEST=="power/wakeup", RUN+="/bin/sh -c 'echo enabled > /sys/$env{DEVPATH}/power/wakeup'"

# Disable wakeup when dongle switches to IDLE
ACTION=="add|change", SUBSYSTEMS=="usb", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="3109", TEST=="power/wakeup", RUN+="/bin/sh -c 'echo disabled > /sys/$env{DEVPATH}/power/wakeup'"
```

🔍 Explanation

*   **Vendor ID 2dc8 / Product ID 3106** represents the **active state** of the dongle.   
*   **Vendor ID 2dc8 / Product ID 3109** is used when the dongle switches to **idle or sleep mode**.
* These rules automatically enable or disable `power/wakeup` dynamically based on the USB device's current state.

This is useful for advanced control over suspend behavior and can help prevent wake-up loops or power drain when idle.

🧪 Example Output
```
[DongleSuspend] Matching device: 046d:c534 at 1-1
[DongleSuspend] Unbinding usb 1-1...
[DongleSuspend] Rebinding usb 1-1...
[USB Wakeup] Enabled wakeup for usb 1-2
```

📜 License

MIT — feel free to modify, improve, and share.
