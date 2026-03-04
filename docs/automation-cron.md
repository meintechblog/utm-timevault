# Automation with cron

Use CLI subcommands for non-interactive automation.

## Example: Daily backup at 02:00

```cron
0 2 * * * /usr/local/bin/utm-timevault backup --vm "Hulki" --keep 14 --mode auto >> "$HOME/Library/Logs/utm-timevault.log" 2>&1
```

## Example: Weekly archive-only backup

```cron
0 3 * * 0 /usr/local/bin/utm-timevault backup --vm "Hulki" --keep 8 --mode archive >> "$HOME/Library/Logs/utm-timevault.log" 2>&1
```

## Recommended cron practices

- Use absolute paths.
- Redirect stdout/stderr to log files.
- Add `--yes` for restore jobs to avoid prompts.
- Run `utm-timevault doctor` manually after system updates.
