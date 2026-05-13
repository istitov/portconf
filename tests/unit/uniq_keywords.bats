#!/usr/bin/env bats
# Tests for uniq_keywords (via sort_keys) — the keyword deduplication pass
# for package.keywords / package.accept_keywords.
#
# sort_keys uses sort_passed_uses for conflict resolution (same last-wins
# semantics as sort_uses, but keyword tilde prefixes are not treated as
# negations — "~amd64" and "amd64" are independent tokens).
#
# Extra behaviour specific to keywords:
#   - atom with no keywords in the file → assigned "~${ARCH}" as default
#   - whole-line comments stripped
#   - sort_keys also calls stupid_keywords which prunes profile-defined
#     keywords; that pass is stubbed out here so tests are host-independent.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	# Stub out the profile-keyword pruner.  The real stupid_keywords calls
	# `eix --print ACCEPT_KEYWORDS` and removes matching keywords, which
	# makes test outcomes depend on the host profile.
	stupid_keywords() { :; }
}

teardown() {
	teardown_test_portage
}

# --- unchanged content ---

@test "uniq_keywords: single atom single keyword — unchanged" {
	printf '%s\n' "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	uniq_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
}

@test "uniq_keywords: two distinct atoms — both preserved" {
	printf '%s\n' "app-misc/foo ~amd64" "dev-libs/baz ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	uniq_keywords
	run grep -c "." "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "2"
	run grep "app-misc/foo ~amd64" "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
	run grep "dev-libs/baz ~amd64" "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "dev-libs/baz ~amd64"
}

# --- deduplication ---

@test "uniq_keywords: duplicate identical lines — collapsed to one" {
	printf '%s\n' "app-misc/foo ~amd64" "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	uniq_keywords
	run grep -c "." "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "1"
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
}

@test "uniq_keywords: conflicting keyword tokens — last occurrence wins" {
	# sort_passed_uses treats -amd64 as the negation of amd64
	printf '%s\n' "app-misc/foo amd64" "app-misc/foo -amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	uniq_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo -amd64"
}

# --- default keyword ---

@test "uniq_keywords: atom without keyword — gets ~ARCH added" {
	printf '%s\n' "app-misc/foo" > "${TEST_PORT_ETC}/package.accept_keywords"
	uniq_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~${ARCH}"
}

# --- comment handling ---

@test "uniq_keywords: whole-line comment stripped" {
	printf '%s\n' "# comment" "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	uniq_keywords
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
}

@test "uniq_keywords: works on package.keywords too" {
	printf '%s\n' "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.keywords"
	uniq_keywords
	run cat "${TEST_PORT_ETC}/package.keywords"
	assert_output "app-misc/foo ~amd64"
}
