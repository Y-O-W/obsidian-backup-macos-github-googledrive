# obsidian-backup-macos-github-googledrive

Automated daily backup of an [Obsidian](https://obsidian.md) vault to **GitHub** and **Google Drive** on macOS, using a shell script scheduled via launchd.

- Commits and pushes new/changed notes to a private GitHub repo
- Mirrors the vault to a local Google Drive folder (synced to the cloud by Google Drive for Desktop)
- Sends a macOS notification on success or failure
- Runs at a scheduled time daily, and also at login to catch missed runs when the laptop was closed

---

## Prerequisites

- macOS (tested on Ventura and later)
- Git installed (`xcode-select --install` if missing)
- Obsidian vault already initialised as a git repo with a GitHub remote
- Google Drive for Desktop installed (optional — skip if you only want GitHub backup)
- SSH key added to your GitHub account

---

## Quick install

```bash
git clone https://github.com/Y-O-W/obsidian-backup-macos-github-googledrive.git
cd obsidian-backup-macos-github-googledrive
bash install.sh
```

The installer will ask for:

| Prompt | Example |
|--------|---------|
| Obsidian vault path | `~/Documents/MyVault` |
| Google Drive folder path | `~/Library/CloudStorage/GoogleDrive-you@gmail.com/My Drive/obsidian` |
| SSH key path | `~/.ssh/id_ed25519` |
| Daily run time | `09:00` |

It then installs the script, configures the SSH keychain, and loads the LaunchAgent.

---

## Manual setup

### 1. Copy and configure the backup script

```bash
mkdir -p ~/.local/bin
cp obsidian-backup.sh ~/.local/bin/obsidian-backup.sh
chmod +x ~/.local/bin/obsidian-backup.sh
```

Open `~/.local/bin/obsidian-backup.sh` and set the three variables at the top:

```bash
VAULT="$HOME/Obsidian"          # path to your vault
DRIVE=""                         # path to local Google Drive folder, or leave empty
SSH_KEY="$HOME/.ssh/id_ed25519" # path to your SSH key
```

### 2. Store your SSH key in the macOS Keychain

This lets the script authenticate to GitHub without a running terminal session:

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

Add to `~/.ssh/config` (create if it doesn't exist):

```
Host *
  UseKeychain yes
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519
```

### 3. Install the LaunchAgent

Copy the plist template and replace placeholders:

```bash
cp com.example.obsidian-backup.plist \
   ~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist
```

Edit the copy and replace:
- `__LABEL__` → `com.yourusername.obsidian-backup`
- `__SCRIPT__` → `/Users/yourusername/.local/bin/obsidian-backup.sh`
- `__HOUR__` / `__MINUTE__` → your preferred run time (e.g. `9` / `0`)
- `__LOG__` → `/Users/yourusername/Library/Logs/obsidian-backup.log`

Load it:

```bash
launchctl load ~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist
```

### 4. Grant Full Disk Access (Google Drive sync only)

macOS blocks background processes from accessing `~/Library/CloudStorage`. To fix this:

> **System Settings → Privacy & Security → Full Disk Access → add `/bin/bash`**

---

## Running manually

```bash
bash ~/.local/bin/obsidian-backup.sh
```

---

## Log

```bash
tail -f ~/Library/Logs/obsidian-backup.log
```

Each run appends a timestamped entry:

```
--- backup started 2026-07-04 09:00 ---
backup ok
```

or on failure:

```
--- backup started 2026-07-04 09:00 ---
backup failed: git push failed
```

---

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist
rm ~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist
rm ~/.local/bin/obsidian-backup.sh
```
