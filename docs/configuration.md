# Configuration

## CLI Flags

## `backup`

- `--vm <name>` required
- `--keep <n>` retention count, default from `KEEP_DEFAULT`
- `--mode auto|snapshot|archive` default from `BACKUP_MODE`
- `--checksum 0|1` snapshot change detection strictness
- `--backup-dir <path>` override backup target dir
- `--utm-docs-dir <path>` override UTM docs dir
- `--timeout <sec>` VM state wait timeout
- `--poll <sec>` VM state polling interval

## `restore`

- `--vm <name>` required
- `--source <path>` required
- `--yes` skip confirmation prompt
- `--backup-dir <path>` override backup dir
- `--utm-docs-dir <path>` override UTM docs dir
- `--timeout <sec>` VM state wait timeout
- `--poll <sec>` VM state polling interval

## `list-vms`

- `--utm-docs-dir <path>` optional

## `list-backups`

- `--vm <name>` required
- `--backup-dir <path>` optional

## Environment Variables

- `UTM_DOCS_DIR`
- `BACKUP_DIR`
- `KEEP_DEFAULT`
- `BACKUP_MODE` (`auto`, `snapshot`, `archive`)
- `RSYNC_SNAPSHOT_CHECKSUM` (`0` or `1`)
- `UTM_STOP_TIMEOUT_SEC`
- `UTM_STOP_POLL_INTERVAL_SEC`

## Defaults

On macOS:

- `UTM_DOCS_DIR=$HOME/Library/Containers/com.utmapp.UTM/Data/Documents`
- `BACKUP_DIR=/Volumes/BigBadaBoom/Backup/utm`

On Linux:

- `UTM_DOCS_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/UTM/Documents`
- `BACKUP_DIR=$HOME/backups/utm`
