# Property-test bats helper.
#
# The property tier drives the BUILT src/portconf binary end-to-end (like
# smoke) but asserts *invariants* rather than "doesn't crash":
#
#   idempotence            apply a flag twice -> the second run is a no-op
#   no-duplicate-flag      no atom line carries the same base flag twice
#   inventory-preservation the atom set is preserved (modulo intended drops)
#
# These are oracle-free correctness checks: they don't encode a golden
# output, so they catch regressions a fixed-output test can't anticipate.
# They are exactly the checks that surfaced the 2.0.4 corruption bugs
# (invalid_uses' agrep "did you mean" created duplicate flags and broke
# idempotence; diff_ask silently discarded changes).  See the project
# memory feedback_verify_on_real_config_copy / suspect-the-verification-harness.
#
# Fixtures are SYNTHETIC and UNIVERSAL on purpose (anonymity): made-up
# atoms in fake categories (cat-test/*, cat-demo/*), generic flag tokens
# (foo/bar/baz/...), synthetic arch tokens (~testarch) that can never
# match a host's real ACCEPT_KEYWORDS, and — only where real eix metadata
# is unavoidable (invalid_uses) — @system-universal packages (sys-apps/grep)
# plus an obviously-fake flag (not_a_real_use_flag_xyz).  No cross-compile
# targets, no video_cards_*/cpu_flags_*, none of the maintainer's real
# package mix.  For real-config verification use the local-only, gitignored
# scripts/verify-local.sh instead — its data is never committed.

source "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Path to the built binary.  Same resolution as the smoke tier.
PORTCONF_BIN="${BATS_TEST_DIRNAME}/../../src/portconf"

# Create a sandboxed path environment.  Each root is a fresh mktemp dir,
# kept DISTINCT from each other and from the binary's own _mktemp temp dir
# (which honors $TMPDIR) — an in-place "tmp == target" overlap is the
# classic harness self-corruption (suspect-the-verification-harness).
prop_sandbox() {
	PROP_PORT_ETC="$(mktemp -d)"
	PROP_BRDIR="$(mktemp -d)"
	PROP_PKGDB="$(mktemp -d)"
	PROP_DEP="$(mktemp -d)"
	# make.conf must exist before the binary forks: the `makefile` global is
	# captured at portconf.in source time, and invalid_uses_make/use_makeconf
	# `cp "${makefile}" ...` fails when it's empty.  Comment-only -> empty USE
	# baseline so the GLOBAL-redundancy path stays predictable.
	printf '# synthetic test make.conf\n' > "${PROP_PORT_ETC}/make.conf"
}

# Remove the sandbox.  Idempotent.
prop_cleanup() {
	[[ -n "${PROP_PORT_ETC:-}" ]] && rm -rf "${PROP_PORT_ETC}"
	[[ -n "${PROP_BRDIR:-}"    ]] && rm -rf "${PROP_BRDIR}"
	[[ -n "${PROP_PKGDB:-}"    ]] && rm -rf "${PROP_PKGDB}"
	[[ -n "${PROP_DEP:-}"      ]] && rm -rf "${PROP_DEP}"
}

# Run the binary with -y (auto-apply, non-interactive) against the sandbox.
# Sets bats' $status/$output via `run`.
#
#   -y                       diff_ask applies via mv without prompting; the
#                            sandbox is user-writable so no root is needed.
#   PORTCONF_CONF=/dev/null  skip the host /etc/portconf.conf (which often
#                            sets PORTCONF_DEFAULT_OPTS="-rc").
#   OVERLAY_CACHE_METHOD=... force eix_method's "Create temporary cache?"
#                            branch off so eix-dep flags reuse the host cache
#                            instead of running a slow eix-update.
# The piped "No" answers are belt-and-braces: -y bypasses diff_ask's read
# and the cache-method override suppresses eix_method's prompt, so nothing
# actually consumes them — but they keep the run non-blocking if a prompt
# ever reappears.
prop_apply() {
	run env \
		PORT_ETC="${PROP_PORT_ETC}" \
		BRDIR="${PROP_BRDIR}" \
		PKGDB="${PROP_PKGDB}" \
		DEP_PATH="${PROP_DEP}" \
		PORTCONF_CONF=/dev/null \
		OVERLAY_CACHE_METHOD="parse|ebuild*" \
		"${PORTCONF_BIN}" -y "$@" <<< $'No\nNo\nNo\nNo\n'
}

