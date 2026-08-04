#!/usr/bin/env bats
# Tests for repo_fix and rm_repo_fix.
#
# repo_fix: for each overlay in PORTDIR_OVERLAY, if the overlay contains
#   category directories not already listed in PORTDIR/profiles/categories,
#   and the overlay has no profiles/categories of its own, create one in force
#   mode or synthesize a symlink-backed scratch overlay in pretend mode.
#
# rm_repo_fix: remove temporary paths and restore the original overlay list.
#
# Category directories are identified as entries matching *-* or "virtual".

load 'test_helper'

setup() {
	load_portconf
	TEST_PORTDIR="$(mktemp -d)"
	TEST_OVERLAY="$(mktemp -d)"
	mkdir -p "${TEST_PORTDIR}/profiles"
	# Main portage tree has app-misc and dev-libs
	printf 'app-misc\ndev-libs\n' > "${TEST_PORTDIR}/profiles/categories"
	PORTDIR="${TEST_PORTDIR}"
	PORTDIR_OVERLAY=""
	tmp_categories=""
}

teardown() {
	rm -rf "${TEST_PORTDIR}" "${TEST_OVERLAY}"
}

# --- no overlay configured ---

@test "repo_fix: PORTDIR_OVERLAY empty — no-op" {
	PORTDIR_OVERLAY=""
	repo_fix
	[[ -z "${tmp_categories}" ]]
}

# --- overlay category already in portage ---

@test "repo_fix: overlay only has known categories — no profiles/categories created" {
	mkdir -p "${TEST_OVERLAY}/app-misc"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	repo_fix
	[[ ! -f "${TEST_OVERLAY}/profiles/categories" ]]
}

# --- overlay has a new category ---

@test "repo_fix: overlay has new category — profiles/categories created" {
	mkdir -p "${TEST_OVERLAY}/my-overlay"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	repo_fix
	[[ -f "${TEST_OVERLAY}/profiles/categories" ]]
}

@test "repo_fix: new category written to profiles/categories" {
	mkdir -p "${TEST_OVERLAY}/my-overlay"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	repo_fix
	run grep "my-overlay" "${TEST_OVERLAY}/profiles/categories"
	assert_success
}

@test "repo_fix: created paths registered in tmp_categories" {
	mkdir -p "${TEST_OVERLAY}/my-overlay"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	repo_fix
	[[ -n "${tmp_categories}" ]]
}

# --- overlay already has its own profiles/categories ---

@test "repo_fix: overlay already has profiles/categories — not overwritten" {
	mkdir -p "${TEST_OVERLAY}/my-overlay" "${TEST_OVERLAY}/profiles"
	printf 'my-overlay\n' > "${TEST_OVERLAY}/profiles/categories"
	local mtime_before
	mtime_before="$(stat -c %Y "${TEST_OVERLAY}/profiles/categories")"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	repo_fix
	run stat -c %Y "${TEST_OVERLAY}/profiles/categories"
	assert_output "${mtime_before}"
	[[ -z "${tmp_categories}" ]]
}

@test "repo_fix: pretend uses a scratch overlay view with equivalent categories" {
	mkdir -p "${TEST_OVERLAY}/my-overlay"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	local original="${PORTDIR_OVERLAY}" shadow
	_set_action_mode pretend

	repo_fix

	[[ ! -e "${TEST_OVERLAY}/profiles/categories" ]]
	[[ "${PORTDIR_OVERLAY}" != "${original}" ]]
	shadow="${PORTDIR_OVERLAY}"
	[[ -f "${shadow}/profiles/categories" ]]
	grep -qxF 'my-overlay' "${shadow}/profiles/categories"
	[[ -d "${shadow}/my-overlay" ]]
	rm_repo_fix
	[[ "${PORTDIR_OVERLAY}" == "${original}" ]]
}

@test "eix_check: pretend exposes scratch categories only during cache generation" {
	mkdir -p "${TEST_OVERLAY}/my-overlay"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	local original="${PORTDIR_OVERLAY}" captured
	captured="$(mktemp)"
	eix() { printf 'eix test\n'; }
	eix-update() { cat "${PORTDIR_OVERLAY}/profiles/categories" > "${captured}"; }
	_set_action_mode pretend

	eix_check

	grep -qxF 'my-overlay' "${captured}"
	[[ ! -e "${TEST_OVERLAY}/profiles/categories" ]]
	[[ "${PORTDIR_OVERLAY}" == "${original}" ]]
	rm -f "${captured}"
}

# --- rm_repo_fix ---

@test "rm_repo_fix: removes files registered in tmp_categories" {
	local f
	f="$(mktemp)"
	tmp_categories="${f}"
	rm_repo_fix
	[[ ! -e "${f}" ]]
}

@test "rm_repo_fix: tmp_categories empty — no-op" {
	tmp_categories=""
	run rm_repo_fix
	assert_success
}

@test "rm_repo_fix: cleans up what repo_fix created" {
	mkdir -p "${TEST_OVERLAY}/my-overlay"
	PORTDIR_OVERLAY="${TEST_OVERLAY}"
	repo_fix
	[[ -f "${TEST_OVERLAY}/profiles/categories" ]]
	rm_repo_fix
	[[ ! -f "${TEST_OVERLAY}/profiles/categories" ]]
}
