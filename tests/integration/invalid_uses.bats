#!/usr/bin/env bats
# Integration tests for invalid_uses().
#
# Uses real eix (with FORMAT/USEONLY env vars set by check_uses) and real
# qatom to test the USE-flag validation logic.
#
# Test atom: sys-apps/grep — a core package present in every Gentoo tree.
# "static" is a valid USE flag for sys-apps/grep that is NOT in the global
# USE settings on this host (nls/pcre/verify-sig are global and would be
# removed by the "redundant global" path — a separate, correct behaviour).
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
