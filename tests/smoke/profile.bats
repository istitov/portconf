#!/usr/bin/env bats
# Smoke: profile-listing dispatch paths against a real profile tree.
#
# These tests exercise the read-only paths that consume:
#   - eselect --brief profile list  (must return one path per line)
#   - readlink /etc/(portage/)make.profile
#   - sourcing make.defaults from each profile tier with set -u disabled
#   - sort_passed_uses post-processing
#
# A regression in any of (eix, eselect, profile-tree layout, USE-expansion
# semantics) would surface here before users hit it.  No mutation: -apu
# and -cpu only read from ${PORTDIR}/profiles and /etc/(portage/)make.profile.

load test_helper

setup() {
	if ! command -v eselect >/dev/null; then
		skip "eselect not on PATH"
	fi
	if ! command -v eix >/dev/null; then
		skip "eix not on PATH"
	fi
	# Both -apu and -cpu need a resolvable current profile.
	if [[ ! -L /etc/portage/make.profile && ! -L /etc/make.profile ]]; then
		skip "no /etc/portage/make.profile symlink on this host"
	fi
}

@test "smoke: -apu lists all profiles with their USE flags" {
	run "${PORTCONF_BIN}" -apu
	[ "$status" -eq 0 ]
	# Every Gentoo profile tree contains a "default/linux/<arch>" tier;
	# asserting on that catches "profile output suppressed" regressions
	# without hardcoding any one arch.
	assert_output_contains 'default/linux/'
}

@test "smoke: -cpu reports the current profile and its USE flags" {
	run "${PORTCONF_BIN}" -cpu
	[ "$status" -eq 0 ]
	assert_output_contains 'default/linux/'
	# Output is one line: '<profile-path>: <use flags...>'.  The colon
	# separator is the contract between current_profile() and downstream
	# consumers (no machine-readable mode exists yet).
	[[ "$(strip_ansi "${output}")" == *': '* ]]
}

@test "smoke: --all-profiles-use long form works" {
	run "${PORTCONF_BIN}" --all-profiles-use
	[ "$status" -eq 0 ]
	assert_output_contains 'default/linux/'
}

@test "smoke: --current-profile-use long form works" {
	run "${PORTCONF_BIN}" --current-profile-use
	[ "$status" -eq 0 ]
	assert_output_contains 'default/linux/'
}
