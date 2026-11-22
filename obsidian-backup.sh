#!/bin/bash
# ─── Configuration (set by install.sh, or edit manually) ────────────────────
VAULT="__VAULT__"
DRIVE="__DRIVE__"       # leave empty to skip Google Drive sync
SSH_KEY="__SSH_KEY__"
RUN_HOUR="__HOUR__"     # daily run time; defines the start of each backup "cycle"
RUN_MINUTE="__MINUTE__"
# ────────────────────────────────────────────────────────────────────────────

LOG_DATE=$(date '+%Y-%m-%d %H:%M')
ERRORS=()

# launchd runs this with a bare PATH, which resolves `git` to Apple's CLT
# stub — it refuses to run until the Xcode license is re-accepted, which
# happens silently after Xcode/CLT updates. Prefer Homebrew's git, which
# isn't gated by that license, so a background run can't break this way.
for p in /opt/homebrew/bin /usr/local/bin; do
    [ -d "$p" ] && PATH="$p:$PATH"
done
export PATH

notify() {
    osascript -e "display notification \"$2\" with title \"Obsidian Backup\" subtitle \"$1\"" 2>/dev/null
}

# Once a run succeeds, stay quiet until the next scheduled run. launchd also
# fires hourly and at login as a retry net (issue #2); those extra triggers
# exit here when this cycle (= since the most recent daily run time) already
# has a successful backup. Pass --force to run regardless.
STATE_DIR="$HOME/.local/state/obsidian-backup"
STAMP="$STATE_DIR/last-success"
now=$(date +%s)
cycle_start=$(date -j -f '%Y-%m-%d %H:%M:%S' "$(date +%Y-%m-%d) $RUN_HOUR:$RUN_MINUTE:00" +%s 2>/dev/null)
if [ -n "$cycle_start" ]; then
    [ "$now" -lt "$cycle_start" ] && cycle_start=$((cycle_start - 86400))
    last_ok=$(cat "$STAMP" 2>/dev/null)
    if [ "$1" != "--force" ] && [ "${last_ok:-0}" -ge "$cycle_start" ] 2>/dev/null; then
        echo "--- $LOG_DATE: already backed up this cycle, skipping ---"
        exit 0
    fi
fi

echo "--- backup started $LOG_DATE ---"

# Authenticate with a dedicated, passphrase-less deploy key (issue #2).
# The previous approach (ssh-agent + `ssh-add --apple-load-keychain`) failed
# on unattended launchd runs: the login keychain was unreachable for minutes
# after a scheduled/dark wake, so no identity could be loaded. A deploy key
# needs no agent and no keychain. IdentityAgent=none + IdentitiesOnly make
# sure only this key is offered, never a stale agent or keychain identity.
if [ -r "$SSH_KEY" ]; then
    export GIT_SSH_COMMAND="ssh -i \"$SSH_KEY\" -o IdentitiesOnly=yes -o IdentityAgent=none -o BatchMode=yes"
else
    ERRORS+=("deploy key not readable at $SSH_KEY")
fi

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
RESULT_CODE=0
if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "backup ok"
    mkdir -p "$STATE_DIR" && echo "$now" > "$STAMP"
    notify "✓ Success" "Vault backed up"
else
    echo "backup failed: ${ERRORS[*]}"
    notify "✗ Failed" "${ERRORS[*]}"
    RESULT_CODE=1
fi

exit $RESULT_CODE
