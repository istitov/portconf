# Security Policy

## Supported versions

Security fixes land on the active series only.

| Version | Supported          |
|---------|--------------------|
| 2.0.x   | :white_check_mark: |
| < 2.0   | :x:                |

## Reporting a vulnerability

Use GitHub's Private Vulnerability Reporting:

<https://github.com/istitov/portconf/security/advisories/new>

Expect a first response within 14 days.  Reports that include a
reproducer (a minimal `/etc/portage/package.*` snippet or atom string
that triggers the issue, plus the exact `portconf` invocation) get
triaged first.

If GitHub PVR is unavailable, email <iohann.s.titov@gmail.com>.

## In scope

- **sed / shell injection** via crafted atom names, USE flags,
  `package.use` entries, or repo names — anywhere `package.*` content
  gets interpolated into a `sed s|||`, `grep`, or `awk` pattern.  The
  2.0.0 HIGH#1 fix (`_sed_escape_pat` / `_sed_escape_rep` helpers) is
  the reference; any new unescaped interpolation site qualifies.

- **Out-of-root-path writes** — operations that mutate files outside
  the six declared path roots: `$PORT_ETC`, `$BRDIR`, `$PKGDB`,
  `$WORLD`, `$DEP_PATH`, `$PORTCONF_CONF`.  Path traversal via `../`
  in atom names; tar-side traversal via a crafted backup tarball; etc.

- **`--pretend` bypass** — any code path that mutates state when `-p`
  is in effect.  `backup()` running unconditionally is documented and
  not a bypass; everything *downstream* of `backup()` is.

- **`qatom -F` re-parse drift** — silent misclassification of mask
  atoms when a future `portage-utils` reshuffles the `qatom` output
  format.  The 2.0.0 `7e5ccd7` (`package_envs` modernised for qatom
  0.97+) and `0bf7162` (HIGH#1 — `sed`-injection in `package_env`,
  plus the `file_or_dir` diagnostic cascade) fixes are the reference
  for why this class is in scope.

## Out of scope

- Performance issues.  portconf scales with `/etc/portage` size and
  installed-package count by design.

- "It removed my hand-edited line."  portconf sorts, dedupes, and
  rewrites the files it operates on; that's the feature, not a bug.
  Use `--pretend` and inspect the diff before non-pretend runs.

- Issues already fixed in the supported version.  Check the
  [`ChangeLog`](ChangeLog) before reporting.

- Anything that requires pre-existing root-equivalent access on the
  same host.  portconf runs as root by design.

- ANSI escape leakage from non-TTY output — addressed by the
  NO_COLOR + isatty gate added pre-2.0.0.

## Disclosure

Once a fix is available, an advisory is published on the GitHub
Security tab (with a CVE if it warrants one) and the corresponding
ChangeLog entry references it.
