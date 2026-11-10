#!/bin/bash
###############################################################################
# Restart Reminder — DEMO
#
# Double-click this file on a Mac (or run: bash Restart-Reminder-Demo.command)
# to see what students see, start to finish, in about a minute.
#
# This is a demo only: it installs nothing, needs no admin password, and
# NEVER restarts your Mac.
###############################################################################

ORG_NAME="School IT"
FAKE_UPTIME_DAYS=8
MAX_DEFERRALS=3
COUNTDOWN_SEC=20     # the real tool uses 10 minutes; shortened for the demo

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This demo needs macOS (it uses macOS dialogs)."
  exit 1
fi

TITLE="$ORG_NAME — Restart Required"

# $1=message $2=buttons (AppleScript list) $3=default button $4=timeout seconds
dialog() {
  local r
  r=$(/usr/bin/osascript \
    -e 'on run argv' \
    -e "set r to display dialog (item 1 of argv) with title (item 2 of argv) buttons $2 default button \"$3\" with icon caution giving up after ((item 3 of argv) as integer)" \
    -e 'if gave up of r then return "TIMEOUT"' \
    -e 'return button returned of r' \
    -e 'end run' \
    "$1" "$TITLE" "$4" 2>/dev/null)
  echo "${r:-CANCEL}"
}

info() {
  /usr/bin/osascript -e 'on run argv' \
    -e 'display dialog (item 1 of argv) with title "Restart Reminder Demo" buttons {"Quit Demo", "Continue"} default button "Continue" with icon note' \
    -e 'end run' "$1" >/dev/null 2>&1 || { echo "Demo closed."; exit 0; }
}

would_restart() {
  echo ">>> In a real deployment, the Mac would restart now."
  /usr/bin/osascript -e 'on run argv' \
    -e 'display dialog (item 1 of argv) with title "Restart Reminder Demo" buttons {"Done"} default button "Done" with icon note' \
    -e 'end run' "$1" >/dev/null 2>&1
  echo "Demo complete. Nothing was installed or restarted."
  exit 0
}

clear
echo "=============================================="
echo "  Restart Reminder demo (your Mac will NOT restart)"
echo "=============================================="
echo

info "This demo shows what students see when their Mac has been on too long.

• Pretend uptime: $FAKE_UPTIME_DAYS days
• Postponements allowed: $MAX_DEFERRALS
• Final countdown: $COUNTDOWN_SEC seconds (10 minutes in the real tool)

Click Later to postpone, or Restart Now to see what happens.
Your Mac will NOT actually restart."

deferrals=0
while (( deferrals < MAX_DEFERRALS )); do
  remaining=$(( MAX_DEFERRALS - deferrals ))
  echo "[Reminder $((deferrals + 1))] Showing reminder ($remaining postponement(s) left)..."
  msg="Your Mac has been on for $FAKE_UPTIME_DAYS days. A restart installs updates and keeps it running smoothly.

Save your work and click Restart Now. You can postpone $remaining more time(s) before your Mac restarts automatically."
  choice=$(dialog "$msg" '{"Later", "Restart Now"}' "Restart Now" 120)
  case "$choice" in
    "Restart Now")
      echo "    Student chose: Restart Now"
      would_restart "The student clicked Restart Now.

In a real deployment, macOS would restart now and give open apps a chance to save documents."
      ;;
    *)
      deferrals=$(( deferrals + 1 ))
      echo "    Student chose: Later ($deferrals of $MAX_DEFERRALS postponements used)"
      if (( deferrals < MAX_DEFERRALS )); then
        echo "    (The real tool waits 4 hours here. Skipping ahead for the demo.)"
      fi
      ;;
  esac
done

echo
echo "[Final warning] No postponements left. Starting a ${COUNTDOWN_SEC}s countdown..."
# Terminal countdown runs in the background while the dialog is up
( for ((i=COUNTDOWN_SEC; i>0; i--)); do printf "\r    Restarting in %2ds " "$i"; sleep 1; done; echo ) &
cd_pid=$!

msg="Your Mac has been on for $FAKE_UPTIME_DAYS days and you have used all of your postponements.

It will restart automatically in $COUNTDOWN_SEC seconds. Save your work now."
choice=$(dialog "$msg" '{"OK", "Restart Now"}' "Restart Now" "$COUNTDOWN_SEC")

if [[ "$choice" == "Restart Now" ]]; then
  kill "$cd_pid" 2>/dev/null; wait "$cd_pid" 2>/dev/null; echo
  echo "    Student chose: Restart Now"
  would_restart "The student clicked Restart Now on the final warning.

In a real deployment, the Mac would restart now."
fi

# They clicked OK or ignored the dialog: wait until the countdown runs out
[[ "$choice" == "OK" ]] && printf "\n    Student clicked OK. The countdown keeps going...\n"
wait "$cd_pid" 2>/dev/null
would_restart "The countdown ran out.

In a real deployment, the Mac would restart now, whatever the student did. That's the end of the demo."
