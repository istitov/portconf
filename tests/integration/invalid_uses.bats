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
