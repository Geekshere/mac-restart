# macOS Restart Reminder (MDM)

Students get a reminder to restart once their Mac has been on for 7 days. They can postpone 3 times, 4 hours apart. After that, the Mac warns them and restarts after 10 minutes.

## Try the demo (no install, never restarts)
1. Download **Restart-Reminder-Demo.zip** from the [latest release](https://github.com/Geekshere/mac-restart/releases/latest) and unzip it.
2. Double-click **Restart-Reminder-Demo.command**.
   - The first time, macOS may say it "can't be opened" because it's from the internet. Right-click the file → **Open** → **Open**. On newer macOS, go to System Settings → Privacy & Security → **Open Anyway**.
3. Click through the reminders. The whole flow takes about a minute.

Or run it from Terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/Geekshere/mac-restart/main/demo/Restart-Reminder-Demo.command -o /tmp/rr-demo.command && bash /tmp/rr-demo.command
```

## Files
| File | Purpose |
|---|---|
| `install-restart-reminder.sh` | Upload to your MDM and run as root. Safe to re-run to change settings. |
| `uninstall-restart-reminder.sh` | Removes everything. |
| `demo/Restart-Reminder-Demo.command` | Double-click demo. Installs nothing and never restarts. |

## Settings (top of the installer, or Jamf parameters 4–8)
| Setting | Default | Jamf param |
|---|---|---|
| MAX_UPTIME_DAYS | 7 | $4 |
| MAX_DEFERRALS | 3 | $5 |
| PROMPT_INTERVAL_HRS | 4 | $6 |
| FINAL_COUNTDOWN_MIN | 10 | $7 |
| ORG_NAME | School IT | $8 |
| HARD_MAX_UPTIME_DAYS | 14 | – (after this, it no longer skips for Zoom, Teams or Keynote) |
| RESTART_AT_LOGINWINDOW | true | – |

## Deploying
- **Jamf Pro:** Settings → Scripts → add the installer. Create a policy that runs it once per computer, then scope it.
- **Mosyle:** Management → Custom Commands → paste the script and run it as root, once.
- **Kandji:** Library → Custom Script → audit and enforcement script, run once.
- **Intune:** Devices → macOS → Shell scripts → upload. Set "Run script as signed-in user" to **No**.
- **Addigy / others:** run as root, once.

## Testing on one Mac
```bash
sudo sed -i '' 's/^MAX_UPTIME_DAYS=.*/MAX_UPTIME_DAYS=0/; s/^PROMPT_INTERVAL_HRS=.*/PROMPT_INTERVAL_HRS=0/' "/Library/Application Support/RestartReminder/config"
```
```bash
sudo /bin/bash "/Library/Application Support/RestartReminder/restart-reminder.sh"
```
```bash
tail -f /var/log/restart-reminder.log
```
To cancel a scheduled forced restart while testing:
```bash
sudo killall shutdown
```

## Notes
- The deferral count resets on every reboot.
- When a student clicks "Restart Now", the Mac restarts the normal way, so apps can ask to save documents.
- A forced restart uses `shutdown -r`. It still waits out the countdown, so students can save their work first.
- Dialogs use the built-in `osascript`, so nothing extra needs to be installed. No PPPC profile is needed.
