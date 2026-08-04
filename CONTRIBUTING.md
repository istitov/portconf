# Contributing to portconf

Thanks for taking the time to look at portconf.  This file covers
what you need to know to file a bug, propose a feature, or send a
pull request.

## Reporting bugs

Open an issue using the **Bug report** template.  It asks for:

- the exact `portconf --version` output
- the portage / eix / portage-utils versions involved
- the command you ran and the full output (paste raw)
- what you expected to happen vs what actually happened
- the content of any `/etc/portage/*` file the bug involves — the
  bug-report template lists the typical flag → file pairings; strip
  anything sensitive but keep the structure intact

Reproducible reports get triaged first.

## Proposing features

Open an issue using the **Feature request** template.  Describe the
use case before the proposed implementation — portconf has 35 flags
across 8 categories, and there's often a way to do what you want
already.  Check `portconf --help` and `man portconf` first.

## Submitting pull requests

Fork the repo, create a branch off `master`, open a PR.  Two
requirements:

1. **Tests stay green.**  Locally:

   ```sh
   autoreconf -i
   ./configure
   make
   make check                 # bats unit suite
   make check-integration     # needs real eix + qatom + agrep
   make check-smoke           # needs a populated Gentoo host
   make check-properties      # transform-invariant suite (needs eix; qatom for -ui)
   ```

   `make check-integration` needs a populated eix cache — run
   `eix-update` first if you've just installed eix or haven't synced
   recently, or some `invalid_uses` / `invalid_uses_make` tests will
   fail spuriously.

   And independently, the dist tarball must build cleanly in an
   isolated tree — verified by:

   ```sh
   make distcheck
   ```

   CI runs all four test tiers, `shellcheck --severity=error
   src/portconf`, completion-file syntax checks (`bash -n` /
   `zsh -n`), and `make distcheck` on `gentoo/stage3:latest`.  Any
   new code path needs at least one test.

2. **`shellcheck --severity=error src/portconf` clean.**  CI enforces
   this threshold; the local [`.shellcheckrc`](.shellcheckrc) honours
   the same baseline.  Lower-severity findings are tracked (see deferred
   items in [`ChangeLog`](ChangeLog)) but don't block.

## Source layout

`src/portconf.in` is organised into 24 topical sections.  Each section is
introduced by a banner of the form:

```
# ============================================================================
# === SECTION NAME
# === Brief description.  Function list.
# === [optional source-time-side-effect note]
# ============================================================================
```

Run `make toc` from the project root to see the full section index with
line numbers.  When adding a function, drop it under the right existing
section (don't leave it floating between sections); when adding a whole
new topical area, copy an existing banner as the template and keep the
five-line shape so `make toc` keeps working.

Every function has a one-line docstring of the form `# name: brief
description.` directly above its definition.  Add one for any new
function; keep the description ground-truth (echoes what it does, not
the call sites).

## Adding a new flag

A new flag typically needs changes in five places:

- `src/portconf.in` — the code, including arg parsing and `--help`
- `man/portconf.1` — manpage entry under the matching section
- `completion/portconf` and `completion/_portconf` — bash and zsh
- [`ChangeLog`](ChangeLog) — under the next release's entry
- `tests/unit/` or `tests/integration/` — at least one coverage test

Removing a flag touches the same places.

## Commit messages

Substantive commits get a structured body explaining *why*, not just
*what* the diff shows.  Subject line under 70 characters, imperative
mood, no trailing period.  Pure cosmetic / typo commits can stay
single-line.

## Code style

- `set -euo pipefail` at the top of `src/portconf.in` (the main script).
  Bats tests, the completion scripts, and helpers have their own
  conventions and don't need it.
- `IFS= read -r` on every `read` call; tab indent (see [`.editorconfig`](.editorconfig)).
- System path roots are env-overridable.  Don't bake `/etc/portage` /
  `/var/lib/portconf` / `/var/db/pkg` / `/var/lib/portage/world` /
  `/var/cache/edb/dep` / `/etc/portconf.conf` directly into new code —
  use `${PORT_ETC}`, `${BRDIR}`, `${PKGDB}`, `${WORLD}`, `${DEP_PATH}`,
  `${PORTCONF_CONF}` respectively.  See [`INSTALL`](INSTALL) for the full list.
- `qatom -F` with an explicit format string, not the default output —
  the default layout changed in portage-utils 0.97 and broke `package_envs`
  / `mask_trash` (see the 2.0.0 [`ChangeLog`](ChangeLog) entry for the bug class).
- For sed substitutions interpolating user-controlled values, use the
  `_sed_escape_pat` and `_sed_escape_rep` helpers — raw interpolation
  is a known footgun (see the 2.0.0 [`ChangeLog`](ChangeLog) entry).

## Signing

`master` commits are GPG-signed.  PRs don't need to be signed by the
contributor; signing happens at merge time.

## License

By contributing you agree that your changes are licensed under
GPL-3.0-or-later (the project's license; see [`COPYING`](COPYING)).
