#!/usr/bin/env bats
# Tests for sort_keywords — the "keep only the last defined keyword" pass
# for package.keywords / package.accept_keywords.
#
# Contrast with uniq_keywords (sort_keys): that uses sort_passed_uses and
# combines all keyword tokens for an atom.  sort_keywords instead picks the
# very last keyword token found for each atom (via tail -n1), discarding all
# earlier ones.  Useful for collapsing a chain of overrides down to the final
# effective keyword.
#
# Falls back to "~${ARCH}" when an atom has no keyword in the file.
# stupid_keywords is stubbed so tests are host-profile-independent.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	stupid_keywords() { :; }
}

teardown() {
	teardown_test_portage
}

# --- unchanged content ---

@test "sort_keywords: single atom single keyword — unchanged" {
	printf '%s\n' "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
}

@test "sort_keywords: two distinct atoms — both preserved" {
	printf '%s\n' "app-misc/foo ~amd64" "dev-libs/baz **" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run grep -c "." "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "2"
	run grep "app-misc/foo ~amd64" "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
	run grep "dev-libs/baz \*\*" "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "dev-libs/baz **"
}

# --- last-keyword-wins (contrast with uniq_keywords which keeps all) ---

@test "sort_keywords: two keywords for same atom — last one kept" {
	printf '%s\n' "app-misc/foo ~amd64" "app-misc/foo **" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo **"
}

@test "sort_keywords: three keywords for same atom — only last one kept" {
	printf '%s\n' "app-misc/foo ~amd64" "app-misc/foo **" "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
}

@test "sort_keywords: headers from every duplicate atom are preserved" {
	printf '%s\n' \
		"# first reason" "app-misc/foo ~amd64" \
		"# second reason" "app-misc/foo **" \
		> "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "$(printf '# first reason\n# second reason\napp-misc/foo **')"
}

@test "sort_keywords: inline annotations from every duplicate are preserved" {
	printf '%s\n' \
		"app-misc/foo ~amd64 # first reason" \
		"app-misc/foo ** # second reason" \
		> "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "$(printf '# first reason\n# second reason\napp-misc/foo **')"
}

# --- default keyword ---

@test "sort_keywords: atom without keyword — gets ~ARCH added" {
	printf '%s\n' "app-misc/foo" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~${ARCH}"
}

# --- comment handling ---

@test "sort_keywords: header comment preserved with atom" {
	printf '%s\n' "# pin ~amd64 until upstream cuts a stable" "app-misc/foo ~amd64" \
		> "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "$(printf '# pin ~amd64 until upstream cuts a stable\napp-misc/foo ~amd64')"
}

@test "sort_keywords: trailing comments at EOF preserved" {
	printf '%s\n' "app-misc/foo ~amd64" "# trailing note" \
		> "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "$(printf 'app-misc/foo ~amd64\n# trailing note')"
}

@test "sort_keywords: inline comment preserved" {
	printf '%s\n' "app-misc/foo ~amd64 # testing" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64 # testing"
}

@test "sort_keywords: works on package.keywords too" {
	printf '%s\n' "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.keywords"
	sort_keywords
	run cat "${TEST_PORT_ETC}/package.keywords"
	assert_output "app-misc/foo ~amd64"
}
