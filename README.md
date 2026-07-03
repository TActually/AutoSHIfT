# ***AutoSHIfT*** 
## About
Autoshift seamlessly combines **system snapshots** (via Timeshift) with **package updates** (DNF + Flatpak), ensuring your system is always backed up before any changes are applied.<BR>
It is a bash script that aims to provide similar functionality as timeshift-autosnap, written by Marko Gobin.<BR>
I say similar because:<BR>
1.	This script does not add hooks to the package manager.
	Which means you can still use DNF to install and remove applications without triggering a backup every single time.
2.	The script is set to execute via systemd timer, once a week.<BR>
	The default is Saturday at 7AM, but you can change those variables before executing the script.
3.	AutoSHIfT is made for use with RHEL/Fedora based systems that utilize the DNF package manager<BR>
	***System Requirements:***<BR>
    RHEL or Fedora based OS utilizing dnf as it's package manager.<BR>
	Systemd Init system (default for RHEL/Fedora distros)<BR>
	Wayland display protocols (See OG-AutoSHIfT if you are still on X11)<BR>
	Timeshift backup utility (script will install if not present)<BR>
	notify-send (Script will install if not present)<BR>
	

## ✨ Key Features

- **Safety First:** Creates a **Timeshift** snapshot *before* attempting any package updates. If the backup fails, updates are aborted.
- **Wayland Native:** Fully compatible with modern Wayland sessions (GNOME, KDE Plasma, Sway, Hyprland) for accurate user detection and desktop notifications.
- **Secure Architecture:** Uses a **`systemd --user`** timer for scheduling and a tightly scoped **`sudoers`** rule for privileged actions, avoiding full root execution for the main logic.
- **Smart Rotation:** Automatically manages snapshot rotation (keeping the 6 most recent) and handles complex **Btrfs nested subvolumes** cleanup.
- **Dual-Source Updates:** Updates both system packages (`dnf`) and sandboxed applications (`flatpak`).
- **Self-Installing:** The script installs itself, sets up the timer, and configures the necessary permissions on first run.

## 🏗️ Architecture

- **User Space:** The main logic runs as the active desktop user, handling environment detection, notifications, and Flatpak updates.
- **Privileged Space:** Sensitive operations (DNF, Timeshift, mounting) are delegated to a `root_helper` function via a passwordless `sudoers` alias, ensuring the principle of least privilege.
- **Scheduling:** Uses `systemd --user` timers with `Persistent=true` to ensure updates run even if the machine was asleep at the scheduled time.

## ⚙️ User-Editable Configuration

The following variables are located at the top of the script under the `# --- Configuration ---` section. <BR>
#### Edit variables BEFORE running the script for the first time or accept defaults.
#### Variables not listed SHOULD NOT be edited.
| Variable | Default | Description |
| :--- | :--- | :--- |
| `TIMER_DAY` | `Sat` | Day of the week for the weekly update. Accepts numbers (`0`=Sun to `6`=Sat) or 3-letter codes (`Sun`, `Mon`, etc.). |
| `TIMER_HOUR` | `07` | Hour of the day (24-hour format) to run the update. e.g., `07` for 7:00 AM. |
| `MAX_BACKUPS` | `6` | Maximum number of Timeshift snapshots to retain. Older snapshots are automatically deleted. |
| `LOG_RETENTION_DAYS` | `31` | Number of days to keep execution logs before automatically pruning them. |

### Example Configuration
To run updates every **Wednesday at 10:00 PM**, keeping **10 backups** and logs for **60 days**:

```bash
TIMER_DAY="Wed"
TIMER_HOUR="22"
MAX_BACKUPS=10
LOG_RETENTION_DAYS=60
```
## 🚀 Installation

1. Clone the repository or download the `AutoSHIfT.sh` script.
2. Make it executable:
   ```bash
   chmod +x AutoSHIfT.sh
3. Run as root (or with sudo) to install:
   ```bash
   sudo ./AutoSHIfT.sh
   ```
4.	**First-Time Setup:** The script will copy itself to `/usr/local/bin/AutoSHIfT`, create the systemd service & timer, create a sudoers rule, create a manual run commmand, then exit.<BR>
   System backup & update is **NOT** run at this time. You can manually execute using the newly created command or wait for the schedule run.

## 🛠️ Manual Execution
To trigger an update immediately without waiting for the schedule, use the helper command created during installation:
```bash 
AutoSHIfT-now
```
This will start the service, in the background. You will get desktop notifications and/or the opening of the log file, depending on the results.

## 📂 File Locations

- **Script:** `/usr/local/bin/AutoSHIfT`
- **Service/Timer:** `~/.config/systemd/user/AutoSHIfT.{service,timer}`<BR>
	To change the execution time, after first run, edit `~/config/systemd/user/AutoSHIfT.timer`.<BR>
	[Understanding Systemd Timers](https://blog.techiescamp.com/systemd-timers/)
- **Logs:** `~/AutoSHIfT/logs/`
- **Sudoers Rule:** `/etc/sudoers.d/AutoSHIfT-<username>`

## 🛡️ Security Model

AutoSHIfT adheres to strict security practices:
1. **No Full Root Execution:** The main script runs as the user.
2. **Scoped Privileges:** The `sudoers` rule allows *only* specific helper commands (e.g., `dnf upgrade`, `timeshift create`) and nothing else.
3. **Input Validation:** All device paths, UUIDs, and snapshot names are validated before execution to prevent injection attacks.
4. **Session Awareness:** Detects the active Wayland session to ensure updates run in the correct user context.

## 📝 Troubleshooting

- **Notifications not showing?**
  Ensure `libnotify` is installed (`dnf install libnotify`). The script attempts to install `notify-send` automatically.
- **Timeshift not configured?**
  The script will detect this and exit. Launch the Timeshift GUI and configure it. [🔗Timeshift Instructions](https://github.com/linuxmint/timeshift)
- **Timer not starting?**
  Check the user systemd status:
  ```bash
  systemctl --user status AutoSHIfT.timer
  ```
  If the user session bus is not running (e.g., after a reboot before login), the timer will wait until the user logs in.

## 📜 License

This project is licensed under the **GNU GPL v3.0**. See the `LICENSE` file for details.

## 🫱🏿‍🫲🏼 Acknowledgments

- **Original Concept:** T Actually
- **Refactoring & Security Hardening:** Brave Leo AI Assistant, GPT-5.5 Thinking
- Inspiration for this script comes from<BR>
	https://gitlab.com/gobonja/timeshift-autosnap <BR>
	https://github.com/wmutschl/timeshift-autosnap-apt
