#!/usr/bin/env bats
# Tests for file-based operations (rm_comments, rm_all_comments) using a
# scratch portage directory.  PORT_ETC is redirected to a temp dir so no
# real /etc/portage files are touched.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# helper: write a package.use file under TEST_PORT_ETC
write_package_use() {
	printf '%s\n' "$@" > "${TEST_PORT_ETC}/package.use"
}

# --- rm_comments ---

@test "rm_comments: removes whole-line comment lines" {
	write_package_use "# leading comment" "sys-kernel/linux-firmware -savedconfig" "# another comment" "app-arch/zip -natspec"
	rm_comments
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf 'sys-kernel/linux-firmware -savedconfig\napp-arch/zip -natspec')"
}

@test "rm_comments: preserves inline comments" {
	write_package_use "app-arch/zip -natspec # inline note"
	rm_comments
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-arch/zip -natspec # inline note"
}

@test "rm_comments: file with only comments becomes empty" {
	write_package_use "# comment only" "# another comment"
	rm_comments
	# rm_comments strips the comment lines; the resulting empty file is left
	# in place — removal of empty files is a separate empty_files() pass.
	[[ ! -s "${TEST_PORT_ETC}/package.use" ]]
}

@test "rm_comments: file with no comments is left unchanged" {
	write_package_use "sys-kernel/linux-firmware -savedconfig" "app-arch/zip -natspec"
	rm_comments
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf 'sys-kernel/linux-firmware -savedconfig\napp-arch/zip -natspec')"
}

# --- rm_all_comments ---

@test "rm_all_comments: strips inline comments" {
	write_package_use "sys-kernel/linux-firmware -savedconfig # keep firmware working" "app-arch/zip -natspec"
	rm_all_comments
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf 'sys-kernel/linux-firmware -savedconfig\napp-arch/zip -natspec')"
}

@test "rm_all_comments: strips whole-line comments" {
	write_package_use "# whole line" "app-arch/zip -natspec"
	rm_all_comments
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-arch/zip -natspec"
}

@test "rm_all_comments: trailing whitespace after inline comment is removed" {
	write_package_use "app-arch/zip -natspec   # note with spaces"
	rm_all_comments
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-arch/zip -natspec"
}
