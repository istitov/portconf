#!/usr/bin/env bats
# Tests for timestamp() — returns the maximum mtime (seconds since epoch)
# from a list of file arguments.
#
# Implementation: stat -c %Y "${@}" 2>/dev/null | sort | tail -n1 || true
#
# Key properties:
#   - returns the newest (highest) mtime regardless of argument order
#   - silently ignores non-existent files (stat errors go to /dev/null)
#   - returns empty when no file can be stat'd

load 'test_helper'

setup() {
	load_portconf
	_f1="$(mktemp)"
	_f2="$(mktemp)"
}

teardown() {
	rm -f "${_f1}" "${_f2}"
}

@test "timestamp: single file — returns its mtime" {
	touch -d '2020-06-15 12:00:00' "${_f1}"
	local expected
	expected="$(stat -c %Y "${_f1}")"
	run timestamp "${_f1}"
	assert_output "${expected}"
}

@test "timestamp: two files — returns the max mtime" {
	touch -d '2020-01-01' "${_f1}"
	touch -d '2020-01-02' "${_f2}"
	local newer
	newer="$(stat -c %Y "${_f2}")"
	run timestamp "${_f1}" "${_f2}"
	assert_output "${newer}"
}

@test "timestamp: newer file first — still returns max (arg order irrelevant)" {
	touch -d '2020-01-01' "${_f1}"
	touch -d '2020-01-02' "${_f2}"
	local newer
	newer="$(stat -c %Y "${_f2}")"
	run timestamp "${_f2}" "${_f1}"
	assert_output "${newer}"
}

@test "timestamp: non-existent file — returns empty" {
	run timestamp /nonexistent/file/does/not/exist
	assert_output ""
}

@test "timestamp: mix of existing and non-existing — returns existing file mtime" {
	touch -d '2020-03-01' "${_f1}"
	local mt
	mt="$(stat -c %Y "${_f1}")"
	run timestamp "${_f1}" /nonexistent
	assert_output "${mt}"
}
