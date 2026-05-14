# portconf

[![CI](https://github.com/istitov/portconf/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/istitov/portconf/actions/workflows/ci.yml)

**Gentoo `/etc/portage` configuration cleaner and manager.**

Originally written by [megabaks](https://github.com/megabaks/portconf) (2012–2014).
Currently maintained by [istitov](https://github.com/istitov/portconf).

Version 2.0.0 marks the first release of the maintained fork: a thorough
modernisation of the inherited script with autotools build system, a 280-test
suite across three tiers (unit / integration / smoke), env-overridable system
paths for sandboxing, and 15 latent bugs fixed.  See [`ChangeLog`](ChangeLog)
for the full breakdown.

The 2.0.0 modernization was carried out with heavy use of the Claude
large-language model (Anthropic) as a coding assistant; every change was
reviewed by hand and validated against the bats unit, integration, and
smoke test layers, shellcheck, and `make distcheck` before landing.

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

Always start with `--pretend` to review the planned changes before letting
portconf write anything.  Every mutating operation creates a backup tarball
under `/var/lib/portconf/` first; use `portconf --restore` to roll back.

---

## Options

See `portconf --help` or `man portconf` for the full option list (35 flags
across 8 categories).  Tab-completion is provided for bash and zsh — see
[`INSTALL`](INSTALL) for the install paths.

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

The config-file path itself honors the `PORTCONF_CONF` env var; see below.

---

## Environment overrides (for chroots, sandboxes, test harnesses)

The six system path roots are env-overridable.  Defaults match the canonical
modern Gentoo layout; override only if you know what you're doing — pointing
them at the wrong location can sweep or modify real system state.

```
PORT_ETC       config dir            (default: /etc/portage)
BRDIR          backup tarball dir    (default: /var/lib/portconf)
PKGDB          installed-package db  (default: /var/db/pkg)
WORLD          world file            (default: /var/lib/portage/world)
DEP_PATH       eix dep-cache root    (default: /var/cache/edb/dep)
PORTCONF_CONF  config-file path      (default: /etc/portconf.conf)
```

---

## Installation

Production (Gentoo): install from the [`::stuff`](https://github.com/istitov/stuff) overlay.

From source: `autoreconf -i && ./configure && make && doas make install`.
See [`INSTALL`](INSTALL) for full details, runtime dependencies, and the
test-suite invocation.

---

## License

GNU General Public License v3 or later — see [`COPYING`](COPYING) for the
full text.

Original copyright megabaks; maintained fork copyright 2026 Ivan S. Titov.
