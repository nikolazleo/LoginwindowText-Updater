# 0) Variables — adjust these
USER_NAME="$(whoami)"               # user to install for
API_URL="https://www.affirmations.dev/"    # returns JSON like {"message":"..."}
AUTH_HEADER=""                                # e.g. 'Authorization: Bearer xyz'

# 1) Root helper that sets the lock message
sudo install -d /usr/local/sbin
cat <<'EOF' | sudo tee /usr/local/sbin/set-loginmessage >/dev/null
#!/bin/zsh
set -euo pipefail
# Join all args into one string (spaces preserved)
msg="$*"
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "$msg"
/usr/bin/killall cfprefsd 2>/dev/null || true
# Next lock will show it; no reboot needed.
EOF
sudo chmod 755 /usr/local/sbin/set-loginmessage
sudo chown root:wheel /usr/local/sbin/set-loginmessage

# 2) Sudoers rule (only allow running that exact helper without a password)
echo "${USER_NAME} ALL=(root) NOPASSWD: /usr/local/sbin/set-loginmessage *" | sudo tee /etc/sudoers.d/lockmessage >/dev/null
sudo chmod 440 /etc/sudoers.d/lockmessage

# 3) User script that fetches text & sets it
mkdir -p "/bin"
cat <<EOF > "/usr/local/sbin/update_lock_message.sh"
#!/bin/zsh
set -euo pipefail

API_URL="${API_URL}"
AUTH_HEADER='${AUTH_HEADER}'

# Fetch
if [[ -n "\$AUTH_HEADER" ]]; then
  resp=\$(/usr/bin/curl -fsSL -H "\$AUTH_HEADER" "\$API_URL")
else
  resp=\$(/usr/bin/curl -fsSL "\$API_URL")
fi

# Parse message with jq if present, else use python3, else raw body
if command -v jq >/dev/null 2>&1; then
  msg=\$(printf %s "\$resp" | jq -r '.message // .msg // .text // .value // .affirmation // empty' | head -n1)
else
  msg=\$(/usr/bin/python3 - <<'PY' 2>/dev/null || true
import json,sys
try:
    d=json.load(sys.stdin)
    for k in ("message","msg","text","value", "affirmation"):
        if isinstance(d,dict) and isinstance(d.get(k),str):
            print(d[k]); break
        elif isinstance(d,list) and d and isinstance(d[0],str):
            print(d[0]); break
except Exception: pass
PY
)
fi
[[ -z "\$msg" ]] && msg="\$resp"

# Sanitize and trim (loginwindow renders best with single-line; keep it sane-length)
msg="\${msg//$'\n'/ }"
msg="\${msg//$'\r'/ }"
msg="\${msg:0:500}"

# Set the system message via the root helper
/usr/bin/sudo /usr/local/sbin/set-loginmessage "\$msg"

EOF
chmod +x "/usr/local/sbin/update_lock_message.sh"

# 4) LaunchAgent to run at login
mkdir -p "/Library/LaunchAgents"
cat <<'EOF' > "/Library/LaunchAgents/com.custom.update-lockmessage.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.custom.update-lockmessage</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>/usr/local/sbin/update_lock_message.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <!-- Optional: refresh hourly too -->
  <!-- <key>StartInterval</key><integer>3600</integer> -->
  <key>StandardOutPath</key><string>/Library/Logs/update-lockmessage.out.log</string>
  <key>StandardErrorPath</key><string>/Library/Logs/update-lockmessage.err.log</string>
</dict></plist>
EOF

# 5) Ensure loginwindow text is enabled
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow DisableLoginwindowText -bool false

# 6) Load the LaunchAgent now (and it will run at every future login)
launchctl bootstrap "gui/$(id -u)" "/Library/LaunchAgents/com.custom.update-lockmessage.plist" 2>/dev/null || launchctl load -w "/Library/LaunchAgents/com.custom.update-lockmessage.plist"

# 7) Prime-run once so your next lock shows the new text
"/usr/local/sbin/update_lock_message.sh"

echo "Done. Lock the screen and you should see the updated message."