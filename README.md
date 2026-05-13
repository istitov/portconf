# portconf

**Gentoo `/etc/portage` configuration cleaner and manager.**

Originally written by [megabaks](https://github.com/megabaks/portconf) (2012–2014).
Currently maintained by [istitov](https://github.com/istitov/portconf) as part
of the [bash-revival](https://github.com/istitov/bash-revival) project.

> Install from the `::stuff` overlay only — see [INSTALL](INSTALL).

---

## What it does

### USE flags
- Sort, remove duplicates, preserve last defined state (on/off)
- Remove flags that are invalid or already set globally in `make.conf` / profile
- Check flags across **all available versions** of a package

### Keywords
- Sort and deduplicate, preserving the last-defined state per token (`--keyword-uniq`)
- Keep only the single latest-defined keyword per atom, discarding earlier ones (`--keyword-one`)

### Atoms
- Find and remove incorrect, not-found, or not-installed atoms
  (including in `/etc/portage/env`)

### Backups
- Auto-backup `/etc/portage` (+ `make.conf`, `world`) before any change
- Configurable retention count (default: 10)
- Restore to any saved state

### Converting
- Convert `package.*` between flat files and per-package directory layout

### Overlays
- Remove unused repos and stale dependency cache entries
- Detect and offer to remove broken symlinks in overlay repos

### World
- Regenerate the world file (with auto-backup)

---

## Quick start

```sh
# Check only (no changes):
portconf --pretend --full

# Full cleanup with eix cache refresh (recommended):
portconf --regen-cache --full
```

---

## Options

See `portconf --help` or `man portconf` for the full option list.

---

## Configuration

Edit `/etc/portconf.conf`:

```sh
# Number of backups to keep (default: 10)
# COUNT=""

# Skip these categories (shell glob patterns)
# IGNORE_CATEGORY="cross-.*"

# Skip these package names
# IGNORE_PN=""

# Default options prepended to every run
PORTCONF_DEFAULT_OPTS="-rc"
```

---

## License

GNU General Public License v3 or later.
Original copyright megabaks; maintained fork copyright 2026 Ivan S. Titov.
