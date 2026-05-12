#!/usr/bin/env bats
# Unit tests for sort_passed_uses — takes a space-separated list of USE
# flags and deduplicates it, preserving the last defined state (on/off)
# for each flag.  A flag and its negation (-flag) are treated as the same
# slot; whichever appears last wins.

load 'test_helper'

setup() {
	load_portconf
}

# --- basic pass-through ---

@test "sort_passed_uses: empty input produces empty output" {
	result="$(sort_passed_uses "")"
	assert_equal "$result" ""
}

@test "sort_passed_uses: single flag unchanged" {
	result="$(sort_passed_uses "foo")"
	assert_equal "$result" "foo"
}

@test "sort_passed_uses: single negated flag unchanged" {
	result="$(sort_passed_uses "-foo")"
	assert_equal "$result" "-foo"
}

@test "sort_passed_uses: two distinct flags preserved" {
	result="$(sort_passed_uses "foo bar")"
	assert_equal "$result" "foo bar"
}

# --- last-wins deduplication ---

@test "sort_passed_uses: duplicate flag — last occurrence wins, moved to end" {
	result="$(sort_passed_uses "foo bar foo")"
	assert_equal "$result" "bar foo"
}

@test "sort_passed_uses: three occurrences — last wins" {
	result="$(sort_passed_uses "foo foo foo")"
	assert_equal "$result" "foo"
}

# --- negation handling ---

@test "sort_passed_uses: positive then negated — negation wins" {
	result="$(sort_passed_uses "foo -foo")"
	assert_equal "$result" "-foo"
}

@test "sort_passed_uses: negated then positive — positive wins" {
	result="$(sort_passed_uses "-foo foo")"
	assert_equal "$result" "foo"
}

@test "sort_passed_uses: negation in the middle — last state wins" {
	result="$(sort_passed_uses "foo -foo foo")"
	assert_equal "$result" "foo"
}

@test "sort_passed_uses: negation slot collapsed across mixed list" {
	result="$(sort_passed_uses "a -b b c -a")"
	assert_equal "$result" "b c -a"
}

# --- wildcard handling ---
# sort_passed_uses uses 'for opt in ${1}' (unquoted), so globs in the input
# expand in the caller's context.  Tests that involve '*' must disable globbing.

@test "sort_passed_uses: wildcard '*' flag passed through (set -f required)" {
	set -f
	result="$(sort_passed_uses "* foo")"
	set +f
	assert_equal "$result" "* foo"
}
