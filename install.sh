#!/bin/bash
set -e
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "╔══════════════════════════════════════╗"
echo "║     Obsidian Backup Installer        ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ─── Vault path ─────────────────────────────────────────────────────────────
read -rp "Obsidian vault path [$HOME/Obsidian]: " VAULT
VAULT="${VAULT:-$HOME/Obsidian}"
VAULT="${VAULT/#\~/$HOME}"
[ -d "$VAULT" ] || { echo "Error: directory not found: $VAULT"; exit 1; }

# ─── Google Drive (optional) ─────────────────────────────────────────────────
read -rp "Google Drive folder path (leave blank to skip): " DRIVE
DRIVE="${DRIVE/#\~/$HOME}"

# ─── SSH key ─────────────────────────────────────────────────────────────────
read -rp "Deploy key path [$HOME/.ssh/obsidian_backup_deploy]: " SSH_KEY
SSH_KEY="${SSH_KEY:-$HOME/.ssh/obsidian_backup_deploy}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"

# ─── Schedule ────────────────────────────────────────────────────────────────
read -rp "Daily run time, 24h HH:MM [03:00]: " RUN_TIME
RUN_TIME="${RUN_TIME:-03:00}"
HOUR="${RUN_TIME%%:*}"
MINUTE="${RUN_TIME##*:}"

echo ""

# ─── Install script ──────────────────────────────────────────────────────────
echo "→ Installing backup script..."
mkdir -p "$HOME/.local/bin"
SCRIPT_DEST="$HOME/.local/bin/obsidian-backup.sh"

sed \
    -e "s|__VAULT__|$VAULT|g" \
    -e "s|__DRIVE__|$DRIVE|g" \
    -e "s|__SSH_KEY__|$SSH_KEY|g" \
    -e "s|__HOUR__|$HOUR|g" \
    -e "s|__MINUTE__|$MINUTE|g" \
    "$REPO_DIR/obsidian-backup.sh" > "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

# ─── Deploy key (no ssh-agent / Keychain involved) ───────────────────────────
if [ -f "$SSH_KEY" ]; then
    echo "→ Using existing deploy key: $SSH_KEY"
else
    echo "→ Creating deploy key..."
    mkdir -p "$(dirname "$SSH_KEY")"
    ssh-keygen -t ed25519 -N "" -C "obsidian-backup deploy key ($(hostname -s))" -f "$SSH_KEY" > /dev/null
    chmod 600 "$SSH_KEY"

    REPO_SLUG=$(git -C "$VAULT" remote get-url origin 2>/dev/null \
        | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
    if command -v gh > /dev/null && [ -n "$REPO_SLUG" ] \
        && gh repo deploy-key add "$SSH_KEY.pub" --repo "$REPO_SLUG" \
            --title "obsidian-backup launchd ($(hostname -s))" --allow-write; then
        echo "  registered as write-enabled deploy key on $REPO_SLUG"
    else
        echo ""
        echo "  ACTION REQUIRED: add this public key under the repo's"
        echo "  Settings → Deploy keys, with 'Allow write access' ticked:"
        echo ""
        cat "$SSH_KEY.pub"
        echo ""
    fi
fi

# ─── Install LaunchAgent ─────────────────────────────────────────────────────
echo "→ Installing LaunchAgent..."
USERNAME=$(whoami)
LABEL="com.$USERNAME.obsidian-backup"
PLIST_DEST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_PATH="$HOME/Library/Logs/obsidian-backup.log"

sed \
    -e "s|__LABEL__|$LABEL|g" \
    -e "s|__SCRIPT__|$SCRIPT_DEST|g" \
    -e "s|__HOUR__|$HOUR|g" \
    -e "s|__MINUTE__|$MINUTE|g" \
    -e "s|__LOG__|$LOG_PATH|g" \
    "$REPO_DIR/com.example.obsidian-backup.plist" > "$PLIST_DEST"

launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"

# ─── Full Disk Access reminder ───────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ACTION REQUIRED — Full Disk Access for Google Drive sync       ║"
echo "║                                                                  ║"
echo "║  System Settings → Privacy & Security → Full Disk Access        ║"
echo "║  Add: /bin/bash                                                  ║"
echo "║                                                                  ║"
echo "║  Skip this step if you are not syncing to Google Drive.         ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "✓ Installation complete"
echo ""
echo "  Script:      $SCRIPT_DEST"
echo "  LaunchAgent: $PLIST_DEST"
echo "  Log:         $LOG_PATH"
echo ""
echo "  Run manually:"
echo "  bash $SCRIPT_DEST --force"
