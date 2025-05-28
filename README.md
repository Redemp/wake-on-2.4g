# wake-on-2.4g

A Bash script to safely suspend and resume Linux systems (such as Batocera) while keeping selected 2.4GHz USB dongles (e.g., wireless controllers, keyboards, mice) functional across suspend cycles.

## 🎯 Purpose

Many 2.4GHz USB dongles stop working after suspend/resume due to driver unbinding or improper wakeup settings. This script safely unbinds and rebinds only *known* devices during suspend and resume to prevent disconnection issues or missed input. It also enables USB wakeup support on all connected USB devices to improve compatibility with devices that do **not** natively support wake on USB.

## ✅ Features

- Suspend-safe handling for known 2.4GHz USB dongles
- **Mandatory**: Force-enables USB wakeup (`power/wakeup`) for selected USB devices listed in `dongles.conf`
- Uses a config file to define which dongles to unbind/rebind during suspend
- Compatible with Batocera, but works on most Linux distributions
- Includes a `force_usb_wakeup_dongles` service that integrates with Batocera
- Debug-friendly output with logging support
- Ensures safe driver rebinding using kernel paths

---

## 🚀 Quick Installation

Instead of copying files manually, you can now use the included install script to set everything up automatically.

### ▶️ How to use:

```bash
chmod +x ./Install.sh
./Install.sh
```

### 🧰 What it does:

- Installs `register_2.4ghz_dongle.sh` to `/userdata/system/dongle_2_4g/`
- Installs `00-dongle-safe-suspend.sh` to Batocera’s suspend scripts folder
- Installs `force_usb_wakeup_dongles` to `/usr/share/batocera/services/`
- Copies `dongles.conf` to `/userdata/system/configs/` if it doesn't already exist
- Saves all changes using `batocera-save-overlay`

---

## 📁 File Structure

These files will be installed automatically by `Install.sh`, or can be copied manually:

- `/userdata/system/dongle_2_4g/register_2.4ghz_dongle.sh`        ← Interactive dongle setup tool
- `/usr/share/batocera/services/force_usb_wakeup_dongles`         ← System-wide USB wakeup handler
- `/userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh`
- `/userdata/system/configs/dongles.conf`

---

## 🛠️ Usage (Manual setup)

1. **Copy all files** to their respective paths listed above.

2. **Make sure the scripts and config are executable**:

```bash
chmod +x /usr/share/batocera/services/force_usb_wakeup_dongles
chmod +x /userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh
chmod +x /userdata/system/dongle_2_4g/register_2.4ghz_dongle.sh
```

3. **Enable the force_usb_wakeup_dongles service in EmulationStation**:

- Go to Main Menu → System Settings
- Under the Advanced tab, go to Services
- Enable: `force_usb_wakeup_dongles`

4. (Optional) Test the suspend script manually:

```bash
bash -xv /userdata/system/configs/emulationstation/scripts/suspend/00-dongle-safe-suspend.sh
```

5. Save the system overlay so that all changes persist across reboots:

```bash
batocera-save-overlay
```

---

## 🔌 `register_2.4ghz_dongle.sh`

This interactive script helps you register a 2.4GHz gamepad dongle for suspend-safe wake-up support. It detects the dongle in both its **disconnected (idle)** and **connected (paired)** states, and automatically generates the necessary configuration and udev rule files.

### 🧰 What it does:

1. Asks the user to unplug all 2.4GHz dongles.
2. Prompts to connect only the dongle to register (direct USB port).
3. Captures the dongle's USB info in idle state.
4. Asks the user to pair the controller with the dongle.
5. Captures the USB info again in connected state.
6. Creates a structured JSON export with both states for reference.
7. Appends a matching line to `dongles.conf` (with optional `:waitdock`).
8. Generates a matching udev rule for proper wake-up behavior.
9. Prevents duplicate entries and names all files consistently.

### 📦 Output:

- JSON file: `./dongles/<vendor>_<product>_usb_2.4ghz_dongle_<timestamp>.json`
- Config entry: added to:  
  `/userdata/system/configs/dongles.conf`
- Udev rule:  
  `/etc/udev/rules.d/30-wake-on-<dongle-name>.rules`

### ▶️ How to use:

```bash
chmod +x /userdata/system/dongle_2_4g/register_2.4ghz_dongle.sh
/userdata/system/dongle_2_4g/register_2.4ghz_dongle.sh
```

> 🛡️ This ensures that Batocera can safely suspend and resume **only when your gamepad is docked and ready**, preventing unwanted wake-ups from idle dongles or false signals.

---

## 🔧 Example `dongles.conf`

This configuration file controls which dongles are managed during suspend/resume.

- Lines with a serial match only that exact dongle (strict match).
- If the serial is not found, and a fallback is provided, it will match any device with that vendor:product ID.
- You can add `:waitdock` to any entry to delay suspend until a dock state is detected.
- Fallback entries without serials can match any compatible device but are commented out by default.

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
#2dc8:3106
#2dc8:3109

# 🎮 Generic Xbox 360 dongle (always match any & suspend immediately)
045e:028e
```

---

