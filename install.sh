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
read -rp "SSH key path [$HOME/.ssh/id_ed25519]: " SSH_KEY
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_KEY="${SSH_KEY/#\~/$HOME}"
[ -f "$SSH_KEY" ] || { echo "Error: SSH key not found: $SSH_KEY"; exit 1; }

# ─── Schedule ────────────────────────────────────────────────────────────────
read -rp "Daily run time, 24h HH:MM [09:00]: " RUN_TIME
RUN_TIME="${RUN_TIME:-09:00}"
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
    "$REPO_DIR/obsidian-backup.sh" > "$SCRIPT_DEST"
chmod +x "$SCRIPT_DEST"

# ─── Ensure SSH key is in macOS Keychain ─────────────────────────────────────
echo "→ Adding SSH key to macOS Keychain..."
/usr/bin/ssh-add --apple-use-keychain "$SSH_KEY" 2>/dev/null || true

# Ensure UseKeychain is set in ~/.ssh/config
if ! grep -q "UseKeychain yes" "$HOME/.ssh/config" 2>/dev/null; then
    mkdir -p "$HOME/.ssh"
    printf "\nHost *\n  UseKeychain yes\n  AddKeysToAgent yes\n  IdentityFile %s\n" "$SSH_KEY" >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
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
echo "  bash $SCRIPT_DEST"
