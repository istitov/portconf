#!/usr/bin/env bats
# Tests for diff_ask — the change-review/apply helper.
#
# diff_ask FILE TMPFILE computes a colourised diff and, depending on the
# globals `yes` and `PRETEND`:
#   yes=1, PRETEND=""   → auto-apply  (mv TMPFILE → FILE; chmod 0644)
#   yes="", PRETEND=1   → discard     (rm TMPFILE; FILE unchanged)
#   both empty          → interactive prompt (not tested here)
#
# When the files are identical diff_ask is a no-op (removes TMPFILE).

load 'test_helper'

setup() {
	load_portconf
	# diff_ask writes coloured output; silence terminal-capability errors
	# in environments where tput is not connected to a real terminal.
	export TERM="${TERM:-dumb}"
	_f1="$(mktemp)"
	_f2="$(mktemp)"
}

teardown() {
	rm -f "${_f1}" "${_f2}"
}

# helper: populate both files
_write_files() {
	printf '%s\n' "$@" > "${_f1}"
	printf '%s\n' "$@" > "${_f2}"
}

# --- identical files ---

@test "diff_ask: identical files — returns 0, original unchanged" {
	_write_files "app-misc/foo bar" "app-misc/baz qux"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}"
	run cat "${_f1}"
	assert_output "$(printf 'app-misc/foo bar\napp-misc/baz qux')"
	[[ ! -f "${_f2}" ]]
}

@test "diff_ask: identical files — tmp file removed" {
	_write_files "app-misc/foo bar"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}"
	[[ ! -f "${_f2}" ]]
}

# --- yes=1 auto-apply ---

@test "diff_ask: yes=1 — applies change, original gets new content" {
	printf '%s\n' "app-misc/foo bar" > "${_f1}"
	printf '%s\n' "app-misc/foo baz" > "${_f2}"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}"
	run cat "${_f1}"
	assert_output "app-misc/foo baz"
}

@test "diff_ask: yes=1 — tmp file consumed after apply" {
	printf '%s\n' "app-misc/foo bar" > "${_f1}"
	printf '%s\n' "app-misc/foo baz" > "${_f2}"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}"
	[[ ! -f "${_f2}" ]]
}

@test "diff_ask: yes=1 — addition of new line" {
	printf '%s\n' "app-misc/foo bar" > "${_f1}"
	printf '%s\n' "app-misc/foo bar" "app-misc/baz qux" > "${_f2}"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}"
	run cat "${_f1}"
	assert_output "$(printf 'app-misc/foo bar\napp-misc/baz qux')"
}

@test "diff_ask: yes=1 — deletion of a line" {
	printf '%s\n' "app-misc/foo bar" "app-misc/baz qux" > "${_f1}"
	printf '%s\n' "app-misc/baz qux" > "${_f2}"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}"
	run cat "${_f1}"
	assert_output "app-misc/baz qux"
}

# --- PRETEND=1 discard ---

@test "diff_ask: PRETEND=1 — original unchanged" {
	printf '%s\n' "app-misc/foo bar" > "${_f1}"
	printf '%s\n' "app-misc/foo baz" > "${_f2}"
	yes=""; PRETEND="1"
	diff_ask "${_f1}" "${_f2}"
	run cat "${_f1}"
	assert_output "app-misc/foo bar"
}

@test "diff_ask: PRETEND=1 — tmp file discarded" {
	printf '%s\n' "app-misc/foo bar" > "${_f1}"
	printf '%s\n' "app-misc/foo baz" > "${_f2}"
	yes=""; PRETEND="1"
	diff_ask "${_f1}" "${_f2}"
	[[ ! -f "${_f2}" ]]
}
