#!/usr/bin/env bash
################################################################################
#  AutoSHIfT - Automated System Backup & Update for DNF/Systemd/Wayland Systems
#  Original Author: T Actually (tactually@outlook.com)
#  Refactored for Universal Wayland Support by: Brave Leo AI Assistant (2026)
#  Refactored for systemd --user + sudoers separation by: GPT-5.5 Thinking (2026)
#  Security-tightened Option 1 refactor by: GPT-5.5 Thinking (2026)
#  License: GNU GPL v3.0
#  Documentation: https://github.com/TActually/AutoSHIfT
#
#  Compatibility:
#  - DNF Package Manager (Fedora, RHEL, AlmaLinux, Rocky, etc.)
#  - Systemd Init System
#  - Wayland Display Server (GNOME, KDE Plasma, Sway, Hyprland, etc.)
#
#  Functions:
#  1. Self-Installation (Moves to /usr/local/bin, creates systemd --user files)
#  2. Auto-Installs Timeshift if missing, then exits for configuration
#  3. Creates Timeshift snapshot (rotating old ones, handles Btrfs nested subvolumes)
#  4. Updates DNF packages (ONLY if backup succeeds)
#  5. Updates Flatpak applications as the active desktop user
#  6. Sends Wayland-native notification on completion or failure
################################################################################

set -euo pipefail

# --- Configuration ---
SCRIPT_NAME="AutoSHIfT"
INSTALL_PATH="/usr/local/bin/AutoSHIfT"
SERVICE_NAME="AutoSHIfT.service"
TIMER_NAME="AutoSHIfT.timer"
# TIMER_DAY: 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat(DEFAULT)
# TIMER_HOUR: Hour in 24-hour format (0-23). 07 = 7AM (DEFAULT)
# Leave DEFAULT or edit to your liking. DAY can be number or 3-letter-code.
TIMER_DAY="Sat"
TIMER_HOUR="07"
MAX_BACKUPS=6
LOG_RETENTION_DAYS=31
SUDOERS_PREFIX="/etc/sudoers.d/AutoSHIfT"


# --- Helper Functions ---
log_msg() {
    echo -e "\e[36m>>> AutoSHIfT: $1\e[0m"
}

error_msg() {
    echo -e "\e[31m>>> ERROR: $1\e[0m"
}

# --- Active User Discovery ---
get_active_LIUSER() {
    local current_LIUSER=""
    local sudo_LIUSER="${SUDO_USER:-}"
    local session uid session_LIUSER seat tty props active remote class type candidate="" fallback=""

    if [[ "${EUID}" -ne 0 ]]; then
        id -un
        return 0
    fi

    if [[ -n "$sudo_LIUSER" && "$sudo_LIUSER" != "root" ]] && id "$sudo_LIUSER" &>/dev/null; then
        current_LIUSER="$sudo_LIUSER"
    fi

    while read -r session uid session_LIUSER seat tty; do
        [[ -n "${session:-}" ]] || continue
        [[ -n "${session_LIUSER:-}" && "$session_LIUSER" != "root" ]] || continue

        props=$(loginctl show-session "$session" \
            -p Active -p Remote -p Class -p Type 2>/dev/null || true)
        active=$(awk -F= '$1 == "Active" {print $2}' <<< "$props")
        remote=$(awk -F= '$1 == "Remote" {print $2}' <<< "$props")
        class=$(awk -F= '$1 == "Class" {print $2}' <<< "$props")
        type=$(awk -F= '$1 == "Type" {print $2}' <<< "$props")

        [[ "$remote" == "no" ]] || continue
        [[ "$class" == "user" || -z "$class" ]] || continue

        if [[ "$active" == "yes" && "$type" == "wayland" ]]; then
            echo "$session_LIUSER"
            return 0
        fi

        if [[ "$active" == "yes" && -z "$candidate" ]]; then
            candidate="$session_LIUSER"
        fi

        if [[ -z "$fallback" ]]; then
            fallback="$session_LIUSER"
        fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null || true)

    if [[ -n "$current_LIUSER" ]]; then
        echo "$current_LIUSER"
        return 0
    fi

    if [[ -n "$candidate" ]]; then
        echo "$candidate"
        return 0
    fi

    if [[ -n "$fallback" ]]; then
        echo "$fallback"
        return 0
    fi

    if getent passwd 1000 >/dev/null 2>&1; then
        getent passwd 1000 | cut -d: -f1
        return 0
    fi

    echo "ERROR: No suitable user session found." >&2
    return 1
}

