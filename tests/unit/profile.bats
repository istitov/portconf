#!/usr/bin/env bats
# Tests for current_profile() — prints the active profile's USE flags (-cpu).
#
# Regression: with no make.profile symlink (an unconfigured tree, or a
# sandboxed PORT_ETC), current_profile used to run an unguarded
# `readlink "$PORT_ETC/make.profile"`, which under set -e + pipefail aborted
# the function (empty output, non-zero exit). It now detects a missing symlink
# and reports cleanly with exit 0.
#
# Both tests assume the host has no legacy /etc/make.profile symlink (modern
# Gentoo keeps it at /etc/portage/make.profile); they skip otherwise, since
# current_profile prefers /etc/make.profile when present.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() { teardown_test_portage; }

@test "current_profile: no make.profile symlink -> clean message, exit 0 (no set -e abort)" {
	[[ -h /etc/make.profile ]] && skip "host has a legacy /etc/make.profile symlink"
	# make_test_portage's sandbox PORT_ETC has no make.profile.
	run current_profile
	assert_success
	assert_output --partial 'No active profile'
}

@test "current_profile: PORT_ETC/make.profile symlink -> resolves and prints the profile" {
	[[ -h /etc/make.profile ]] && skip "host has a legacy /etc/make.profile symlink"
	# Link text need not exist on disk; readlink reads the link itself.
	ln -s "/var/db/repos/gentoo/profiles/default/linux/amd64/23.0" \
		"${TEST_PORT_ETC}/make.profile"
	PROFILE="X -gtk"
	run current_profile
	assert_success
	assert_output --partial 'default/linux/amd64/23.0'
	refute_output --partial 'No active profile'
}
