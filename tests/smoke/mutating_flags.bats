#!/usr/bin/env bats
# Smoke: mutating dispatch arms exercised end-to-end with --pretend.
#
# Every test here forks the BUILT src/portconf binary with these env-var
# overrides pointing at throwaway tmpdirs:
#
#   PORT_ETC   sandboxed config tree (with representative fixture files)
#   BRDIR      sandboxed backup output dir (backup() writes here)
#   PKGDB      empty sandbox (so the few PKGDB-readers find no packages)
#   DEP_PATH   sandboxed dep-cache (so overlays()'s fix_deps doesn't
#              touch the host's /var/cache/edb/dep)
#
# Combined with -p (--pretend), every actual file mutation downstream of
# backup() is gated — assertions can verify PORT_ETC is unchanged after
# the run.  backup() itself ALWAYS writes (it doesn't honor PRETEND by
# design), so each test confirms the tarball lands in the sandboxed BRDIR.
#
# Coverage focus: the dispatch arm wiring.  Unit and integration tests
# already validate each individual function; smoke validates that the
# binary actually walks every case-statement branch from start to finish
# without crashing, and that the composite arms (-uf chains 6 functions,
# -t chains 6, -f chains 13+) work as the dispatcher intended.
#
# eix-cache strategy: for arms that need real eix (-ui/-uf/-t/-ft/-f/-sm/-sum
# satisfy the _needs_eix gate), eix_method's "Create temporary cache?"
# prompt fires when OVERLAY_CACHE_METHOD != "parse|ebuild*" (the modern
# Gentoo default).  smoke_run pipes "No" to dismiss it; eix then uses
# the host's existing populated cache to validate test atoms.  -um is NOT
# here -- use_makeconf reads no eix cache.

load test_helper

setup() {
	if ! command -v eselect >/dev/null; then
		skip "eselect not on PATH"
	fi
	if ! command -v eix >/dev/null; then
		skip "eix not on PATH"
	fi
	smoke_sandbox
}

teardown() {
	smoke_cleanup
}

# Helper assertions.

_assert_brdir_has_backup() {
	# backup() writes portage_<timestamp>.tar.bz2 unconditionally on every
	# mutating-arm invocation (PRETEND doesn't gate backup itself).
	[[ -n "$(ls "${SMOKE_BRDIR}/")" ]]
}

_assert_port_etc_unchanged() {
	# With -p, no function downstream of backup() should mutate PORT_ETC.
	# The fixture's package.use must still contain its original content.
	local content
	content="$(cat "${SMOKE_PORT_ETC}/package.use")"
	[[ "${content}" == 'sys-apps/grep static' ]]
}

# --- single-step arms (no eix-dep-keys, no composite) -------------------

@test "smoke: -y -p -b — standalone backup" {
	smoke_run -y -p -b
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
	_assert_port_etc_unchanged
}

