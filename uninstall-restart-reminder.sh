#!/bin/bash
# Removes Restart Reminder. Run as root through MDM.
LABEL="com.school.restartreminder"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
launchctl bootout system "$PLIST" 2>/dev/null
rm -f "$PLIST"
rm -rf "/Library/Application Support/RestartReminder"
rm -f /var/log/restart-reminder.log
echo "Restart Reminder removed."
exit 0
