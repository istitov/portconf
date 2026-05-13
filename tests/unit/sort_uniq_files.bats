#!/usr/bin/env bats
# Tests for sort_uniq_files — the general-purpose package.* deduplicator.
#
# sort_uniq_files finds every package.* file (excluding ~/*.bak backups)
# under PORT_ETC and, for each:
#   - collects all flag/keyword tokens for each atom across duplicate lines
#   - joins them (no conflict resolution — unlike sort_uses, both sides
#     of a +flag/-flag pair are kept)
#   - strips whole-line comment lines
#   - removes trailing whitespace and empty lines
#   - sorts lines alphabetically (sort -u)
#   - calls diff_ask to apply or discard the result
#
# Note: this is distinct from sort_use_file/sort_uses which does resolve
# +flag/-flag conflicts via sort_passed_uses.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# --- unchanged content ---

@test "sort_uniq_files: single atom single flag — unchanged" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uniq_files: two distinct atoms — both preserved" {
	printf '%s\n' "app-misc/foo bar" "dev-libs/baz qux" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "2"
	run grep "app-misc/foo bar" "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
	run grep "dev-libs/baz qux" "${TEST_PORT_ETC}/package.use"
	assert_output "dev-libs/baz qux"
}

@test "sort_uniq_files: flag-less atom (package.mask style) — preserved" {
	printf '%s\n' "app-misc/foo" > "${TEST_PORT_ETC}/package.mask"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.mask"
	assert_output "app-misc/foo"
}

@test "sort_uniq_files: processes package.accept_keywords" {
	printf '%s\n' "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
}

# --- deduplication ---

@test "sort_uniq_files: duplicate identical lines — collapsed to one" {
	printf '%s\n' "app-misc/foo bar" "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "1"
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uniq_files: same atom different flags — merged onto one line" {
	printf '%s\n' "app-misc/foo bar" "app-misc/foo baz" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar baz"
}

@test "sort_uniq_files: conflicting flags — both retained (no conflict resolution)" {
	printf '%s\n' "app-misc/foo bar" "app-misc/foo -bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar -bar"
}

# --- comment handling ---

@test "sort_uniq_files: whole-line comment stripped" {
	printf '%s\n' "# comment" "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}