get_LIUSER_home() {
    getent passwd "$1" | cut -d: -f6
}

get_LIUSER_group() {
    id -gn "$1"
}

need_root_helper_cmd() {
    local label="$1"
    shift
    local candidate

    for candidate in "$@"; do
        if [[ -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    echo "Required command not found for root helper: $label" >&2
    return 127
}

validate_snapshot_name() {
    [[ "${1:-}" =~ ^[A-Za-z0-9._:@+=-]+$ ]]
}

validate_uuid() {
    [[ "${1:-}" =~ ^[A-Fa-f0-9-]+$ ]]
}

validate_device_path() {
    [[ "${1:-}" == /dev/* && "${1:-}" != *..* ]]
}

validate_tmp_path() {
    [[ ( "${1:-}" == /tmp/* || "${1:-}" == /var/tmp/* ) && "${1:-}" != *..* ]]
}

# --- Privileged Root Helper ---
root_helper() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Root helper must be executed as root." >&2
        return 1
    fi

    local action="${1:-}"
    [[ $# -gt 0 ]] && shift

    local dnf_bin timeshift_bin mount_bin umount_bin btrfs_bin blkid_bin

    case "$action" in
        dnf-install-timeshift)
            [[ $# -eq 0 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            dnf_bin=$(need_root_helper_cmd dnf /usr/bin/dnf /usr/bin/dnf5)
            "$dnf_bin" install -y timeshift
            ;;
        dnf-clean)
            [[ $# -eq 0 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            dnf_bin=$(need_root_helper_cmd dnf /usr/bin/dnf /usr/bin/dnf5)
            "$dnf_bin" clean all
            ;;
        dnf-upgrade)
            [[ $# -eq 0 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            dnf_bin=$(need_root_helper_cmd dnf /usr/bin/dnf /usr/bin/dnf5)
            "$dnf_bin" upgrade -y
            ;;
        timeshift-list)
            [[ $# -eq 0 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            timeshift_bin=$(need_root_helper_cmd timeshift /usr/bin/timeshift /usr/sbin/timeshift)
            "$timeshift_bin" --list
            ;;
        timeshift-create)
            [[ $# -eq 0 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            timeshift_bin=$(need_root_helper_cmd timeshift /usr/bin/timeshift /usr/sbin/timeshift)
            "$timeshift_bin" --create --comment "AutoSHIfT" --scripted
            ;;
        timeshift-delete)
            [[ $# -eq 1 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            validate_snapshot_name "$1" || { echo "Invalid snapshot name: $1" >&2; return 2; }
            timeshift_bin=$(need_root_helper_cmd timeshift /usr/bin/timeshift /usr/sbin/timeshift)
            "$timeshift_bin" --delete --snapshot "$1" --yes --scripted
            ;;
        blkid-uuid)
            [[ $# -eq 1 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            validate_uuid "$1" || { echo "Invalid UUID: $1" >&2; return 2; }
            blkid_bin=$(need_root_helper_cmd blkid /usr/sbin/blkid /usr/bin/blkid /sbin/blkid)
            "$blkid_bin" -U "$1"
            ;;
        mount-btrfs-root)
            [[ $# -eq 2 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            validate_device_path "$1" || { echo "Invalid device path: $1" >&2; return 2; }
            validate_tmp_path "$2" || { echo "Invalid mount point: $2" >&2; return 2; }
            mount_bin=$(need_root_helper_cmd mount /usr/bin/mount /bin/mount)
            "$mount_bin" -o subvolid=5 "$1" "$2"
            ;;
        umount)
            [[ $# -eq 1 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            validate_tmp_path "$1" || { echo "Invalid mount point: $1" >&2; return 2; }
            umount_bin=$(need_root_helper_cmd umount /usr/bin/umount /bin/umount)
            "$umount_bin" "$1"
            ;;
        btrfs-subvolume-list)
            [[ $# -eq 1 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            validate_tmp_path "$1" || { echo "Invalid btrfs path: $1" >&2; return 2; }
            btrfs_bin=$(need_root_helper_cmd btrfs /usr/sbin/btrfs /usr/bin/btrfs /sbin/btrfs)
            "$btrfs_bin" subvolume list "$1"
            ;;
        btrfs-subvolume-delete)
            [[ $# -eq 1 ]] || { echo "Invalid arguments for $action" >&2; return 2; }
            validate_tmp_path "$1" || { echo "Invalid btrfs path: $1" >&2; return 2; }
            btrfs_bin=$(need_root_helper_cmd btrfs /usr/sbin/btrfs /usr/bin/btrfs /sbin/btrfs)
            "$btrfs_bin" subvolume delete "$1"
            ;;
        *)
            echo "Unknown root helper action: ${action:-<none>}" >&2
            return 2
            ;;
    esac
}

if [[ "${1:-}" == "--root-helper" ]]; then
    shift
    root_helper "$@"
    exit $?
fi

# --- Installation Helpers ---
run_LIUSER_systemctl() {
    local LIUSER="$1"
    local LIUSER_home="$2"
    shift 2

    local LIUSER_UID
    LIUSER_UID=$(id -u "$LIUSER")

    sudo -u "$LIUSER" \
        env \
        HOME="$LIUSER_home" \
        XDG_RUNTIME_DIR="/run/user/$LIUSER_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$LIUSER_UID/bus" \
        systemctl --user "$@"
}

install_sudoers_rule() {
    local LIUSER="$1"
    local LIUSER_UID="$2"
    local sudoers_file="$SUDOERS_PREFIX-$LIUSER"
    local sudoers_alias="AUTOSHIFT_${LIUSER_UID}_HELPER"
    local tmp_file

    if [[ ! "$LIUSER" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        error_msg "Unsupported username for sudoers automation: $LIUSER"
        echo "Create a sudoers rule manually for: $INSTALL_PATH --root-helper *"
        exit 1
    fi

    tmp_file=$(mktemp)
    cat > "$tmp_file" <<EOF_SUDOERS
# AutoSHIfT passwordless root helper rule
# Created by AutoSHIfT installer. The script is root-owned and validates helper actions internally.
Cmnd_Alias $sudoers_alias = $INSTALL_PATH --root-helper *
$LIUSER ALL=(root) NOPASSWD: $sudoers_alias
EOF_SUDOERS

    if ! visudo -cf "$tmp_file" >/dev/null; then
        rm -f "$tmp_file"
        error_msg "Generated sudoers rule failed validation. Installation stopped."
        exit 1
    fi

    install -o root -g root -m 0440 "$tmp_file" "$sudoers_file"
    rm -f "$tmp_file"

    if ! visudo -cf "$sudoers_file" >/dev/null; then
        rm -f "$sudoers_file"
        error_msg "Installed sudoers rule failed validation and was removed."
        exit 1
    fi
}

remove_legacy_system_units() {
    local changed="false"

    if [[ -f "/etc/systemd/system/$SERVICE_NAME" || -f "/etc/systemd/system/$TIMER_NAME" ]]; then
        log_msg "Removing legacy system-level AutoSHIfT units..."
        systemctl disable --now "$TIMER_NAME" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/$SERVICE_NAME" "/etc/systemd/system/$TIMER_NAME"
        changed="true"
    fi

    if [[ "$changed" == "true" ]]; then
        systemctl daemon-reload || true
    fi
}

remove_og_anacron_install() {
    local anacrontab_file="/etc/anacrontab"
    local tmp_file referenced_path normalized_path
    local -a referenced_paths=()

    [[ -f "$anacrontab_file" ]] || return 0

    while IFS= read -r referenced_path; do
        [[ -n "$referenced_path" ]] && referenced_paths+=("$referenced_path")
    done < <(awk '''
        $1 == "@weekly" && $2 == "0" && $3 == "AutoSHIfT" && $4 ~ /^(\.\/home|\/home)\/[^/]+\/AutoSHIfT\/AutoSHIfT\.sh$/ { print $4 }
    ''' "$anacrontab_file")

    [[ "${#referenced_paths[@]}" -gt 0 ]] || return 0

    log_msg "Removing the OG version of AutoSHIfT"

    tmp_file=$(mktemp)
    awk '''
        !($1 == "@weekly" && $2 == "0" && $3 == "AutoSHIfT" && $4 ~ /^(\.\/home|\/home)\/[^/]+\/AutoSHIfT\/AutoSHIfT\.sh$/)
    ''' "$anacrontab_file" > "$tmp_file"

    install -o root -g root -m 0644 "$tmp_file" "$anacrontab_file"
    rm -f "$tmp_file"

    for referenced_path in "${referenced_paths[@]}"; do
        if [[ "$referenced_path" == ./* ]]; then
            normalized_path="/${referenced_path#./}"
        else
            normalized_path="$referenced_path"
        fi

        if [[ "$normalized_path" =~ ^/home/[^/]+/AutoSHIfT/AutoSHIfT\.sh$ ]]; then
            rm -f "$normalized_path"
        fi
    done
}

# --- Manual Backup and Update command (AutoSHIfT-now) ---
create_AutoSHIfT_now_command() {
    log_msg "Creating AutoSHIfT-now manual update command..."

    cat > /usr/local/bin/AutoSHIfT-now << 'EOF'
#!/usr/bin/env bash
systemctl --user start --no-block AutoSHIfT.service
EOF

    chown root:root /usr/local/bin/AutoSHIfT-now
    chmod 755 /usr/local/bin/AutoSHIfT-now
}

# -- notify-send validation: installs if not present--
ensure_notify_send_available() {
    if command -v notify-send >/dev/null 2>&1; then
        return 0
    fi

    echo ""
    echo -e "\e[33m>>> AutoSHIfT: notify-send not found. Installing desktop notification support...\e[0m"

    if dnf install -y /usr/bin/notify-send; then
        echo -e "\e[32m>>> AutoSHIfT: notify-send installed successfully.\e[0m"
    else
        echo -e "\e[31m>>> AutoSHIfT: Failed to install notify-send. Desktop notifications may not work.\e[0m"
        return 1
    fi
}

# --- Installation Logic (Runs only if not yet installed) ---
perform_installation() {
    local LIUSER LIUSER_UID LIUSER_GROUP LIUSER_home LIUSER_systemd_dir

    LIUSER=$(get_active_LIUSER)
    LIUSER_UID=$(id -u "$LIUSER")
    LIUSER_GROUP=$(get_LIUSER_group "$LIUSER")
    LIUSER_home=$(get_LIUSER_home "$LIUSER")
    LIUSER_systemd_dir="$LIUSER_home/.config/systemd/user"

    log_msg "Starting AutoSHIfT Installation for user: $LIUSER"
    sleep 1

    # 1. Move script to permanent location (Force overwrite)
    log_msg "Moving script to $INSTALL_PATH..."
    install -o root -g root -m 0755 "$0" "$INSTALL_PATH"

    # 2. Remove old system-level units from previous AutoSHIfT versions
    remove_legacy_system_units
    remove_og_anacron_install

    # 3. Create sudoers rule for the active user's root helper access
    log_msg "Creating sudoers rule for passwordless AutoSHIfT root helper..."
    install_sudoers_rule "$LIUSER" "$LIUSER_UID"

    # 4. Check for Notify-send and install if needed
    ensure_notify_send_available

    # 5. Create user-level Systemd Service File
    log_msg "Creating systemd --user service..."
    install -d -o "$LIUSER" -g "$LIUSER_GROUP" -m 0755 "$LIUSER_systemd_dir"

    cat > "$LIUSER_systemd_dir/$SERVICE_NAME" <<EOF_SERVICE
[Unit]
Description=AutoSHIfT System Backup and Update
Documentation=https://github.com/TActually/AutoSHIfT
After=default.target

[Service]
Type=oneshot
ExecStart=$INSTALL_PATH
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=XDG_RUNTIME_DIR=%t
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF_SERVICE

    chown "$LIUSER:$LIUSER_GROUP" "$LIUSER_systemd_dir/$SERVICE_NAME"
    chmod 0644 "$LIUSER_systemd_dir/$SERVICE_NAME"

    # 6. Create user-level Systemd Timer File (Weekly with Persistence)
    log_msg "Creating systemd --user timer (Weekly schedule: $TIMER_DAY at $TIMER_HOUR:00)..."

    TIMER_HOUR=$(printf "%02d" "$TIMER_HOUR" 2>/dev/null || echo "$TIMER_HOUR")

    cat > "$LIUSER_systemd_dir/$TIMER_NAME" <<EOF_TIMER
[Unit]
Description=Run AutoSHIfT Weekly
Documentation=https://github.com/TActually/AutoSHIfT

[Timer]
OnCalendar=$TIMER_DAY *-*-* ${TIMER_HOUR}:00:00
Persistent=true
RandomizedDelaySec=120
Unit=$SERVICE_NAME

[Install]
WantedBy=timers.target
EOF_TIMER

    chown "$LIUSER:$LIUSER_GROUP" "$LIUSER_systemd_dir/$TIMER_NAME"
    chmod 0644 "$LIUSER_systemd_dir/$TIMER_NAME"

    # 7. Reload user systemd and enable/start timer
    if [[ ! -S "/run/user/$LIUSER_UID/bus" ]]; then
        error_msg "No active user bus found at /run/user/$LIUSER_UID/bus."
        echo "Log in graphically as $LIUSER, then run:"
        echo "  systemctl --user daemon-reload"
        echo "  systemctl --user enable --now $TIMER_NAME"
        exit 1
    fi

    log_msg "Reloading systemd --user daemon..."
    run_LIUSER_systemctl "$LIUSER" "$LIUSER_home" daemon-reload

    log_msg "Enabling and starting AutoSHIfT user timer..."
    run_LIUSER_systemctl "$LIUSER" "$LIUSER_home" enable --now "$TIMER_NAME"

    # 8. Create AutoSHIfT-now command to run manual updates with terminal output
    create_AutoSHIfT_now_command

    # 9. Verification
    echo ""
    log_msg "Installation Complete!"
    echo "---------------------------------------------------------"
    echo "AutoSHIfT is now installed and scheduled for user: $LIUSER"
    echo "Next scheduled run: "
    run_LIUSER_systemctl "$LIUSER" "$LIUSER_home" list-timers "$TIMER_NAME" --no-pager | grep -v "NEXT" | head -n 1 || echo "Could not determine next run time."
    echo ""
    echo "How it works:"
    echo "  - AutoSHIfT will run as a systemd --user timer every $TIMER_DAY at ${TIMER_HOUR}:00 AM."
    echo "  - If system is off, asleep or in use by a different user, AutoSHIfT wil run at the next available time."
    echo "  - Privileged actions run through a narrow sudoers root-helper rule."
    echo "  - You will receive a desktop notification upon completion when the session bus is available."
    echo "  - Logs are stored in $LIUSER_home/AutoSHIfT/logs/"
    echo ""
    echo "No update has been ran, yet."
    echo "To manually trigger AutoSHIfT, run command:  AutoSHIfT-now"
    echo ""
    echo "Need to change the execution time?"
    echo "Edit this file: $LIUSER_systemd_dir/$TIMER_NAME"
    echo "---------------------------------------------------------"

    exit 0
}

# --- Check Installation Status ---
if [[ "$(readlink -f "$0")" != "$INSTALL_PATH" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        error_msg "First run installation must be performed as root (sudo)."
        exit 1
    fi
    perform_installation
fi

# --- Runtime Logic (Executes after installation) ---

root_cmd() {
    if [[ "$EUID" -eq 0 ]]; then
        root_helper "$@"
    else
        sudo -n "$INSTALL_PATH" --root-helper "$@"
    fi
}

# Initialize User and Environment
LIUSER=$(get_active_LIUSER)
LIUSER_UID=$(id -u "$LIUSER")
LIUSER_GROUP=$(get_LIUSER_group "$LIUSER")
HOME_DIR=$(get_LIUSER_home "$LIUSER")
LOG_DIR="$HOME_DIR/AutoSHIfT/logs"
LOG_FILE=$(date +%Y%m%d-%H%M%S).log

if [[ "$EUID" -eq 0 ]]; then
    install -d -o "$LIUSER" -g "$LIUSER_GROUP" -m 0755 "$LOG_DIR"
else
    mkdir -p "$LOG_DIR"
fi

log() {
    local msg="[$(date '+%F %T')] $1"
    echo "$msg" | tee -a "$LOG_DIR/$LOG_FILE"
}

ensure_session_environment() {
    export HOME="$HOME_DIR"
    export USER="$LIUSER"
    export LOGNAME="$LIUSER"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$LIUSER_UID}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        local wayland_socket=""
        for wayland_socket in "$XDG_RUNTIME_DIR"/wayland-*; do
            if [[ -S "$wayland_socket" ]]; then
                export WAYLAND_DISPLAY="$(basename "$wayland_socket")"
                break
            fi
        done
    fi

    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

    if [[ ! -S "$XDG_RUNTIME_DIR/bus" ]]; then
        log "Warning: User session bus not found at $XDG_RUNTIME_DIR/bus. Notifications and desktop open may be skipped."
    fi

    if [[ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]; then
        log "Warning: Wayland socket not found at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY. Continuing with DBus-only desktop actions."
    fi
}

run_as_active_LIUSER() {
    local -a env_vars

    env_vars=(
        "HOME=$HOME_DIR"
        "USER=$LIUSER"
        "LOGNAME=$LIUSER"
        "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
        "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
        "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    )

    if [[ -n "${DISPLAY:-}" ]]; then
        env_vars+=("DISPLAY=$DISPLAY")
    fi

    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        env_vars+=("XDG_CURRENT_DESKTOP=$XDG_CURRENT_DESKTOP")
    fi

    if [[ "$EUID" -eq 0 ]]; then
        sudo -u "$LIUSER" env "${env_vars[@]}" "$@"
    else
        env "${env_vars[@]}" "$@"
    fi
}

open_log_file() {
    if [[ -S "$XDG_RUNTIME_DIR/bus" ]]; then
        run_as_active_LIUSER /usr/bin/xdg-open "$LOG_DIR/$LOG_FILE" >/dev/null 2>&1 &
    else
        log "Warning: Cannot open log for $LIUSER. No active session bus detected."
    fi
}

send_notification() {
    local title="$1"
    local body="$2"
    local urgency="$3"

    if [[ ! -S "$XDG_RUNTIME_DIR/bus" ]]; then
        return 0
    fi

    if [[ ! -x /usr/bin/notify-send ]]; then
        log "Warning: notify-send not found. Skipping desktop notification."
        return 0
    fi

    run_as_active_LIUSER /usr/bin/notify-send \
        -a "$SCRIPT_NAME" \
        -u "$urgency" \
        "$title" \
        "$body" \
        2>/dev/null || true
}

ensure_session_environment
log "=== AutoSHIfT Started for user: $LIUSER ==="

# --- Timeshift Check & Auto-Install ---
if ! command -v timeshift &> /dev/null; then
    log "Timeshift not found. Installing automatically..."
    echo ""
    echo -e "\e[33m>>> AutoSHIfT is installing Timeshift...\e[0m"

    if root_cmd dnf-install-timeshift; then
        echo ""
        echo -e "\e[32m>>> Timeshift installed successfully!\e[0m"
        echo ""
        echo "---------------------------------------------------------"
        echo "IMPORTANT: Timeshift requires manual configuration before AutoSHIfT can run."
        echo ""
        echo "Next Steps:"
        echo "  1. Launch Timeshift from your application menu."
        echo "  2. Select your snapshot type (BTRFS or RSYNC)."
        echo "  3. Choose your backup storage location."
        echo "  4. Complete the setup wizard."
        echo ""
        echo "Once configured, AutoSHIfT will run automatically on its next scheduled time."
        echo "Need to manually run an update? Run 'AutoSHIfT-now'."
        echo "---------------------------------------------------------"
        echo ""

        send_notification "AutoSHIfT Setup" "Timeshift installed. Please configure it before backups can begin. Re-run when done!" "critical"
        exit 0
    else
        log "CRITICAL ERROR: Failed to install Timeshift."
        send_notification "AutoSHIfT FAILED" "Could not install Timeshift. Please install manually. Re-run when done!" "critical"
        exit 1
    fi
fi

# --- Verify Timeshift Configuration ---
TS_CONFIG=""
if [[ -f "/etc/timeshift/timeshift.json" ]]; then
    TS_CONFIG="/etc/timeshift/timeshift.json"
elif [[ -f "/etc/timeshift.json" ]]; then
    TS_CONFIG="/etc/timeshift.json"
fi

if [[ -z "$TS_CONFIG" ]]; then
    log "Timeshift is installed but NOT configured."
    echo ""
    echo -e "\e[33m>>> Timeshift is not configured yet!\e[0m"
    echo ""
    echo "Please launch Timeshift and complete the setup wizard."
    echo "AutoSHIfT cannot create backups until Timeshift is configured."
    echo ""

    send_notification "AutoSHIfT Warning" "Timeshift is installed but needs configuration. Re-run when done!" "critical"
    exit 0
fi

# Detect Timeshift mode (BTRFS or RSYNC)
if grep -q '"btrfs_mode"[[:space:]]*:[[:space:]]*"true"' "$TS_CONFIG" 2>/dev/null; then
    TS_MODE="btrfs"
else
    TS_MODE="rsync"
fi
log "Detected Timeshift mode: $TS_MODE"

# --- Timeshift Backup Logic ---
TS_LIST_OUTPUT=$(root_cmd timeshift-list 2>/dev/null || true)
TS_COUNT=$(grep -cE "^[0-9]+" <<< "$TS_LIST_OUTPUT" || true)
log "Current snapshot count: $TS_COUNT (Max allowed: $MAX_BACKUPS)"

if [[ "$TS_COUNT" -ge "$MAX_BACKUPS" ]]; then
    log "Deleting oldest backup..."
    OLDEST_SNAPSHOT=$(awk '/^[0-9]+/ {print $2; exit}' <<< "$TS_LIST_OUTPUT")

    if [[ -n "$OLDEST_SNAPSHOT" ]]; then
        if [[ "$TS_MODE" == "btrfs" ]]; then
            TS_DEVICE_UUID=$(grep -o '"backup_device_uuid"[[:space:]]*:[[:space:]]*"[^"]*"' "$TS_CONFIG" 2>/dev/null | cut -d'"' -f4 || true)
            TS_DEVICE=""

            if [[ -n "$TS_DEVICE_UUID" ]]; then
                TS_DEVICE=$(root_cmd blkid-uuid "$TS_DEVICE_UUID" 2>/dev/null || true)
            fi

            if [[ -n "$TS_DEVICE" ]]; then
                MOUNT_POINT=$(mktemp -d)

                if root_cmd mount-btrfs-root "$TS_DEVICE" "$MOUNT_POINT" 2>/dev/null; then
                    SNAPSHOT_PATH="$MOUNT_POINT/timeshift-btrfs/snapshots/$OLDEST_SNAPSHOT"

                    if [[ -d "$SNAPSHOT_PATH" ]]; then
                        NESTED_SUBVOLS=$(root_cmd btrfs-subvolume-list "$SNAPSHOT_PATH" 2>/dev/null | awk '{print $NF}' | sort -r || true)
                        while IFS= read -r subvol; do
                            [[ -n "$subvol" ]] || continue
                            root_cmd btrfs-subvolume-delete "$SNAPSHOT_PATH/$subvol" 2>/dev/null || true
                        done <<< "$NESTED_SUBVOLS"

                        root_cmd timeshift-delete "$OLDEST_SNAPSHOT" || true
                    else
                        log "Warning: Expected Timeshift snapshot path not found: $SNAPSHOT_PATH"
                        root_cmd timeshift-delete "$OLDEST_SNAPSHOT" || true
                    fi

                    root_cmd umount "$MOUNT_POINT" 2>/dev/null || true
                else
                    log "Warning: Could not mount Btrfs root for nested subvolume cleanup. Falling back to Timeshift delete."
                    root_cmd timeshift-delete "$OLDEST_SNAPSHOT" || true
                fi

                rmdir "$MOUNT_POINT" 2>/dev/null || true
            else
                log "Warning: Could not resolve Timeshift backup device UUID. Falling back to Timeshift delete."
                root_cmd timeshift-delete "$OLDEST_SNAPSHOT" || true
            fi
        else
            root_cmd timeshift-delete "$OLDEST_SNAPSHOT" || true
        fi
    fi
fi

log "Creating new Timeshift snapshot..."
if ! root_cmd timeshift-create; then
    log "CRITICAL ERROR: Timeshift snapshot creation FAILED. Aborting updates."
    send_notification "AutoSHIfT FAILED" "System backup failed. Updates skipped for safety." "critical"
    exit 1
fi
log "Snapshot created successfully."

# --- System Updates (DNF) ---
OVERALL_STATUS="success"
log "Running DNF update..."
root_cmd dnf-clean &>/dev/null || log "Warning: DNF clean failed; continuing to upgrade."

if ! root_cmd dnf-upgrade 2>&1 | tee -a "$LOG_DIR/$LOG_FILE"; then
    log "ERROR: DNF update failed."
    OVERALL_STATUS="partial"
else
    log "DNF update completed successfully."
fi

# --- Flatpak Updates ---
log "Running Flatpak update..."
if command -v flatpak &>/dev/null; then
    if ! run_as_active_LIUSER flatpak update -y --noninteractive 2>&1 | tee -a "$LOG_DIR/$LOG_FILE"; then
        log "ERROR: Flatpak update failed."
        OVERALL_STATUS="partial"
    else
        log "Flatpak update completed successfully."
    fi
else
    log "Flatpak not found. Skipping Flatpak updates."
fi

# --- Log Pruning ---
log "Pruning logs older than $LOG_RETENTION_DAYS days..."
find "$LOG_DIR" -type f -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete

log "=== AutoSHIfT Finished ==="

# --- Final Notification & Log Opening ---
if [[ "$OVERALL_STATUS" == "success" ]]; then
    send_notification "AutoSHIfT Complete" "System backup and updates finished successfully." "normal"
    open_log_file
else
    send_notification "AutoSHIfT Warning" "Backup succeeded, but some updates failed. Check logs." "critical"
    open_log_file
fi

exit 0