@test "smoke: -y -p -c — backup + rm_comments" {
	# Add a comment line that rm_comments would target.
	printf '# leading comment\nsys-apps/grep static\n' \
		> "${SMOKE_PORT_ETC}/package.use"
	smoke_run -y -p -c
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -y -p -ac — backup + rm_all_comments" {
	smoke_run -y -p -ac
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -y -p -f2d — backup + f_to_d (file → dir layout)" {
	smoke_run -y -p -f2d
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

# --- composite arms WITHOUT eix-dep-keys --------------------------------

@test "smoke: -y -p -s — sort composite (backup + 4 fns)" {
	smoke_run -y -p -s
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -y -p -us — backup + sort_use_file" {
	smoke_run -y -p -us
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -y -p -ku — backup + uniq_keywords" {
	smoke_run -y -p -ku
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -y -p -ko — backup + sort_keywords" {
	smoke_run -y -p -ko
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -y -p -um — backup + use_makeconf (reads no eix cache)" {
	smoke_run -y -p -um
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

# --- composite arms WITH eix-dep-keys (slow path) -----------------------
# Each calls a handler that queries the eix PACKAGE cache, so _needs_eix fires
# and eix_method prompts (dismissed with "No" -> host cache) when run without
# -y.  -sm/-sum (mask_trash / remove_trash) join the set the binary used to
# skip; -um moved out above (use_makeconf reads no cache).

@test "smoke: -p -sm — backup + mask_trash (real qatom; now gated on eix)" {
	# Pre-fix, -sm skipped the eix gate entirely and ran mask_trash against
	# whatever host cache happened to exist; it now routes through eix_method
	# like -ui, so the "No" pipe (not -y) keeps it on the host cache.
	smoke_run -p -sm
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -p -sum — backup + stupid_unmask -> remove_trash (gated on eix)" {
	smoke_run -p -sum
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -p -ui — invalid_uses composite" {
	# Without -y, eix_method DOESN'T auto-run eix-update; smoke_run pipes
	# "No" to dismiss the prompt and uses the host's existing cache.
	smoke_run -p -ui
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
	_assert_port_etc_unchanged
}

@test "smoke: -p -t — trash composite (6 fns including not_found chain)" {
	smoke_run -p -t
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

@test "smoke: -p -uf — use-full composite (backup + 6 fns + eix cleanup)" {
	# Exercises the eix_cache cleanup branch at the end of the -uf dispatch
	# arm (line ~1923) — unreachable by unit/integration tests because
	# eix_check is what populates ${eix_cache}, and it runs only here.
	smoke_run -p -uf
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
	_assert_port_etc_unchanged
}

@test "smoke: -p -f — full composite (the big one — 13+ fns)" {
	# The most comprehensive dispatch arm.  A wiring regression anywhere
	# in this chain surfaces here even if every individual function still
	# passes its unit tests.
	smoke_run -p -f
	[ "$status" -eq 0 ]
	_assert_brdir_has_backup
}

# --- profile-listing already covered by profile.bats; world-state arm ---

@test "smoke: -f preserves header comments end-to-end on directory-layout package.use" {
	# Regression for the sort_uniq_files + sort_uses comment-deletion
	# bug (fixed by the gawk-based rewrites).  Pre-fix, both functions
	# rebuilt the file from atoms only — every header comment vanished.
	# This test runs the FULL -f chain (which calls both, plus the
	# rest of the dispatch) against a directory-layout package.use
	# fragment that contains a header comment block above an atom,
	# and asserts the header survives.
	(( UID != 0 )) && skip "needs root for diff_ask mv branch"
	rm -f "${SMOKE_PORT_ETC}/package.use"
	mkdir "${SMOKE_PORT_ETC}/package.use"
	# Fixture: header comment + atom + flag.  sys-apps/grep is on every
	# Gentoo install (system set) so the atom survives not_found.
	# 'static' is a long-stable IUSE that won't be flagged invalid.
	printf '%s\n' \
		'# Why grep keeps static linking: bug-compat with ancient scripts' \
		'# that exec /bin/grep before /usr is mounted.  See bug #00000.' \
		'sys-apps/grep static' \
		> "${SMOKE_PORT_ETC}/package.use/grep"
	# PORTCONF_CONF=/dev/null suppresses host /etc/portconf.conf, which
	# often sets PORTCONF_DEFAULT_OPTS="-rc" — that would auto-trigger
	# eix_check + eix-update and make the test slow + tied to the host's
	# eix cache state.
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" \
		BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" \
		DEP_PATH="${SMOKE_DEP}" \
		PORTCONF_CONF=/dev/null \
		"${PORTCONF_BIN}" -f -y <<< $'No\n'
	[ "$status" -eq 0 ]
	# Both comment lines must survive the full dispatch chain.
	local content
	content="$(cat "${SMOKE_PORT_ETC}/package.use/grep")"
	[[ "${content}" == *'Why grep keeps static linking'* ]] || \
		{ echo "missing first header line; got:" >&2; cat "${SMOKE_PORT_ETC}/package.use/grep" >&2; false; }
	[[ "${content}" == *'See bug #00000'* ]] || \
		{ echo "missing second header line; got:" >&2; cat "${SMOKE_PORT_ETC}/package.use/grep" >&2; false; }
	[[ "${content}" == *'sys-apps/grep static'* ]] || \
		{ echo "atom missing; got:" >&2; cat "${SMOKE_PORT_ETC}/package.use/grep" >&2; false; }
}

@test "smoke: interactive Yes mutates when package.use is a directory" {
	# Regression for the file_or_dir directory-branch stdin-redirect bug.
	# When package.use is a directory (the modern Gentoo layout), file_or_dir
	# iterates its fragments via `done < <(find ...)`; the process-
	# substitution clobbers fd 0 for the loop body, so the nested
	# diff_ask's `read x` would hit EOF instead of the user's "Yes"
	# answer and silently rm the tmp file without mutating PORT_ETC.
	# diff_ask now reads from fd 9 (dispatch-entry stdin dup) instead.
	# Needs UID==0 because diff_ask's Yes branch gates mv on root.
	(( UID != 0 )) && skip "needs root for diff_ask mv branch"
	rm -f "${SMOKE_PORT_ETC}/package.use"
	mkdir "${SMOKE_PORT_ETC}/package.use"
	printf 'sys-apps/grep static\nsys-apps/grep static\nsys-apps/grep -static\n' \
		> "${SMOKE_PORT_ETC}/package.use/grep"
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" \
		BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" \
		DEP_PATH="${SMOKE_DEP}" \
		"${PORTCONF_BIN}" -us <<< $'Yes\n'
	[ "$status" -eq 0 ]
	# Without the fix: 3 lines unchanged.  With the fix: sort_uses collapses
	# duplicates and last-state ("-static") wins, leaving one normalised line.
	local content
	content="$(cat "${SMOKE_PORT_ETC}/package.use/grep")"
	[[ "${content}" == 'sys-apps/grep -static' ]]
}

@test "smoke: -y -p -wb — world_backup standalone" {
	# WORLD defaults to /var/lib/portage/world (real host path).  For
	# isolated smoke testing point it at the sandbox.  Tarball lands in
	# ${BRDIR}/world/ — verify it's there.
	mkdir -p "${SMOKE_PORT_ETC}/world_dir"
	local world_file="${SMOKE_PORT_ETC}/world_dir/world"
	printf 'sys-apps/portage\n' > "${world_file}"
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" \
		BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" \
		DEP_PATH="${SMOKE_DEP}" \
		WORLD="${world_file}" \
		"${PORTCONF_BIN}" -y -p -wb <<< $'No\n'
	[ "$status" -eq 0 ]
	[[ -d "${SMOKE_BRDIR}/world" ]]
	[[ -n "$(ls "${SMOKE_BRDIR}/world/")" ]]
}
