#!/usr/bin/env bats
# Tests for empty_files and backup_files — the housekeeping passes that
# remove zero-byte/comment-only files and stale backup files from PORT_ETC.
#
# empty_files: iterates all files under PORT_ETC; calls remove_ask on any
#   that are zero bytes or consist entirely of comment lines.
#
# backup_files: iterates files matching *~, *.bak, *.old under PORT_ETC;
#   calls remove_ask on each.
#
# remove_ask with yes=1 removes the file immediately (no prompt).
# remove_ask with PRETEND=1 is a no-op (file untouched).

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# --- empty_files ---

@test "empty_files: zero-byte file removed (yes=1)" {
	touch "${TEST_PORT_ETC}/package.use"
	empty_files
	[[ ! -f "${TEST_PORT_ETC}/package.use" ]]
}

@test "empty_files: comment-only file removed (yes=1)" {
	printf '%s\n' "# only a comment" > "${TEST_PORT_ETC}/package.use"
	empty_files
	[[ ! -f "${TEST_PORT_ETC}/package.use" ]]
}

@test "empty_files: file with real content kept" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	empty_files
	[[ -f "${TEST_PORT_ETC}/package.use" ]]
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "empty_files: PRETEND=1 — zero-byte file not removed" {
	touch "${TEST_PORT_ETC}/package.use"
	yes=""; PRETEND="1"
	empty_files
	[[ -f "${TEST_PORT_ETC}/package.use" ]]
}

@test "empty_files: mixed content and comment-only files — only empty removed" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	printf '%s\n' "# only comment" > "${TEST_PORT_ETC}/package.mask"
	empty_files
	[[ -f "${TEST_PORT_ETC}/package.use" ]]
	[[ ! -f "${TEST_PORT_ETC}/package.mask" ]]
}

# --- backup_files ---

@test "backup_files: tilde file removed (yes=1)" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use~"
	backup_files
	[[ ! -f "${TEST_PORT_ETC}/package.use~" ]]
}

@test "backup_files: .bak file removed (yes=1)" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use.bak"
	backup_files
	[[ ! -f "${TEST_PORT_ETC}/package.use.bak" ]]
}

@test "backup_files: .old file removed (yes=1)" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use.old"
	backup_files
	[[ ! -f "${TEST_PORT_ETC}/package.use.old" ]]
}

@test "backup_files: regular package.use not touched" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	backup_files
	[[ -f "${TEST_PORT_ETC}/package.use" ]]
}

@test "backup_files: PRETEND=1 — .bak file not removed" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use.bak"
	yes=""; PRETEND="1"
	backup_files
	[[ -f "${TEST_PORT_ETC}/package.use.bak" ]]
}
