# Quickstart

## 1. Prerequisites

- macOS with UTM installed
- Bash, tar, awk, du, date
- At least one backup method: `rsync` or `gzip` or `zstd`

## 2. Install

### Installer

```bash
curl -fsSL https://raw.githubusercontent.com/meintechblog/utm-timevault/main/scripts/install.sh | bash
```

### Manual

```bash
git clone https://github.com/meintechblog/utm-timevault.git
cd utm-timevault
chmod +x scripts/utm-timevault.sh
sudo cp scripts/utm-timevault.sh /usr/local/bin/utm-timevault
```

## 3. Validate setup

```bash
utm-timevault doctor
```

## 4. Discover your VMs

```bash
utm-timevault list-vms
```

## 5. Run first backup

```bash
utm-timevault backup --vm "MyVM" --keep 14
```

## 6. Restore a backup

```bash
utm-timevault list-backups --vm "MyVM"
utm-timevault restore --vm "MyVM" --source "/path/to/backup" --yes
```

## 7. Interactive mode

If you prefer guided usage:

```bash
utm-timevault
```
