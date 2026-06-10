#!/usr/bin/env bats
# Tests for _mktemp / _cleanup.
#
# _mktemp is almost always called as `f="$(_mktemp)"` -- a command-substitution
# subshell.  The previous array tracker (_tmpfiles+=("$f")) therefore mutated
# only the subshell's private copy; the parent array stayed empty and the
# EXIT-trap _cleanup removed nothing -- every temp file leaked.  Tracking now
# appends to a file (_tmpfile_list), which survives the subshell, so _cleanup
# reads every path back in the parent.

load 'test_helper'

setup() {
	load_portconf
}

@test "_mktemp: a \$()-captured temp file is created and recorded" {
	local f
	f="$(_mktemp)"
	[ -n "${f}" ]
	[ -f "${f}" ]
	# The path was recorded despite the command-substitution subshell -- this
	# is exactly what the old array tracker silently failed to do.
	run grep -qxF "${f}" "${_tmpfile_list}"
	assert_success
}

@test "_mktemp: _cleanup removes every \$()-captured temp file" {
	local a b
	a="$(_mktemp)"
	b="$(_mktemp)"
	[ -f "${a}" ]
	[ -f "${b}" ]
	_cleanup
	[ ! -f "${a}" ]
	[ ! -f "${b}" ]
}

@test "_mktemp: _cleanup is a safe no-op when nothing was allocated" {
	: > "${_tmpfile_list}"
	_cleanup
}
