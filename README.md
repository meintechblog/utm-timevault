# UTM TimeVault

State-aware backup and restore tool for UTM virtual machines.

UTM TimeVault stops your VM before backup, waits until it is really stopped, runs backup/rotation, and starts the VM again if it was running before.

## Features

- Interactive menu for beginners
- Scriptable CLI for cron and automation
- Snapshot backups with `rsync` hard-link deduplication
- Archive backups (`.tar.zst` or `.tar.gz`) fallback
- Global retention per VM
- VM state restore after backup (if previously running)

## Support Scope

- Official: macOS + UTM
- Experimental: Linux

## Quick Start (2 minutes)

### Option A: Installer (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/meintechblog/utm-timevault/main/scripts/install.sh | bash
```

Then run:

```bash
utm-timevault doctor
```

### Option B: Manual install

```bash
git clone https://github.com/meintechblog/utm-timevault.git
cd utm-timevault
chmod +x scripts/utm-timevault.sh
sudo cp scripts/utm-timevault.sh /usr/local/bin/utm-timevault
```

## First Backup

```bash
utm-timevault backup --vm "MyVM" --keep 14
```

## First Restore

```bash
utm-timevault list-backups --vm "MyVM"
utm-timevault restore --vm "MyVM" --source "/path/to/MyVM.utm_2026-03-04_02-00-00.snapshot" --yes
```

## Commands

```bash
utm-timevault menu
utm-timevault backup --vm <name> [--keep <n>] [--mode auto|snapshot|archive] [--checksum 0|1] [--backup-dir <path>] [--utm-docs-dir <path>] [--timeout <sec>] [--poll <sec>]
utm-timevault restore --vm <name> --source <path> [--yes] [--backup-dir <path>] [--utm-docs-dir <path>] [--timeout <sec>] [--poll <sec>]
utm-timevault list-vms [--utm-docs-dir <path>]
utm-timevault list-backups --vm <name> [--backup-dir <path>]
utm-timevault doctor
utm-timevault version
```

## Safety Model

1. VM stop requested before backup/restore.
2. Status polling blocks until VM is really `stopped`.
3. On backup completion, VM is started again if it was running before.
4. Start polling confirms `started`.
5. Exit trap attempts VM state restoration even if backup fails.

## Documentation

- [Quickstart](docs/quickstart.md)
- [Configuration](docs/configuration.md)
- [Backup and Restore](docs/backup-and-restore.md)
- [Automation (cron)](docs/automation-cron.md)
- [Troubleshooting](docs/troubleshooting.md)
- [FAQ](docs/faq.md)

## License

MIT. See [LICENSE](LICENSE).
