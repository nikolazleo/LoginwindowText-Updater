# LoginwindowText Updater

Automate keeping your macOS login window text fresh by pulling content from an HTTP API and updating the lock screen message at each login (and optionally on a schedule). This repo packages the one-off setup script, supporting helper, and LaunchAgent configuration needed to install the workflow on a local machine.

## Why This Exists

- Show rotating affirmations or status messages on the lock screen without manual edits.
- Allow a non-root user to refresh the message safely via a narrowly scoped sudo rule.
- Avoid rebooting by nudging the system preference cache after each update.

## What the Script Installs

Running `steps.sh` performs the following actions:

1. Installs a privileged helper `/usr/local/sbin/set-loginmessage` that writes the system login window text.
2. Adds a sudoers entry granting your user passwordless access to that helper only.
3. Creates `/usr/local/sbin/update_lock_message.sh`, which fetches content from your API, sanitises it, and forwards it to the helper.
4. Registers the LaunchAgent `com.custom.update-lockmessage.plist` so the updater runs when you log in (and you can uncomment an hourly `StartInterval` if desired).
5. Triggers an immediate refresh so the new message appears on your next lock.

All files are installed under `/usr/local/sbin`, `/Library/LaunchAgents`, `/Library/Logs`, and `/etc/sudoers.d`, in keeping with macOS conventions.

## Prerequisites

- macOS with administrative (sudo) access.
- `curl` (preinstalled on macOS), plus either `jq` or the system `python3` for JSON parsing.
- An HTTP API that returns a message in its body or a JSON field such as `message`, `msg`, `text`, `value`, or `affirmation`.

## Quick Start

```bash
git clone <this repo url>
cd lock_message
zsh steps.sh
```

Before running the script, edit the configurable variables at the top of `steps.sh`:

- `USER_NAME`: macOS short username that will run the updater.
- `API_URL`: Endpoint returning the text or JSON payload you want displayed.
- `AUTH_HEADER`: Optional authorization header if the endpoint requires it (example: `Authorization: Bearer sk_xxx`).

The script will prompt for your administrator password the first time so it can install the helper, sudoers rule, and LaunchAgent.

## How the Updater Works

- Fetch: `update_lock_message.sh` uses `curl` (and `AUTH_HEADER` if provided) to retrieve fresh content.
- Parse: Prefers `jq` when available; otherwise falls back to a tiny embedded Python parser; as a last resort uses the raw response body.
- Sanitize: Replaces newlines and carriage returns with spaces and truncates to 500 characters (macOS renders single-line messages best).
- Apply: Calls `sudo set-loginmessage "<message>"`, which updates `LoginwindowText` and flushes the `cfprefsd` cache.

Logs for successful and failed runs are written to `/Library/Logs/update-lockmessage.{out,err}.log` by the LaunchAgent.

## Testing the Setup

After installation you can validate manually:

```bash
/usr/local/sbin/update_lock_message.sh
defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText
```

![alt text](image.png)

Lock your Mac (Ctrl+Cmd+Q) and verify the message shows up. If it does not, check the logs mentioned above.

## Customising the Schedule

To enable hourly refreshes in addition to the login trigger, edit `/Library/LaunchAgents/com.custom.update-lockmessage.plist`, uncomment the `StartInterval` block, and reload:

```bash
sudo /bin/launchctl unload /Library/LaunchAgents/com.custom.update-lockmessage.plist
sudo /bin/launchctl load -w /Library/LaunchAgents/com.custom.update-lockmessage.plist
```

## Maintenance and Troubleshooting

- **Update API credentials**: Edit `/usr/local/sbin/update_lock_message.sh` and rerun `launchctl kickstart gui/$(id -u) com.custom.update-lockmessage`.
- **Missing sudo permissions**: Confirm `/etc/sudoers.d/lockmessage` contains the correct username and helper path.
- **Parser issues**: Install `jq` via Homebrew (`brew install jq`) for more resilient JSON parsing.
- **Reset the message**: `sudo /usr/local/sbin/set-loginmessage ""` clears the lock screen text.

## Uninstalling

```bash
sudo /bin/launchctl unload /Library/LaunchAgents/com.custom.update-lockmessage.plist
sudo rm /Library/LaunchAgents/com.custom.update-lockmessage.plist
sudo rm /usr/local/sbin/update_lock_message.sh
sudo rm /usr/local/sbin/set-loginmessage
sudo rm /etc/sudoers.d/lockmessage
sudo /usr/bin/defaults delete /Library/Preferences/com.apple.loginwindow LoginwindowText
```

Remove the cloned repository directory when finished.

## Security Notes

- The sudoers entry is scoped to `set-loginmessage` with arbitrary arguments, which is sufficient because the helper only writes a plist and restarts `cfprefsd`. Review the script before deployment if you require stricter guarantees.
- macOS Ventura and later may prompt to approve LaunchAgent changes; ensure System Preferences → Privacy & Security allows them.
- Consider pointing `API_URL` to an internal service or static JSON file if you do not control the remote endpoint.
