# Troubleshooting

## Exit Codes

- `0` success
- `1` runtime failure
- `2` invalid arguments
- `3` missing required dependencies
- `4` VM state timeout

## "Missing required tools"

Run:

```bash
utm-timevault doctor
```

Install what is missing (`rsync`, `zstd`, `pv` are commonly needed).

## Timeout waiting for VM stop/start

If you get exit code `4`:

1. Check UTM app state.
2. Increase timeout, for example:

```bash
utm-timevault backup --vm "Hulki" --timeout 300 --poll 3
```

3. Verify VM name exactly matches UTM.

## Restore fails with `.tar.zst`

Install `zstd`:

```bash
brew install zstd
```

## "Directory not found"

Override paths explicitly:

```bash
utm-timevault backup --vm "Hulki" --utm-docs-dir "$HOME/Library/Containers/com.utmapp.UTM/Data/Documents" --backup-dir "/Volumes/Backup/utm"
```

## SMB/NAS target without hard-link support

If the target filesystem does not support hard links, snapshot deduplication cannot work.

Default behavior:

- `HARDLINK_AUTO_FALLBACK=1` switches from `snapshot` to `archive` mode automatically.

Alternative behavior:

- Set `HARDLINK_AUTO_FALLBACK=0` to keep snapshot mode and only warn (expect full-copy-like growth).

## Cron job works manually but fails in cron

Cron has a minimal PATH. Use absolute binary paths and explicit directories.
