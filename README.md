# obsidian-backup-macos-github-googledrive

Automatic backup of an [Obsidian](https://obsidian.md) vault on macOS, run by a launchd agent:

- **GitHub** – commits and pushes changes to a private repo
- **Google Drive** – mirrors the vault into a local Drive folder (optional)
- **Notifications** – a macOS notification on success or failure

It runs daily at a time you choose, at login, and hourly. A run that fails (offline, asleep, …) is retried within the hour, and every run pushes any commits still outstanding.

## How it works

`obsidian-backup.sh` runs `git add` → `commit` → `push`, then `rsync`s the vault to Drive. It authenticates to GitHub with a **dedicated deploy key**: a passphrase-less key scoped to the vault repo only. No ssh-agent or Keychain is involved, which keeps unattended runs working (see [Troubleshooting](#troubleshooting)).

## Requirements

- macOS Ventura or later
- Git (`xcode-select --install` if missing)
- A vault that is already a git repo with a GitHub remote
- [GitHub CLI](https://cli.github.com), authenticated, to register the deploy key automatically (otherwise add it by hand)
- Google Drive for Desktop (optional)

## Install

```bash
git clone https://github.com/Y-O-W/obsidian-backup-macos-github-googledrive.git
cd obsidian-backup-macos-github-googledrive
bash install.sh
```

The installer asks for:

| Prompt | Example |
|--------|---------|
| Vault path | `~/Documents/MyVault` |
| Google Drive folder (blank to skip) | `~/Library/CloudStorage/GoogleDrive-you@gmail.com/My Drive/obsidian` |
| Deploy key path | `~/.ssh/obsidian_backup_deploy` (created if missing) |
| Daily run time | `09:00` |

It then installs the script to `~/.local/bin`, creates and registers the deploy key (or prints the public key to add manually), and loads the LaunchAgent.

**Google Drive only:** macOS blocks background processes from `~/Library/CloudStorage`. Grant access under *System Settings → Privacy & Security → Full Disk Access → add `/bin/bash`*.

## Manual setup

Skip this if you used the installer.

1. **Script** – copy it and set the variables at the top:

   ```bash
   mkdir -p ~/.local/bin
   cp obsidian-backup.sh ~/.local/bin/ && chmod +x ~/.local/bin/obsidian-backup.sh
   ```

   ```bash
   VAULT="$HOME/Obsidian"                      # path to your vault
   DRIVE=""                                    # local Google Drive folder, or empty to skip
   SSH_KEY="$HOME/.ssh/obsidian_backup_deploy" # deploy key from step 2
   ```

2. **Deploy key** – create it and register it with write access:

   ```bash
   ssh-keygen -t ed25519 -N "" -C "obsidian-backup deploy key" -f ~/.ssh/obsidian_backup_deploy
   gh repo deploy-key add ~/.ssh/obsidian_backup_deploy.pub \
      --repo YOUR_USER/YOUR_VAULT_REPO --title "obsidian-backup launchd" --allow-write
   ```

   Without `gh`: paste the `.pub` contents into the repo's *Settings → Deploy keys* and tick *Allow write access*.

3. **LaunchAgent** – copy `com.example.obsidian-backup.plist` to `~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist`, replace the placeholders, then load it:

   | Placeholder | Value |
   |-------------|-------|
   | `__LABEL__` | `com.yourusername.obsidian-backup` |
   | `__SCRIPT__` | `/Users/yourusername/.local/bin/obsidian-backup.sh` |
   | `__HOUR__` / `__MINUTE__` | run time, e.g. `9` / `0` |
   | `__LOG__` | `/Users/yourusername/Library/Logs/obsidian-backup.log` |

   ```bash
   launchctl load ~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist
   ```

## Usage

Run a backup now:

```bash
bash ~/.local/bin/obsidian-backup.sh
```

Follow the log (`~/Library/Logs/obsidian-backup.log`):

```bash
tail -f ~/Library/Logs/obsidian-backup.log
```

```
--- backup started 2026-07-04 09:00 ---
backup ok
```

A failure ends with `backup failed: <reasons>` instead, e.g. `git push failed`.

## Troubleshooting

### `Permission denied (publickey)` or `deploy key not readable`

Check that the key exists, is registered, and can write (`read_only` must be `false`):

```bash
ls -l ~/.ssh/obsidian_backup_deploy
gh api repos/YOUR_USER/YOUR_VAULT_REPO/keys --jq '.[] | {title, read_only}'
GIT_SSH_COMMAND="ssh -i ~/.ssh/obsidian_backup_deploy -o IdentitiesOnly=yes -o IdentityAgent=none" \
  git -C ~/Obsidian ls-remote origin HEAD
```

### `ssh-add: no identity loaded from keychain` (older versions)

Early versions loaded your personal SSH key from the Keychain with `ssh-add --apple-load-keychain`. This broke repeatedly on unattended runs (issues [#1](../../issues/1), [#2](../../issues/2)):

- After a macOS update, the Keychain's "always allow" grant for `ssh-add` is revoked, because it is tied to the binary's code signature. A background LaunchAgent has no GUI session to re-approve it, so `ssh-add` fails silently on every run.
- The Keychain can also be unreachable for minutes after a scheduled or dark wake, so retrying doesn't help.

The deploy key avoids both. If you still see this message, you are running an old copy of the script: re-run `install.sh`.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist
rm ~/Library/LaunchAgents/com.$(whoami).obsidian-backup.plist ~/.local/bin/obsidian-backup.sh
```

Optionally remove the deploy key from the repo's *Settings → Deploy keys* and delete `~/.ssh/obsidian_backup_deploy*`.
