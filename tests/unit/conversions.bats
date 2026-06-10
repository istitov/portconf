#!/usr/bin/env bats
# Tests for f_to_d and d_to_f — the flat-file ↔ per-category-directory
# conversion helpers.
#
# f_to_d: reads every package.* FILE under PORT_ETC, moves it to a temp
#   file, strips comments, then writes each line into a per-category
#   sub-file inside a new directory of the same name.
#
# d_to_f: reads every package.* DIRECTORY under PORT_ETC, concatenates
#   all per-category sub-files into a temp file, removes the directory,
#   and installs the flat file in its place.
#
# Requires: app-portage/portage-utils (qatom)

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# --- f_to_d ---

@test "f_to_d: flat package.use → directory exists" {
	printf '%s\n' "app-misc/foo bar baz" > "${TEST_PORT_ETC}/package.use"
	f_to_d
	[[ -d "${TEST_PORT_ETC}/package.use" ]]
}

@test "f_to_d: original file replaced by directory" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	f_to_d
	[[ ! -f "${TEST_PORT_ETC}/package.use" ]]
	[[ -d "${TEST_PORT_ETC}/package.use" ]]
}

@test "f_to_d: atom filed under its category" {
	printf '%s\n' "app-misc/foo bar baz" > "${TEST_PORT_ETC}/package.use"
	f_to_d
	run cat "${TEST_PORT_ETC}/package.use/app-misc"
	assert_output "app-misc/foo bar baz"
}

@test "f_to_d: atoms from two categories land in separate sub-files" {
	printf '%s\n' "app-misc/foo bar" "dev-libs/baz qux" > "${TEST_PORT_ETC}/package.use"
	f_to_d
	[[ -f "${TEST_PORT_ETC}/package.use/app-misc" ]]
	[[ -f "${TEST_PORT_ETC}/package.use/dev-libs" ]]
	run cat "${TEST_PORT_ETC}/package.use/app-misc"
	assert_output "app-misc/foo bar"
	run cat "${TEST_PORT_ETC}/package.use/dev-libs"
	assert_output "dev-libs/baz qux"
}

@test "f_to_d: comment lines are stripped" {
	printf '%s\n' "# comment" "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	f_to_d
	run cat "${TEST_PORT_ETC}/package.use/app-misc"
	assert_output "app-misc/foo bar"
}

@test "f_to_d: blank and comment lines do not create a junk 'unset' file" {
	# A blank line (or a comment blanked by the strip pass) yields an empty
	# atom whose qatom category is "<unset>" on modern portage-utils; it must
	# be skipped, not written to a file literally named "unset".
	printf '%s\n' "app-misc/foo bar" "" "# a comment" > "${TEST_PORT_ETC}/package.use"
	f_to_d
	[[ ! -e "${TEST_PORT_ETC}/package.use/unset" ]]
	run cat "${TEST_PORT_ETC}/package.use/app-misc"
	assert_output "app-misc/foo bar"
}

@test "f_to_d: skips existing directories" {
	mkdir -p "${TEST_PORT_ETC}/package.use"
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use/app-misc"
	f_to_d
	# directory left untouched
	[[ -d "${TEST_PORT_ETC}/package.use" ]]
	run cat "${TEST_PORT_ETC}/package.use/app-misc"
	assert_output "app-misc/foo bar"
}

# --- d_to_f ---

@test "d_to_f: directory → flat file exists" {
	mkdir -p "${TEST_PORT_ETC}/package.use"
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use/app-misc"
	d_to_f
	[[ -f "${TEST_PORT_ETC}/package.use" ]]
}

@test "d_to_f: original directory removed" {
	mkdir -p "${TEST_PORT_ETC}/package.use"
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use/app-misc"
	d_to_f
	[[ ! -d "${TEST_PORT_ETC}/package.use" ]]
}

@test "d_to_f: single sub-file content preserved" {
	mkdir -p "${TEST_PORT_ETC}/package.use"
	printf '%s\n' "app-misc/foo bar baz" > "${TEST_PORT_ETC}/package.use/app-misc"
	d_to_f
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar baz"
}

@test "d_to_f: a backslash in content is not mangled" {
	# Old inner `while read line` (no -r) ate the backslash -- "a\tb" became
	# "atb".  cat copies the sub-file verbatim.
	mkdir -p "${TEST_PORT_ETC}/package.use"
	printf '%s\n' 'app-misc/foo a\tb' > "${TEST_PORT_ETC}/package.use/app-misc"
	d_to_f
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output 'app-misc/foo a\tb'
}

@test "d_to_f: multiple sub-files concatenated" {
	mkdir -p "${TEST_PORT_ETC}/package.use"
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use/app-misc"
	printf '%s\n' "dev-libs/baz qux" > "${TEST_PORT_ETC}/package.use/dev-libs"
	d_to_f
	# both lines present (order is sort output of find)
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "2"
	run grep "app-misc/foo bar" "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
	run grep "dev-libs/baz qux" "${TEST_PORT_ETC}/package.use"
	assert_output "dev-libs/baz qux"
}

@test "d_to_f: skips existing flat files" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	d_to_f
	# file left untouched
	[[ -f "${TEST_PORT_ETC}/package.use" ]]
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

# --- roundtrip ---

@test "f_to_d then d_to_f: content survives roundtrip" {
	printf '%s\n' "app-misc/foo bar baz" "dev-libs/qux quux" > "${TEST_PORT_ETC}/package.use"
	f_to_d
	d_to_f
	[[ -f "${TEST_PORT_ETC}/package.use" ]]
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "2"
	run grep "app-misc/foo bar baz" "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar baz"
	run grep "dev-libs/qux quux" "${TEST_PORT_ETC}/package.use"
	assert_output "dev-libs/qux quux"
}
