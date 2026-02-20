# BrewThatMac

Brew-first macOS package workflow with a single source of truth `Brewfile`.

## Commands

Primary dispatcher:

```bash
./brewthatmac.sh <command>
```

Commands:

- `config`: interactive setup for `.env`
- `up`: `brew update/upgrade` + `mas upgrade` + cleanup + doctor
- `dump`: dump installed state to Brewfile + version snapshots
- `drift`: compare installed state vs Brewfile and apply fixes
- `help`: show usage

Direct scripts are also available:

- `./brewup.sh`
- `./brewdump.sh`
- `./brewdrift.sh`

## Setup

1. Copy config template:

```bash
cp ./.env.example ./.env
```

2. Edit `./.env`:

- `MACOS_BACKUP_ROOT`
- `MACOS_BREWFILE_PATH`
- `MACOS_REPORTS_DIR`
- `MACOS_BREWFILE_VERSIONS_DIR`
- retention values

Alternative:

```bash
./brewthatmac.sh config
```

This interactive setup writes `.env`.

First-run behavior:
- Running `brewthatmac up|dump|drift` without `.env` will automatically launch interactive config.

## Recommended Workflow

1. Run `brewthatmac up` for package maintenance.
2. Use `brew install ...` when needed.
3. Run `brewthatmac dump` (or accept prompt if configured) to update Brewfile.
4. Run `brewthatmac drift` when you want to reconcile differences.

## Optional Aliases

```zsh
alias brewthatmac='/path/to/BrewThatMac/brewthatmac.sh'
alias brewup='/path/to/BrewThatMac/brewup.sh'
alias brewdump='/path/to/BrewThatMac/brewdump.sh'
alias brewdrift='/path/to/BrewThatMac/brewdrift.sh'
```

## Notes

- `.env` is not committed.
- `Brewfile` location is configurable via `MACOS_BREWFILE_PATH`.
