# zimbra-mailbox-restore

Bash script to restore Zimbra mailbox messages (`.msg` files) from a remote backup via `rsync`, automatically resolving each user's `mailboxId` and re-adding the messages to their Inbox using `zmmailbox`.

## How it works

For every user listed in `users.txt`, the script:

1. **Get mailbox ID** — runs `zmprov gmi <user>` to resolve the account's `mailboxId`.
2. **Resolve msg folder paths** — builds the local and remote store paths using that `mailboxId` (e.g. `store/0/<mailboxId>/msg`).
3. **Rsync from backup** — syncs `.msg` files from the remote backup host into the local Zimbra store, and captures the list of transferred files from the rsync output.
4. **Add messages** — for each transferred `.msg` file, runs `zmmailbox -z -m <user> addMessage /Inbox <file>` to inject it into the user's Inbox.

Each user gets its own log file, so you can review results per account without digging through one giant log.

## Requirements

- Zimbra server (tested on Ubuntu 20.04) with `zmprov` and `zmmailbox` available.
- SSH access (key-based recommended) from the Zimbra host to the remote backup host.
- Must be run as the `zimbra` user (or with equivalent permissions).
- `bash` (the script uses bash-specific syntax such as `<<<` here-strings).

## Setup

1. Clone this repository onto your Zimbra server.
2. Create a `users.txt` file in the same directory, one email address per line:

   ```
   rio.prayoga@example.com
   admin@example.com
   ```

3. Edit the configuration block at the top of `zimbra-msg-restore.sh`:

   ```bash
   USERS_FILE="./users.txt"
   STORE_ROOT="/opt/zimbra/store/0"
   REMOTE_HOST="root@1.2.3.4"
   REMOTE_STORE_ROOT="/mnt/recover-vm100/zimbra/store/0"
   TARGET_FOLDER="/Inbox"
   LOG_DIR="./logs"
   RSYNC_FLAGS="-avH"
   ```

   | Variable | Description |
   |---|---|
   | `USERS_FILE` | Path to the list of user emails to process |
   | `STORE_ROOT` | Local Zimbra store root path |
   | `REMOTE_HOST` | SSH target of the backup source (`user@host`) |
   | `REMOTE_STORE_ROOT` | Remote store root path on the backup host |
   | `TARGET_FOLDER` | Mailbox folder messages are added to (default `/Inbox`) |
   | `LOG_DIR` | Directory where per-user log files are written |
   | `RSYNC_FLAGS` | Flags passed to `rsync`. Include `-avH` for a real run |

4. Make the script executable:

   ```bash
   chmod +x zimbra-msg-restore.sh
   ```

## Usage

Run as the `zimbra` user:

```bash
su - zimbra
./zimbra-msg-restore.sh
```

or:

```bash
bash zimbra-msg-restore.sh
```

> ⚠️ Always run with `bash`, not `sh` — the script relies on bash-only features and will fail under `dash` (Ubuntu's default `/bin/sh`).

## Dry-run mode

To preview what would happen without actually copying files or adding messages, add `n` to `RSYNC_FLAGS` to enable rsync's dry-run mode:

```bash
RSYNC_FLAGS="-avHn"
```

When dry-run is detected, the script:
- Still connects and lists what rsync *would* transfer.
- Skips the actual file copy.
- Skips running `addMessage`, only logging which files *would* be added.

Remove the `n` (back to `-avH`) to perform the real restore.

## Logs

Each run creates one log file per user under `./logs/`, named:

```
logs/<sanitized_email>_<run_timestamp>.log
```

For example:

```
logs/denny.c_example.com_20260908_143012.log
```

Each log contains:
- The resolved `mailboxId`
- Local/remote msg folder paths
- Full rsync output
- Result of every `addMessage` call (success/error)
- A summary count of messages processed

## Notes / Caveats

- The script uses `--ignore-existing` in rsync, so files already present locally are not re-transferred or re-added, avoiding duplicate messages on repeated runs.
- If a user's `mailboxId` can't be resolved, or no new `.msg` files are found, that user is skipped and logged accordingly.
- Make sure SSH access to `REMOTE_HOST` is passwordless (SSH key) if you plan to run this unattended.

## License

MIT (or update to match your organization's policy).
