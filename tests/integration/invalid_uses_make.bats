#!/usr/bin/env bats
# Integration tests for invalid_uses_make().
#
# Uses real eix --print-all-useflags to determine which flags are valid.
# "nls" is a well-known global USE flag present in any Gentoo tree; it is
# used as the "known-valid" flag in these tests.  "not_a_real_use_flag_xyz"
# is a clearly synthetic token that eix will never report as valid.
#
# Overridden globals:
#   makefile   — scratch file acting as /etc/portage/make.conf
#   yes="1"    — diff_ask auto-applies changes
#   PRETEND="" — diff_ask writes (not dry-run)

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	TEST_MAKEFILE="$(mktemp)"
	makefile="${TEST_MAKEFILE}"
}

teardown() {
	teardown_test_portage
	[[ -n "${TEST_MAKEFILE:-}" ]] && rm -f "${TEST_MAKEFILE}"
}

@test "invalid_uses_make: invalid flag removed from makefile" {
	printf 'USE=" nls not_a_real_use_flag_xyz"\n' > "${makefile}"
	invalid_uses_make
	run grep 'not_a_real_use_flag_xyz' "${makefile}"
	assert_failure
}

@test "invalid_uses_make: valid flag preserved after invalid removed" {
	printf 'USE=" nls not_a_real_use_flag_xyz"\n' > "${makefile}"
	invalid_uses_make
	run grep 'nls' "${makefile}"
	assert_success
}

@test "invalid_uses_make: no invalid flags — file unchanged" {
	printf 'USE=" nls doc"\n' > "${makefile}"
	local before
	before="$(cat "${makefile}")"
	invalid_uses_make
	run cat "${makefile}"
	assert_output "${before}"
}

@test "invalid_uses_make: negated invalid flag removed" {
	printf 'USE=" -not_a_real_use_flag_xyz nls"\n' > "${makefile}"
	invalid_uses_make
	run grep 'not_a_real_use_flag_xyz' "${makefile}"
	assert_failure
}

@test "invalid_uses_make: negated valid flag preserved" {
	printf 'USE=" -nls doc"\n' > "${makefile}"
	invalid_uses_make
	run grep -- '-nls' "${makefile}"
	assert_success
}
