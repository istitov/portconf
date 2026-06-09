#!/usr/bin/env bats
# Integration tests for invalid_uses().
#
# Uses real eix (with FORMAT/USEONLY env vars set by check_uses) and real
# qatom to test the USE-flag validation logic.
#
# Test atom: sys-apps/grep — a core package present in every Gentoo tree.
# "static" is a long-stable IUSE entry for sys-apps/grep used as the
# "known-valid" flag.  PROFILE and MAKE_USES are forced empty by
# make_test_portage so GLOBAL is empty by default — invalid_uses' "redundant
# global" code path is covered by a dedicated test that sets PROFILE
# explicitly, rather than relying on whatever the host happens to inherit.
# "not_a_real_use_flag_xyz" is a synthetic token eix will never recognise.
#
# Stubs:
#   agrep() — returns empty (no fuzzy suggestion); prevents test results
#             from depending on agrep's edit-distance heuristics.
#   tput()  — already stubbed as no-op in make_test_portage (non-TTY safe).

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	agrep() { :; }
}

teardown() {
	teardown_test_portage
}

@test "invalid_uses: invalid USE flag removed from package.use" {
	printf 'sys-apps/grep static not_a_real_use_flag_xyz\n' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	run grep 'not_a_real_use_flag_xyz' "${PORT_ETC}/package.use"
	assert_failure
}

@test "invalid_uses: valid non-global USE flag preserved after invalid removed" {
	printf 'sys-apps/grep static not_a_real_use_flag_xyz\n' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	run grep 'static' "${PORT_ETC}/package.use"
	assert_success
}

@test "invalid_uses: all-valid non-global USE flags — file unchanged" {
	printf 'sys-apps/grep static\n' > "${PORT_ETC}/package.use"
	local before
	before="$(cat "${PORT_ETC}/package.use")"
	invalid_uses
	run cat "${PORT_ETC}/package.use"
	assert_output "${before}"
}

@test "invalid_uses: atom line with only invalid flag — line removed" {
	printf 'sys-apps/grep not_a_real_use_flag_xyz\n' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	run grep 'sys-apps/grep' "${PORT_ETC}/package.use"
	assert_failure
}

@test "invalid_uses: negated invalid flag removed" {
	printf 'sys-apps/grep static -not_a_real_use_flag_xyz\n' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	run grep 'not_a_real_use_flag_xyz' "${PORT_ETC}/package.use"
	assert_failure
}

@test "invalid_uses: flag already in GLOBAL is removed as redundant" {
	# When a flag is set in PROFILE or MAKE_USES, declaring it again per-atom
	# is redundant — invalid_uses strips it.  PROFILE is normally derived from
	# the live profile tree; we set it explicitly here to make the test
	# host-independent.
	PROFILE="static"
	printf 'sys-apps/grep static\n' > "${PORT_ETC}/package.use"
	invalid_uses
	run grep 'static' "${PORT_ETC}/package.use"
	assert_failure
}

@test "invalid_uses: bare-atom drop also removes the orphaned header block" {
	# Regression: when invalid_uses strips all USE flags from an
	# atom (because they're invalid or already global), the line
	# collapses to just "atom" and gets dropped.  Pre-fix, the
	# header comments above the atom stayed orphaned in the file.
	# Now they go too.
	printf '# why we wanted that invalid flag\n# (whole story)\nsys-apps/grep not_a_real_use_flag_xyz\n' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	run cat "${PORT_ETC}/package.use"
	# Both header lines AND the atom should be gone.
	[[ "${output}" != *'why we wanted that invalid flag'* ]] \
		|| { echo "orphan header line 1 still present: $output" >&2; false; }
	[[ "${output}" != *'(whole story)'* ]] \
		|| { echo "orphan header line 2 still present: $output" >&2; false; }
	[[ "${output}" != *'sys-apps/grep'* ]] \
		|| { echo "atom still present: $output" >&2; false; }
}

@test "invalid_uses: bare-atom drop leaves surrounding atoms + their headers intact" {
	printf '%s\n' \
		'# header for valid_atom' \
		'sys-apps/grep static' \
		'' \
		'# header for the doomed atom' \
		'sys-apps/grep not_a_real_use_flag_xyz' \
		'' \
		'# header for second valid atom' \
		'sys-libs/ncurses minimal' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	run cat "${PORT_ETC}/package.use"
	# Both surviving atoms must keep their headers.
	[[ "${output}" == *'# header for valid_atom'* ]] \
		|| { echo "valid header missing: $output" >&2; false; }
	[[ "${output}" == *'# header for second valid atom'* ]] \
		|| { echo "second valid header missing: $output" >&2; false; }
	# Doomed atom's header is gone.
	[[ "${output}" != *'header for the doomed atom'* ]] \
		|| { echo "doomed header should be gone: $output" >&2; false; }
}

@test "invalid_uses: agrep -B fallback is not invoked (edit-distance bound)" {
	# Regression for the agrep silent-substitution misfeature: the
	# legacy `agrep -B` (best-match-regardless-of-distance) would
	# rewrite a typoed flag to whatever IUSE token sorted first under
	# tied Levenshtein, even at edit-distance 10+.  The loop now caps
	# at -1/-2/-3; -B is unreachable.  This stub returns a "match"
	# only when -B is invoked — if it is, the flag would be silently
	# rewritten to 'should_not_be_substituted', which the assertion
	# below catches.
	agrep() {
		case "$1" in
			-B) printf 'should_not_be_substituted\n' ;;
			*) return 1 ;;
		esac
	}
	printf 'sys-apps/grep static not_a_real_use_flag_xyz\n' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	# Flag must be removed (not silently substituted).
	run grep 'not_a_real_use_flag_xyz' "${PORT_ETC}/package.use"
	assert_failure
	# And the would-be -B substitute must NOT appear.
	run grep 'should_not_be_substituted' "${PORT_ETC}/package.use"
	assert_failure
}

@test "invalid_uses: a bounded agrep match is not applied (correction removed; no dup)" {
	# Regression: the agrep edit-distance "did you mean" correction was
	# removed entirely.  On real configs it mis-mapped genuinely-removed
	# flags to unrelated valid ones (gles1->test, xvmc->llvm, pipe->zip) and,
	# when the target was already present, duplicated it (test test).  Even
	# when agrep returns a single match, the invalid flag must just be
	# REMOVED, leaving the already-present valid flag exactly once.
	agrep() { printf 'static\n'; }
	printf 'sys-apps/grep static not_a_real_use_flag_xyz\n' \
		> "${PORT_ETC}/package.use"
	invalid_uses
	run grep 'not_a_real_use_flag_xyz' "${PORT_ETC}/package.use"
	assert_failure
	# 'static' must appear exactly once — no correction-induced duplicate.
	run bash -c "grep -ow static '${PORT_ETC}/package.use' | wc -l"
	assert_output "1"
}
