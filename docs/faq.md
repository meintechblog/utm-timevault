# FAQ

## Why snapshots and archives both?

- Snapshot mode (`rsync` + hard links) is usually faster and storage efficient for repeated backups.
- Archive mode is a robust fallback when `rsync` is unavailable.

## Does it always stop the VM first?

Yes. Backup and restore attempt VM stop, then poll for `stopped` before file operations.

## Will it start the VM again after backup?

If the VM was running before backup, yes. The tool restores that state and waits for `started`.

## Is Linux supported?

Linux is experimental in this release. macOS is the official support scope.

## Can I run it fully non-interactive?

Yes. Use CLI subcommands (`backup`, `restore`, `list-*`, `doctor`) and not the menu.

## How many backups are kept?

Controlled by `--keep` or `KEEP_DEFAULT`. Rotation applies per VM across snapshot and archive backups.
