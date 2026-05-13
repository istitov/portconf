#!/usr/bin/env bats
# Tests for sort_uses (invoked via sort_use_file) — the USE-flag sorting and
# deduplication pass that normalises package.use entries.
#
# sort_use_file finds package.use (file or directory), sets the external
# `file` variable, then calls sort_uses which:
#   - collects all flags for each atom across duplicate lines
#   - calls sort_passed_uses to resolve conflicts (last occurrence wins)
#   - strips whole-line comments
#   - preserves inline comments
#   - removes atom entries with no remaining flags
#   - sorts output lines alphabetically
#
# Tests use yes=1 (auto-apply) so diff_ask commits every change.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# helper
write_use() { printf '%s\n' "$@" > "${TEST_PORT_ETC}/package.use"; }

# --- unchanged content ---

@test "sort_uses: single atom single flag — file unchanged" {
	write_use "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uses: single atom multiple flags — flags preserved" {
	write_use "app-misc/foo bar baz"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar baz"
}

@test "sort_uses: two distinct atoms — both lines preserved" {
	write_use "app-misc/foo bar" "dev-libs/baz qux"
	sort_use_file
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "2"
	run grep "app-misc/foo bar" "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
	run grep "dev-libs/baz qux" "${TEST_PORT_ETC}/package.use"
	assert_output "dev-libs/baz qux"
}

# --- deduplication ---

@test "sort_uses: duplicate identical lines — collapsed to one" {
	write_use "app-misc/foo bar" "app-misc/foo bar"
	sort_use_file
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "1"
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uses: conflicting flags — last occurrence wins (pos then neg)" {
	write_use "app-misc/foo bar" "app-misc/foo -bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo -bar"
}

@test "sort_uses: conflicting flags — last occurrence wins (neg then pos)" {
	write_use "app-misc/foo -bar" "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uses: three duplicate lines — last state preserved" {
	write_use "app-misc/foo bar" "app-misc/foo -bar" "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

# --- comments ---

@test "sort_uses: whole-line comment stripped" {
	write_use "# comment" "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uses: inline comment preserved" {
	write_use "app-misc/foo bar # keep this"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar # keep this"
}
