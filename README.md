# BrewThatMac

Brew-first macOS package workflow with a single source of truth `Brewfile`.

## Commands

Primary dispatcher:

```bash
./scripts/brewthatmac.sh <command>
```

Commands:

- `config`: interactive setup for `scripts/.env`
- `up`: `brew update/upgrade` + `mas upgrade` + cleanup + doctor
- `dump`: dump installed state to Brewfile + version snapshots
- `drift`: compare installed state vs Brewfile and apply fixes
- `help`: show usage

Direct scripts are also available:

- `./scripts/brewup.sh`
- `./scripts/brewdump.sh`
- `./scripts/brewdrift.sh`

## Setup

1. Copy config template:

```bash
cp ./scripts/.env.example ./scripts/.env
```

2. Edit `./scripts/.env`:

- `MACOS_BACKUP_ROOT`
- `MACOS_BREWFILE_PATH`
- `MACOS_REPORTS_DIR`
- `MACOS_BREWFILE_VERSIONS_DIR`
- retention values

Alternative:

```bash
./scripts/brewthatmac.sh config
```

This interactive setup writes `scripts/.env`.

First-run behavior:
- Running `brewthatmac up|dump|drift` without `scripts/.env` will automatically launch interactive config.

## Recommended Workflow

1. Run `brewthatmac up` for package maintenance.
2. Use `brew install ...` when needed.
3. Run `brewthatmac dump` (or accept prompt if configured) to update Brewfile.
4. Run `brewthatmac drift` when you want to reconcile differences.

## Optional Aliases

```zsh
alias brewthatmac='/path/to/BrewThatMac/scripts/brewthatmac.sh'
alias brewup='/path/to/BrewThatMac/scripts/brewup.sh'
alias brewdump='/path/to/BrewThatMac/scripts/brewdump.sh'
alias brewdrift='/path/to/BrewThatMac/scripts/brewdrift.sh'
```

## Notes

- `.env` is not committed.
- `Brewfile` location is configurable via `MACOS_BREWFILE_PATH`.
