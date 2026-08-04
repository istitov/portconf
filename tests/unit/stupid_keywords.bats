#!/usr/bin/env bats
# Tests for stupid_keywords -- drop per-package keywords already granted by the
# system ACCEPT_KEYWORDS or by a parent wildcard (cat/* or */*) entry.
#
# stupid_keywords reads its $1 (source) and edits $2 (a copy) in place, and reads
# the system keywords from `eix --print ACCEPT_KEYWORDS` (stubbed per test via
# SK_SYS).  Regressions guarded here:
#   * the system-redundant check used to live inside the parent-wildcard loop,
#     so it never fired for a package with no parent entry;
#   * `cut -d#` without -s returned the whole keyword line as a bogus "comment"
#     for a comment-less entry, sending it down a branch whose grep never matched
#     (the redundant keyword was left in place).

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
	rm -f "${SK_IN:-}" "${SK_OUT:-}"
}

# Run stupid_keywords over the given lines with SK_SYS as the system keywords.
_run_sk() {  # $1 = system ACCEPT_KEYWORDS, rest = package.accept_keywords lines
	SK_SYS="$1"; shift
	eix() { printf '%s\n' "${SK_SYS}"; }
	SK_IN="$(mktemp)"; SK_OUT="$(mktemp)"
	printf '%s\n' "$@" > "${SK_IN}"
	cp "${SK_IN}" "${SK_OUT}"
	stupid_keywords "${SK_IN}" "${SK_OUT}"
}

@test "stupid_keywords: drops a system-redundant keyword with no parent wildcard" {
	# The old code checked key == system-KEY only inside the parent loop, so with
	# no cat-test/* entry the redundant ~amd64 survived.
	_run_sk "~amd64" 'cat-test/a ~amd64 ~x86'
	run cat "${SK_OUT}"
	assert_output 'cat-test/a ~x86'
}

@test "stupid_keywords: drops a keyword granted by a parent wildcard entry" {
	_run_sk "~amd64" 'cat-test/* ~arm64' 'cat-test/a ~arm64 ~x86'
	run cat "${SK_OUT}"
	[[ "${output}" == *'cat-test/a ~x86'* ]]
	# the wildcard parent itself is left alone
	[[ "${output}" == *'cat-test/* ~arm64'* ]]
}

@test "stupid_keywords: a non-redundant keyword is untouched" {
	_run_sk "~amd64" 'cat-test/a ~x86'
	run cat "${SK_OUT}"
	assert_output 'cat-test/a ~x86'
}

@test "stupid_keywords: exact removal preserves a substring-sharing keyword" {
	_run_sk "amd64" 'cat-test/a amd64 ~amd64'
	run cat "${SK_OUT}"
	assert_output 'cat-test/a ~amd64'
}

@test "stupid_keywords: option-leading and wildcard keywords are removed literally" {
	_run_sk "-*" 'cat-test/a -* ~testarch'
	run cat "${SK_OUT}"
	assert_output 'cat-test/a ~testarch'

	_run_sk "**" 'cat-test/a ** ~testarch'
	run cat "${SK_OUT}"
	assert_output 'cat-test/a ~testarch'
}
