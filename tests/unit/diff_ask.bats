#!/usr/bin/env bats
# Tests for diff_ask — the change-review/apply helper.
#
# diff_ask FILE TMPFILE computes a colourised diff and, depending on the
# globals `yes` and `PRETEND`:
#   yes=1, PRETEND=""   → auto-apply  (mv TMPFILE → FILE; chmod 0644)
#   yes="", PRETEND=1   → discard     (rm TMPFILE; FILE unchanged)
#   both empty          → interactive prompt (read x; Yes/No/reprompt)
#
# When the files are identical diff_ask is a no-op (removes TMPFILE).
#
# NOTE on the interactive Apply branch: it's gated on `${UID}` == 0.  Non-
# root callers hit the "you are !root --> go away!" arm and exit 1.  The
# interactive tests below assert that behaviour rather than mocking UID.

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

# --- interactive: yes="" PRETEND="" — reads from stdin -----------------

@test "diff_ask: interactive 'No' — original unchanged" {
	printf '%s\n' "old content" > "${_f1}"
	printf '%s\n' "new content" > "${_f2}"
	yes=""; PRETEND=""
	diff_ask "${_f1}" "${_f2}" <<< "No"
	run cat "${_f1}"
	assert_output 'old content'
}

@test "diff_ask: interactive 'No' — tmp file removed" {
	printf '%s\n' "old content" > "${_f1}"
	printf '%s\n' "new content" > "${_f2}"
	yes=""; PRETEND=""
	diff_ask "${_f1}" "${_f2}" <<< "No"
	[[ ! -f "${_f2}" ]]
}

@test "diff_ask: interactive 'n' (lowercase short) — original unchanged" {
	printf '%s\n' "old" > "${_f1}"
	printf '%s\n' "new" > "${_f2}"
	yes=""; PRETEND=""
	diff_ask "${_f1}" "${_f2}" <<< "n"
	run cat "${_f1}"
	assert_output 'old'
}

@test "diff_ask: interactive 'Yes' as non-root — exits 1 with go-away message" {
	# The Yes case-arm runs `mv` only when UID==0; otherwise prints
	# "you are !root --> go away!" and exits 1.  This test exercises
	# the gating branch and so only applies when the running user is
	# NOT root.  CI on gentoo/stage3:latest runs as root by default →
	# the gating branch is unreachable → skip.
	(( UID == 0 )) && skip "running as root; non-root branch unreachable"
	printf '%s\n' "old" > "${_f1}"
	printf '%s\n' "new" > "${_f2}"
	yes=""; PRETEND=""
	# diff_ask exits via `exit 1` inside the case; capture with run.
	run diff_ask "${_f1}" "${_f2}" <<< "Yes"
	[ "$status" -eq 1 ]
	[[ "${output}" == *'!root'* || "${output}" == *'go away'* ]]
}

@test "diff_ask: interactive 'Yes' as root — applies change, file replaced" {
	# Complement to the previous test.  When UID==0 the Yes case-arm
	# does mv + chmod 0644.  In CI on stage3:latest this is the actual
	# path that fires.  Skip on non-root hosts so dev runs don't get
	# a noisy skip.
	(( UID != 0 )) && skip "not running as root; mv-branch unreachable from this UID"
	printf '%s\n' "old" > "${_f1}"
	printf '%s\n' "new" > "${_f2}"
	yes=""; PRETEND=""
	diff_ask "${_f1}" "${_f2}" <<< "Yes"
	run cat "${_f1}"
	assert_output 'new'
}

@test "diff_ask: interactive bogus response then 'No' — reprompts and discards" {
	# Unknown responses fall through the * case-arm which reprompts.
	# Two-line stdin: bogus is rejected, second "No" breaks out cleanly.
	printf '%s\n' "old" > "${_f1}"
	printf '%s\n' "new" > "${_f2}"
	yes=""; PRETEND=""
	run diff_ask "${_f1}" "${_f2}" <<< $'maybe\nNo\n'
	[ "$status" -eq 0 ]
	# Reprompt message must have been emitted for the bogus input.
	[[ "${output}" == *"not understood"* ]]
	# Original file unchanged.
	run cat "${_f1}"
	assert_output 'old'
}
