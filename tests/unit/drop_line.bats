#!/usr/bin/env bats
# Tests for _drop_line — the literal-string line remover that replaced the
# fragile deletion seds.  The old `sed -e "s|^${x}.*||"` / `s|${x}||` removals
# were unanchored / over-broad / unescaped, so they also destroyed prefix-
# sibling or regex-metachar-matching valid entries (removing `foo` nuked
# `foobar`; a bare `cat/pn` nuked every slot).  _drop_line compares trimmed
# LITERAL strings via awk, which can never collateral-match.

load 'test_helper'

setup() {
	load_portconf
	_f="$(mktemp)"
}

teardown() {
	rm -f "${_f}"
}

@test "_drop_line: removes the exact matching line" {
	printf '%s\n' 'cat/a' 'cat/b' 'cat/c' > "${_f}"
	_drop_line "${_f}" 'cat/b'
	run cat "${_f}"
	assert_output "$(printf 'cat/a\ncat/c')"
}

@test "_drop_line: leaves a prefix-sibling (foo does not remove foobar)" {
	printf '%s\n' 'foo' 'foobar' '-foo' > "${_f}"
	_drop_line "${_f}" 'foo'
	run cat "${_f}"
	assert_output "$(printf 'foobar\n-foo')"
}

@test "_drop_line: a bare cat/pn does not remove slot/version siblings" {
	printf '%s\n' 'dev-lang/python' 'dev-lang/python:3.11' 'dev-lang/python-exec' > "${_f}"
	_drop_line "${_f}" 'dev-lang/python'
	run cat "${_f}"
	assert_output "$(printf 'dev-lang/python:3.11\ndev-lang/python-exec')"
}

@test "_drop_line: VALUE is literal, not a regex (a dot matches a dot only)" {
	printf '%s\n' '=dev-lang/python-3.11' '=dev-lang/python-3x11' > "${_f}"
	_drop_line "${_f}" '=dev-lang/python-3.11'
	run cat "${_f}"
	assert_output '=dev-lang/python-3x11'
}

@test "_drop_line: removes every identical duplicate line" {
	printf '%s\n' 'cat/a' 'cat/dup' 'cat/b' 'cat/dup' > "${_f}"
	_drop_line "${_f}" 'cat/dup'
	run cat "${_f}"
	assert_output "$(printf 'cat/a\ncat/b')"
}

@test "_drop_line: no-op when VALUE is absent" {
	printf '%s\n' 'cat/a' 'cat/b' > "${_f}"
	_drop_line "${_f}" 'cat/zzz'
	run cat "${_f}"
	assert_output "$(printf 'cat/a\ncat/b')"
}

@test "_drop_line: matches modulo surrounding whitespace" {
	printf '%s\n' '  cat/a  ' 'cat/b' > "${_f}"
	_drop_line "${_f}" 'cat/a'
	run cat "${_f}"
	assert_output 'cat/b'
}

# --- field1 mode: match the first whitespace field (drop the whole entry) ---

@test "_drop_line field1: removes the whole entry matching the first field" {
	printf '%s\n' 'cat/a flag1 flag2' 'cat/b flag3' > "${_f}"
	_drop_line "${_f}" 'cat/a' field1
	run cat "${_f}"
	assert_output 'cat/b flag3'
}

@test "_drop_line field1: a first-field match never hits a prefix-sibling atom" {
	printf '%s\n' 'cat/a flag' 'cat/a-extra flag' 'dev-lang/python:3.11' 'dev-lang/python:3.12' > "${_f}"
	_drop_line "${_f}" 'cat/a' field1
	_drop_line "${_f}" 'dev-lang/python:3.11' field1
	run cat "${_f}"
	assert_output "$(printf 'cat/a-extra flag\ndev-lang/python:3.12')"
}
