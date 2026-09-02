#!/bin/bash
# ─── Configuration (set by install.sh, or edit manually) ────────────────────
VAULT="__VAULT__"
DRIVE="__DRIVE__"       # leave empty to skip Google Drive sync
SSH_KEY="__SSH_KEY__"
# ────────────────────────────────────────────────────────────────────────────

LOG_DATE=$(date '+%Y-%m-%d %H:%M')
ERRORS=()

notify() {
    osascript -e "display notification \"$2\" with title \"Obsidian Backup\" subtitle \"$1\"" 2>/dev/null
}

echo "--- backup started $LOG_DATE ---"

# Start a fresh ssh-agent and load key from macOS Keychain
eval "$(ssh-agent -s)" > /dev/null
/usr/bin/ssh-add --apple-load-keychain 2>/dev/null
ssh-add -l > /dev/null 2>&1 || ERRORS+=("ssh-add: no identity loaded from keychain")

cd "$VAULT" || { echo "error: vault not found at $VAULT"; notify "✗ Failed" "Vault not found"; exit 1; }

# Git backup
git add -A
if ! git diff --cached --quiet; then
    git commit -m "auto backup $LOG_DATE" || ERRORS+=("git commit failed")
fi

# Push whatever's outstanding, whether or not this run made a new commit
# above — catches a backlog left by a prior run whose push failed (issue #1).
if ! git rev-parse --abbrev-ref --symbolic-full-name @{u} > /dev/null 2>&1; then
    # No upstream tracking branch yet (first run against a fresh clone).
    git push -u origin "$(git branch --show-current)" || ERRORS+=("git push failed (no upstream)")
elif [ "$(git rev-list --count @{u}..HEAD)" -gt 0 ]; then
    git push || ERRORS+=("git push failed")
fi

# Google Drive sync (skipped if DRIVE is empty)
if [ -n "$DRIVE" ]; then
    rsync -a --delete --exclude='.git/' "$VAULT/" "$DRIVE/" \
        || ERRORS+=("rsync to Drive failed")
fi

# Result
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "backup ok"
    notify "✓ Success" "Vault backed up"
else
    echo "backup failed: ${ERRORS[*]}"
    notify "✗ Failed" "${ERRORS[*]}"
fi

kill "$SSH_AGENT_PID" 2>/dev/null
