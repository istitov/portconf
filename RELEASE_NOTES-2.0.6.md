## portconf 2.0.6 — Safety Net

This release completes the post-2.0.5 safety audit. It keeps portconf's feature
set intact while making its mutation policy, failure recovery, command-line
handling, and rewrite invariants substantially harder to violate.

### Safer mutation

- Dry-run is now the authoritative default. Changes are applied only with
  `--ask` or `--force` (legacy `-y` remains an alias), including restore,
  conversion, world, and repository workflows.
- Destructive multi-step operations stage replacements on the target
  filesystem and use an undo journal, restoring the original state after an
  ordinary failure.
- Applying invocations take an exclusive advisory lock. Concurrent dry-runs
  remain available.
- Rewrites and file/directory conversions preserve access metadata.

### Exact command-line behavior

- Unknown options fail with usage status 2 before any earlier option can run.
- Arguments remain exact array elements through validation and dispatch, so
  wildcard-shaped tokens cannot expand against the working directory.
- `--help` and `--version` preempt earlier mutating options.
- A bare invocation is always help-only, even if `PORTCONF_DEFAULT_OPTS`
  contains a mutating action. Configured defaults still apply to explicit
  invocations.

### Data-preserving cleanup

- Sorting keeps flagless `package.use` atoms and all header-comment blocks
  attached to duplicate atom occurrences.
- Trash/full cleanup removes stale nested env targets before pruning their
  `package.env` references, completes the rewrite in one pass, preserves useful
  annotations, and removes newly empty directories deepest-first.
- Temp cleanup, backup rotation, eix-cache lifetime, qatom parsing, environment
  cleanup, mask/keyword decisions, overlay cleanup, and status accounting have
  all received additional correctness hardening.

### Verification

The release passes 463 automated tests: 281 unit, 107 integration, 53 smoke,
and 22 property tests. The property tier now directly checks that exact
removal never changes a sibling and that rejected restore archives leave the
live tree unchanged.

Ten representative mutating modes (`-us`, `-s`, `-ku`, `-ko`, `-c`, `-ac`,
`-ui`, `-uf`, `-t`, and `-f`) were also applied twice to isolated copies of a
real `/etc/portage` tree. Every mode passed clean-exit, no-invention,
no-new-duplicate, and idempotence checks.

See the [ChangeLog](https://github.com/istitov/portconf/blob/master/ChangeLog)
for the full per-fix breakdown.

### Install

From the [`::stuff`](https://github.com/istitov/stuff) overlay:

```sh
eselect repository enable stuff
emaint sync -r stuff
emerge --quiet-build app-portage/portconf
```

From source:

```sh
git clone https://github.com/istitov/portconf
cd portconf
autoreconf -i && ./configure && make && sudo make install
```

### Verify

```sh
sha256sum -c portconf-2.0.6.tar.xz.sha256
gpg --verify portconf-2.0.6.tar.xz.asc portconf-2.0.6.tar.xz
git tag -v 2.0.6
```

The release tag is signed with EDDSA key
`0CAC B6D9 B849 3DB5 8470 0971 3EB2 3EA8 4387 95B7`.

---

*AI-assisted: the 2.0.6 audit and implementation used OpenAI Codex as a coding
assistant. Every change was reviewed and validated with the full automated
suite, ShellCheck, `make distcheck`, and isolated real-config-copy checks.*
