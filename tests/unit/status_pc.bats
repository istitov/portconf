#!/usr/bin/env bats
# Tests for the end-of-run status line.
#
# diff_ask maintains three globals as it processes each file:
#   _changes_seen     -- set to 1 once any mutating op (diff_ask) ran at all
#   _changes_found    -- count of files that had a pending diff
#   _changes_applied  -- count of files actually written
# _status_pc reads those (plus PRETEND) after the dispatch loop and prints one
# summary line so a mutating invocation is never silent.  It is purely additive:
# it speaks only when _changes_seen is set, and re-returns the incoming $? so it
# never changes the exit status.  Colours collapse to empty under bats (stdout
# is not a tty), so the asserted lines are plain text.

load 'test_helper'

setup() {
	load_portconf
	export TERM="${TERM:-dumb}"
	_f1="$(mktemp)"
	_f2="$(mktemp)"
}

teardown() {
	rm -f "${_f1}" "${_f2}"
}

# --- wiring: diff_ask feeds the counters ------------------------------------

@test "wiring: apply bumps found + applied and sets seen" {
	printf '%s\n' "cat-test/a x" > "${_f1}"
	printf '%s\n' "cat-test/a y" > "${_f2}"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}" >/dev/null
	[ "${_changes_seen}" = "1" ]
	[ "${_changes_found}" -eq 1 ]
	[ "${_changes_applied}" -eq 1 ]
}

@test "wiring: pretend bumps found but not applied" {
	printf '%s\n' "cat-test/a x" > "${_f1}"
	printf '%s\n' "cat-test/a y" > "${_f2}"
	yes=""; PRETEND="1"
	diff_ask "${_f1}" "${_f2}" >/dev/null
	[ "${_changes_found}" -eq 1 ]
	[ "${_changes_applied}" -eq 0 ]
}

@test "wiring: identical files set seen but leave found at 0" {
	printf '%s\n' "cat-test/a x" > "${_f1}"
	printf '%s\n' "cat-test/a x" > "${_f2}"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}" >/dev/null
	[ "${_changes_seen}" = "1" ]
	[ "${_changes_found}" -eq 0 ]
	[ "${_changes_applied}" -eq 0 ]
}

@test "wiring: counters accumulate across calls" {
	printf '%s\n' "cat-test/a x" > "${_f1}"; printf '%s\n' "cat-test/a y" > "${_f2}"
	yes="1"; PRETEND=""
	diff_ask "${_f1}" "${_f2}" >/dev/null
	printf '%s\n' "cat-test/b x" > "${_f1}"; printf '%s\n' "cat-test/b y" > "${_f2}"
	diff_ask "${_f1}" "${_f2}" >/dev/null
	[ "${_changes_found}" -eq 2 ]
	[ "${_changes_applied}" -eq 2 ]
}

# --- _status_pc message branches --------------------------------------------

@test "_status_pc: silent when no mutating op ran (_changes_seen empty)" {
	# A non-mutating run prints nothing.  (Status is the *incoming* $?, which
	# _status_pc passes through transparently -- exercised in its own test
	# below -- so here we assert only the silence.)
	_changes_seen=""; _changes_found=0; _changes_applied=0; PRETEND=""
	run _status_pc
	assert_output ""
}

@test "_status_pc: all applied -> 'updated N file(s)'" {
	_changes_seen=1; _changes_found=3; _changes_applied=3; PRETEND=""
	run _status_pc
	assert_output "portconf: updated 3 file(s)"
}

@test "_status_pc: partial apply -> 'updated N, M still pending'" {
	_changes_seen=1; _changes_found=5; _changes_applied=2; PRETEND=""
	run _status_pc
	assert_output "portconf: updated 2 file(s), 3 still pending (re-run with -y)"
}

@test "_status_pc: pending, none applied -> 're-run with -y'" {
	_changes_seen=1; _changes_found=4; _changes_applied=0; PRETEND=""
	run _status_pc
	assert_output "portconf: 4 file(s) have pending changes, none applied (re-run with -y)"
}

@test "_status_pc: pretend with pending -> 'would change, nothing written'" {
	_changes_seen=1; _changes_found=8; _changes_applied=0; PRETEND="1"
	run _status_pc
	assert_output "portconf: pretend (-p), 8 file(s) would change, nothing written"
}

@test "_status_pc: pretend with nothing found -> 'no changes needed'" {
	_changes_seen=1; _changes_found=0; _changes_applied=0; PRETEND="1"
	run _status_pc
	assert_output "portconf: no changes needed"
}

@test "_status_pc: ran but nothing to change -> 'no changes needed'" {
	_changes_seen=1; _changes_found=0; _changes_applied=0; PRETEND=""
	run _status_pc
	assert_output "portconf: no changes needed"
}

# --- exit-code transparency -------------------------------------------------

@test "_status_pc: re-returns the incoming exit status (non-zero preserved)" {
	_changes_seen=1; _changes_found=1; _changes_applied=1; PRETEND=""
	# Seed $?=3 then confirm _status_pc hands it back unchanged.  bats runs
	# test bodies under set -e, where a bare `(exit 3)` would abort the test;
	# disable errexit just for the seed so we actually reach the assertion.
	set +e
	(exit 3); _status_pc >/dev/null; local rc=$?
	set -e
	[ "$rc" -eq 3 ]
}
