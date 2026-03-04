# Backup and Restore

## Backup Workflow

When you run `backup`, UTM TimeVault:

1. Reads the current VM state.
2. Requests graceful shutdown (`stop ... by request`).
3. Polls until status is `stopped`.
4. If graceful shutdown times out, escalates to force stop (`stop ... by force`) and polls again.
5. Creates snapshot or archive backup.
6. Applies rotation (`--keep`).
7. Starts VM again if it was running before.
8. Polls until status is `started`.

## Backup Examples

Automatic mode:

```bash
utm-timevault backup --vm "Hulki" --keep 14
```

Force snapshot mode:

```bash
utm-timevault backup --vm "Hulki" --mode snapshot --checksum 1
```

Force archive mode:

```bash
utm-timevault backup --vm "Hulki" --mode archive
```

Custom dirs:

```bash
utm-timevault backup --vm "Hulki" --backup-dir "/Volumes/Backup/utm" --utm-docs-dir "$HOME/Library/Containers/com.utmapp.UTM/Data/Documents"
```

## Restore Workflow

When you run `restore`, UTM TimeVault:

1. Requests graceful VM shutdown (`request`), with force fallback on timeout.
2. Polls until status is `stopped`.
3. Renames existing VM folder to `.old_<timestamp>`.
4. Restores from snapshot or archive source.

## Restore Examples

List backups:

```bash
utm-timevault list-backups --vm "Hulki"
```

Restore from snapshot:

```bash
utm-timevault restore --vm "Hulki" --source "/Volumes/Backup/utm/Hulki.utm_2026-03-04_02-00-00.snapshot" --yes
```

Restore from archive:

```bash
utm-timevault restore --vm "Hulki" --source "/Volumes/Backup/utm/Hulki.utm_2026-03-04_02-00-00.tar.zst" --yes
```

## Interactive Mode

```bash
utm-timevault menu
```