# cat a package.* target whether it's a flat file or a directory of fragments
# (the modern Gentoo layout).  Mirrors portconf's own find filter.
_prop_cat() {
	local t="$1"
	if [[ -d "$t" ]]; then
		find "$t" -type f \! -name '*~' \! -name '*.bak' -exec cat {} +
	else
		cat "$t"
	fi
}

# Print the sorted-unique atom set (first field of every non-comment,
# non-blank line) of a package.* file or directory.
atoms_of() {
	_prop_cat "$1" | awk 'NF && $1 !~ /^#/ { print $1 }' | sort -u
}

# Assert the atom set of $2 (file/dir) exactly equals the captured set $1.
# Use for transforms that must never add or drop an atom (sort/dedup).
assert_atoms_equal() {
	local before="$1" after
	after="$(atoms_of "$2")"
	if [[ "${before}" != "${after}" ]]; then
		printf 'inventory NOT preserved (atom set changed):\n--- before ---\n%s\n--- after ---\n%s\n' \
			"${before}" "${after}" >&2
		return 1
	fi
}

# Assert the atom set of $2 (file/dir) is a SUBSET of the captured set $1 —
# i.e. no new atom appeared.  Use for removal transforms (-ui) where some
# atoms are intentionally dropped but none may be invented.
assert_atoms_subset() {
	local before="$1" after extra
	after="$(atoms_of "$2")"
	extra="$(comm -13 <(printf '%s\n' "${before}") <(printf '%s\n' "${after}"))"
	if [[ -n "${extra}" ]]; then
		printf 'inventory violated — NEW atoms appeared (not a subset of input):\n%s\n' \
			"${extra}" >&2
		return 1
	fi
}

# Assert no atom line carries the same base flag twice.  A "base" is the
# token with any leading -/~ stripped (so `foo` and `-foo`, or `amd64` and
# `~amd64`, collide).  Inline comments are ignored.  Works for both
# package.use (USE flags) and package.{,accept_}keywords (arch keywords).
# This is the direct guard for the agrep "did you mean" duplicate-flag bug.
assert_no_dup_flags() {
	local target="$1" report
	report="$(
		_prop_cat "${target}" | awk '
			/^[[:space:]]*$|^[[:space:]]*#/ { next }
			{
				line = $0
				sub(/[[:space:]]+#.*/, "", line)      # drop inline comment
				n = split(line, f, /[[:space:]]+/)
				delete seen
				for (i = 2; i <= n; i++) {
					t = f[i]
					if (t == "") continue
					sub(/^[-~]/, "", t)
					if (t == "") continue
					if (t in seen) { printf "  dup %s in: %s\n", t, $0; bad = 1 }
					seen[t] = 1
				}
			}
			END { exit (bad ? 1 : 0) }
		'
	)" && return 0
	printf 'duplicate flag(s) found in %s:\n%s\n' "${target}" "${report}" >&2
	return 1
}

# Assert re-applying the same flag(s) is a no-op (idempotence).  Snapshots
# the CURRENT sandbox config, re-runs the binary, and diffs.  The snapshot
# dir is outside PORT_ETC; the backup tarball lands in the separate BRDIR,
# so neither perturbs the comparison.
assert_idempotent() {
	local snap diffout
	snap="$(mktemp -d)"
	diffout="$(mktemp)"
	cp -a "${PROP_PORT_ETC}/." "${snap}/"
	prop_apply "$@"
	if [[ "${status}" -ne 0 ]]; then
		printf 'idempotence re-apply of [%s] FAILED (status=%s):\n%s\n' \
			"$*" "${status}" "${output}" >&2
		rm -rf "${snap}" "${diffout}"
		return 1
	fi
	if ! diff -r "${snap}" "${PROP_PORT_ETC}" > "${diffout}" 2>&1; then
		printf 'NOT IDEMPOTENT — second apply of [%s] changed the tree:\n' "$*" >&2
		cat "${diffout}" >&2
		rm -rf "${snap}" "${diffout}"
		return 1
	fi
	rm -rf "${snap}" "${diffout}"
}
