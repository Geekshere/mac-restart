#!/bin/bash
###############################################################################
# Restart Reminder for macOS — MDM installer
#
# Deploy via MDM as a script that runs as root (Jamf policy, Mosyle Custom
# Command, Kandji Custom Script, Intune shell script, etc.).
#
# What it does:
#   * Installs a LaunchDaemon that checks uptime every hour.
#   * Once the Mac has been up for MAX_UPTIME_DAYS, the logged-in student gets
#     a "please restart" dialog (Restart Now / Later).
#   * Each "Later" (or ignored dialog) counts as a deferral. When deferrals
#     run out, the student gets a final warning and the Mac restarts after a
#     countdown.
#   * If no one is logged in (login window), it restarts right away.
#   * It skips the prompt during a video call or presentation (unless the
#     Mac is past HARD_MAX_UPTIME_DAYS).
#
# Jamf script parameters (optional; leave blank to use the defaults below):
#   $4 = MAX_UPTIME_DAYS     $5 = MAX_DEFERRALS
#   $6 = PROMPT_INTERVAL_HRS $7 = FINAL_COUNTDOWN_MIN
#   $8 = ORG_NAME
###############################################################################

# ---------------- Settings (edit these) -------------------------------------
MAX_UPTIME_DAYS="${4:-7}"          # start reminding after this many days of uptime
MAX_DEFERRALS="${5:-3}"            # how many times a student can click "Later"
PROMPT_INTERVAL_HRS="${6:-4}"      # hours between reminders
FINAL_COUNTDOWN_MIN="${7:-10}"     # minutes of warning before a forced restart
ORG_NAME="${8:-School IT}"         # shown in the dialog title
DIALOG_TIMEOUT_SEC=900             # an ignored dialog closes after this and counts as "Later"
HARD_MAX_UPTIME_DAYS=14            # past this, don't skip for meetings or presentations
RESTART_AT_LOGINWINDOW=true        # restart right away if no one is logged in
# -----------------------------------------------------------------------------

LABEL="com.school.restartreminder"
INSTALL_DIR="/Library/Application Support/RestartReminder"
SCRIPT_PATH="$INSTALL_DIR/restart-reminder.sh"
CONFIG_PATH="$INSTALL_DIR/config"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}.plist"

if [[ $EUID -ne 0 ]]; then
  echo "This installer must run as root." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"

# ---- Config file (read by the checker) ---------------------------------------
cat > "$CONFIG_PATH" <<EOF
MAX_UPTIME_DAYS=$MAX_UPTIME_DAYS
MAX_DEFERRALS=$MAX_DEFERRALS
PROMPT_INTERVAL_HRS=$PROMPT_INTERVAL_HRS
FINAL_COUNTDOWN_MIN=$FINAL_COUNTDOWN_MIN
DIALOG_TIMEOUT_SEC=$DIALOG_TIMEOUT_SEC
HARD_MAX_UPTIME_DAYS=$HARD_MAX_UPTIME_DAYS
RESTART_AT_LOGINWINDOW=$RESTART_AT_LOGINWINDOW
ORG_NAME="$ORG_NAME"
EOF

# ---- Checker script ----------------------------------------------------------
cat > "$SCRIPT_PATH" <<'CHECKER'
#!/bin/bash
# Restart Reminder checker. The LaunchDaemon runs this hourly as root.

INSTALL_DIR="/Library/Application Support/RestartReminder"
CONFIG_PATH="$INSTALL_DIR/config"
STATE_PATH="$INSTALL_DIR/state"
LOG="/var/log/restart-reminder.log"

# Defaults (the config file overrides these)
MAX_UPTIME_DAYS=7; MAX_DEFERRALS=3; PROMPT_INTERVAL_HRS=4
FINAL_COUNTDOWN_MIN=10; DIALOG_TIMEOUT_SEC=900; HARD_MAX_UPTIME_DAYS=14
RESTART_AT_LOGINWINDOW=true; ORG_NAME="School IT"
# shellcheck disable=SC1090
[[ -f "$CONFIG_PATH" ]] && source "$CONFIG_PATH"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }

now=$(date +%s)
boot_time=$(sysctl -n kern.boottime | sed -E 's/.*sec = ([0-9]+).*/\1/')
uptime_days=$(( (now - boot_time) / 86400 ))

# ---- State (resets automatically after every reboot) --------------------------
DEFERRALS=0; LAST_PROMPT=0; STATE_BOOT=0
# shellcheck disable=SC1090
[[ -f "$STATE_PATH" ]] && source "$STATE_PATH"
if [[ "$STATE_BOOT" != "$boot_time" ]]; then
  DEFERRALS=0; LAST_PROMPT=0; STATE_BOOT=$boot_time
fi
save_state() {
  printf 'DEFERRALS=%s\nLAST_PROMPT=%s\nSTATE_BOOT=%s\n' \
    "$DEFERRALS" "$LAST_PROMPT" "$STATE_BOOT" > "$STATE_PATH"
}
save_state

