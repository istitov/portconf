#!/usr/bin/env bats
# Tests for use_makeconf() — removes from make.conf any USE flag that appears
# identically in both MAKE_USES (the USE= value from make.conf) and PROFILE
# (the profile-tree USE flags).
#
# Positive duplicate: "flag" in both → sed removes " flag" from makefile.
# Negative duplicate: "-flag" in both → sed removes " -flag" from makefile.
# Partial overlap (flag in only one source) → no change.
#
# Dependencies overridden per test:
#   makefile  — absolute path to a scratch file acting as /etc/portage/make.conf
#   MAKE_USES — space-separated USE flags (from make.conf USE= value)
#   PROFILE   — newline-separated flags from the profile tree
#   yes="1" / PRETEND="" — set by make_test_portage so diff_ask auto-applies

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

# --- positive duplicate: flag appears in both MAKE_USES and PROFILE ---

@test "use_makeconf: positive duplicate — flag removed from makefile" {
	printf 'USE=" foo bar"\n' > "${makefile}"
	MAKE_USES="foo bar"
	PROFILE=$'foo'
	use_makeconf
	run grep 'foo' "${makefile}"
	assert_failure
}

@test "use_makeconf: positive duplicate — non-duplicate flag preserved" {
	printf 'USE=" foo bar"\n' > "${makefile}"
	MAKE_USES="foo bar"
	PROFILE=$'foo'
	use_makeconf
	run grep 'bar' "${makefile}"
	assert_success
}

# --- negative duplicate: -flag appears in both MAKE_USES and PROFILE ---

@test "use_makeconf: negative duplicate — negated flag removed from makefile" {
	printf 'USE=" -foo bar"\n' > "${makefile}"
	MAKE_USES="-foo bar"
	PROFILE=$'-foo'
	use_makeconf
	run grep -- '-foo' "${makefile}"
	assert_failure
}

@test "use_makeconf: negative duplicate — non-duplicate flag preserved" {
	printf 'USE=" -foo bar"\n' > "${makefile}"
	MAKE_USES="-foo bar"
	PROFILE=$'-foo'
	use_makeconf
	run grep 'bar' "${makefile}"
	assert_success
}

# --- no overlap: nothing qualifies for removal ---

@test "use_makeconf: no overlap between MAKE_USES and PROFILE — file unchanged" {
	printf 'USE=" foo"\n' > "${makefile}"
	MAKE_USES="foo"
	PROFILE=$'bar'
	local before
	before="$(cat "${makefile}")"
	use_makeconf
	run cat "${makefile}"
	assert_output "${before}"
}

@test "use_makeconf: flag in PROFILE only (not MAKE_USES) — not removed" {
	printf 'USE=" foo"\n' > "${makefile}"
	MAKE_USES="bar"
	PROFILE=$'foo'
	use_makeconf
	run grep 'foo' "${makefile}"
	assert_success
}

@test "use_makeconf: flag in MAKE_USES only (not PROFILE) — not removed" {
	printf 'USE=" foo bar"\n' > "${makefile}"
	MAKE_USES="foo bar"
	PROFILE=$'baz'
	use_makeconf
	run grep 'foo' "${makefile}"
	assert_success
}

# --- mixed PROFILE: multiple entries, only one is a duplicate ---

@test "use_makeconf: multiple PROFILE flags — only the duplicate is removed" {
	printf 'USE=" foo bar baz"\n' > "${makefile}"
	MAKE_USES="foo bar"
	PROFILE=$'foo\nbaz'
	use_makeconf
	# foo: in both MAKE_USES and PROFILE → removed
	run grep 'foo' "${makefile}"
	assert_failure
}

@test "use_makeconf: multiple PROFILE flags — non-overlapping flag preserved" {
	printf 'USE=" foo bar baz"\n' > "${makefile}"
	MAKE_USES="foo bar"
	PROFILE=$'foo\nbaz'
	use_makeconf
	# bar: in MAKE_USES but not in PROFILE → preserved
	run grep 'bar' "${makefile}"
	assert_success
}
