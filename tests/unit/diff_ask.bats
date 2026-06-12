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
# NOTE on the interactive Apply branch: a "Yes" just tries to write the target
# (mv) and prints "Could not write ... (need root?)" + returns 1 if it can't —
# it no longer refuses non-root unconditionally or exit()s.  An EOF on the
# prompt (non-interactive stdin) fails loudly + returns 1 rather than silently
# discarding the pending change.

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

# --- hunk-filter only matches real headers, not header-shaped content ---

@test "diff_ask: a content line shaped like a hunk header doesn't corrupt the preview" {
	# `4d5` looks exactly like a diff hunk header.  The old unanchored filter
	# matched the CONTENT line `< 4d5` too and re-parsed it, running a stray
	# `seq < 4` that errored ("seq: invalid floating point argument") mid-
	# preview — under set -e that aborts the run.  The anchored filter ignores
	# content lines (diff prefixes them with `< `/`> `), so the change applies
	# cleanly and no seq error leaks.
	printf '%s\n' "keep" "4d5" > "${_f1}"
	printf '%s\n' "keep" "zzz" > "${_f2}"
	yes="1"; PRETEND=""
	run diff_ask "${_f1}" "${_f2}"
	[ "$status" -eq 0 ]
	[[ "${output}" != *"seq:"* ]]
	[[ "$(cat "${_f1}")" == "$(printf 'keep\nzzz')" ]]
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

@test "diff_ask: interactive 'Yes' on a writable target — applies (any UID)" {
	# A "Yes" now just tries the write; on a writable target (these mktemp
	# files are writable by the test user) it applies regardless of UID —
	# no more unconditional non-root "go away" + exit.
	printf '%s\n' "old" > "${_f1}"
	printf '%s\n' "new" > "${_f2}"
	yes=""; PRETEND=""
	diff_ask "${_f1}" "${_f2}" <<< "Yes"
	run cat "${_f1}"
	assert_output 'new'
}

@test "diff_ask: 'Yes' on an unwritable target — 'Could not write', returns 1, unchanged" {
	# When the write fails (mv denied by dir perms), report clearly + return
	# 1 instead of the old non-root "go away"/exit.  root bypasses directory
	# permissions, so this path only exercises as non-root.
	(( UID == 0 )) && skip "running as root; dir perms don't deny mv"
	local dir; dir="$(mktemp -d)"
	printf '%s\n' "old" > "${dir}/f"
	printf '%s\n' "new" > "${_f2}"
	chmod 0555 "${dir}"
	yes=""; PRETEND=""
	run diff_ask "${dir}/f" "${_f2}" <<< "Yes"
	chmod 0755 "${dir}"; rm -rf "${dir}"
	[ "$status" -eq 1 ]
	[[ "${output}" == *'Could not write'* ]]
}

@test "diff_ask: interactive no answer (EOF) — fails loudly, discards, file unchanged" {
	# Non-interactive stdin (EOF) used to silently drop the change; now it
	# prints 'No answer read' + returns 1, leaving the target untouched.
	printf '%s\n' "old" > "${_f1}"
	printf '%s\n' "new" > "${_f2}"
	yes=""; PRETEND=""
	run diff_ask "${_f1}" "${_f2}" </dev/null
	[ "$status" -eq 1 ]
	[[ "${output}" == *'No answer read'* ]]
	run cat "${_f1}"
	assert_output 'old'
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
