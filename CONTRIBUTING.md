# Contributing

Thanks for helping improve UTM TimeVault.

## Development Setup

1. Fork the repository.
2. Create a feature branch.
3. Make focused changes.
4. Run checks:

```bash
bash -n scripts/utm-timevault.sh
bash -n scripts/install.sh
shellcheck scripts/utm-timevault.sh scripts/install.sh
```

5. Open a pull request with clear description and test notes.

## Contribution Guidelines

- Keep shell code compatible with macOS Bash where possible.
- Prefer small, reviewable commits.
- Update docs when behavior changes.
- Keep user-facing CLI contracts stable.

## Reporting Bugs

Use the issue template and include:

- Command used
- Expected behavior
- Actual behavior
- Exit code
- Platform (`macOS`/`Linux`)