# Not due yet
if (( uptime_days < MAX_UPTIME_DAYS )); then
  exit 0
fi

# ---- Who is logged in? -------------------------------------------------------
console_user=$(scutil <<< "show State:/Users/ConsoleUser" \
  | awk '/Name :/ && ! /loginwindow/ { print $3 }')

if [[ -z "$console_user" || "$console_user" == "root" ]]; then
  if [[ "$RESTART_AT_LOGINWINDOW" == "true" ]]; then
    log "Uptime ${uptime_days}d, no user logged in. Restarting now."
    /sbin/shutdown -r now
  fi
  exit 0
fi

user_uid=$(id -u "$console_user")

run_as_user() {
  launchctl asuser "$user_uid" sudo -u "$console_user" "$@"
}

# Shows a dialog to the student. $1=message $2=buttons (AppleScript list) $3=default
# Prints the clicked button, or "TIMEOUT".
show_dialog() {
  local result
  result=$(run_as_user /usr/bin/osascript \
    -e 'on run argv' \
    -e 'set theMsg to item 1 of argv' \
    -e 'set theTitle to item 2 of argv' \
    -e 'set theTimeout to (item 3 of argv) as integer' \
    -e "set r to display dialog theMsg with title theTitle buttons $2 default button \"$3\" with icon caution giving up after theTimeout" \
    -e 'if gave up of r then return "TIMEOUT"' \
    -e 'return button returned of r' \
    -e 'end run' \
    "$1" "$ORG_NAME — Restart Required" "$DIALOG_TIMEOUT_SEC" 2>/dev/null)
  echo "${result:-TIMEOUT}"
}

# Graceful restart: apps get a chance to save open documents.
graceful_restart() {
  run_as_user /usr/bin/osascript -e 'tell application "loginwindow" to «event aevtrrst»' 2>/dev/null
}

# ---- Skip during meetings or presentations (unless far overdue) ----------------
if (( uptime_days < HARD_MAX_UPTIME_DAYS )); then
  if pmset -g assertions 2>/dev/null \
     | grep -E 'PreventUserIdleDisplaySleep' \
     | grep -qiE 'zoom|teams|webex|facetime|keynote|powerpoint|meet'; then
    log "User $console_user is in a meeting or presentation. Skipping this check."
    exit 0
  fi
fi

# ---- Final stage: no deferrals left -----------------------------------------
if (( DEFERRALS >= MAX_DEFERRALS )); then
  log "Uptime ${uptime_days}d, deferrals used up. Forcing restart in ${FINAL_COUNTDOWN_MIN} min."
  /sbin/shutdown -r "+$FINAL_COUNTDOWN_MIN" >/dev/null 2>&1 &
  msg="Your Mac has been on for $uptime_days days and you have used all of your postponements.

It will restart automatically in $FINAL_COUNTDOWN_MIN minutes. Save your work now."
  DIALOG_TIMEOUT_SEC=$(( FINAL_COUNTDOWN_MIN * 60 ))
  choice=$(show_dialog "$msg" '{"OK", "Restart Now"}' "Restart Now")
  if [[ "$choice" == "Restart Now" ]]; then
    log "User $console_user chose Restart Now (final)."
    graceful_restart
  fi
  exit 0
fi

# ---- Reminder stage ------------------------------------------------------------
if (( now - LAST_PROMPT < PROMPT_INTERVAL_HRS * 3600 )); then
  exit 0
fi

remaining=$(( MAX_DEFERRALS - DEFERRALS ))
msg="Your Mac has been on for $uptime_days days. A restart installs updates and keeps it running smoothly.

Save your work and click Restart Now. You can postpone $remaining more time(s) before your Mac restarts automatically."

LAST_PROMPT=$now
save_state

choice=$(show_dialog "$msg" '{"Later", "Restart Now"}' "Restart Now")
case "$choice" in
  "Restart Now")
    log "User $console_user chose Restart Now (uptime ${uptime_days}d)."
    graceful_restart
    ;;
  *)
    DEFERRALS=$(( DEFERRALS + 1 ))
    save_state
    log "User $console_user deferred ($choice). Deferral $DEFERRALS of $MAX_DEFERRALS."
    ;;
esac
exit 0
CHECKER

chown -R root:wheel "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR" "$SCRIPT_PATH"
chmod 644 "$CONFIG_PATH"

# ---- LaunchDaemon ------------------------------------------------------------
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPT_PATH}</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
EOF
chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"

# Reload the daemon (safe to re-run for updates)
launchctl bootout system "$PLIST_PATH" 2>/dev/null
launchctl bootstrap system "$PLIST_PATH"

echo "Restart Reminder installed: reminders start at ${MAX_UPTIME_DAYS} days of uptime, ${MAX_DEFERRALS} deferrals, checked hourly."
exit 0
