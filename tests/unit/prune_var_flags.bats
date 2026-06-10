#!/usr/bin/env bats
# Tests for _prune_var_flags — rebuilds a make.conf VAR="..." assignment with
# flags dropped, matching them as literal tokens/bases (never a regex).  This
# replaced the grep-the-flag / sed-the-line removal in use_makeconf (-um) and
# invalid_uses_make (-ui/-uf), which substituted across the WHOLE make.conf
# (collateral on other vars + comments), missed a first-token flag, and aborted
# under set -e when a flag matched more than one line.

load 'test_helper'

setup() {
	load_portconf
	# _prune_var_flags reads the assignment via make_conf_use, which uses the
	# global ${makefile}; point it at a scratch file.
	makefile="$(mktemp)"
}

teardown() {
	rm -f "${makefile}"
}

@test "_prune_var_flags token: drops the exact token, keeps the rest" {
	printf 'USE="alpha beta gamma"\n' > "${makefile}"
	_prune_var_flags "${makefile}" USE token "$(printf 'beta\n')"
	run cat "${makefile}"
	assert_output 'USE="alpha gamma"'
}

@test "_prune_var_flags token: removes a first-token flag" {
	printf 'USE="alpha beta"\n' > "${makefile}"
	_prune_var_flags "${makefile}" USE token "$(printf 'alpha\n')"
	run cat "${makefile}"
	assert_output 'USE="beta"'
}

@test "_prune_var_flags token: -flag and flag are distinct (only the named one goes)" {
	printf 'USE="-foo foo bar"\n' > "${makefile}"
	_prune_var_flags "${makefile}" USE token "$(printf 'foo\n')"
	run cat "${makefile}"
	assert_output 'USE="-foo bar"'
}

@test "_prune_var_flags base: drops both signs of the flag" {
	printf 'USE="-foo foo bar"\n' > "${makefile}"
	_prune_var_flags "${makefile}" USE base "$(printf 'foo\n')"
	run cat "${makefile}"
	assert_output 'USE="bar"'
}

@test "_prune_var_flags: never touches other variables or comments" {
	printf '%s\n' '# keep foo in this comment' 'USE="foo bar"' 'VIDEO_CARDS="foo nouveau"' > "${makefile}"
	_prune_var_flags "${makefile}" USE base "$(printf 'foo\n')"
	run cat "${makefile}"
	assert_output "$(printf '# keep foo in this comment\nUSE="bar"\nVIDEO_CARDS="foo nouveau"')"
}

@test "_prune_var_flags: \$-expansion tokens survive" {
	printf 'USE="${VIDEO_CARDS} foo bar"\n' > "${makefile}"
	_prune_var_flags "${makefile}" USE base "$(printf 'foo\n')"
	run cat "${makefile}"
	assert_output 'USE="${VIDEO_CARDS} bar"'
}

@test "_prune_var_flags: collapses a backslash-continued assignment" {
	printf 'USE="alpha beta \\\n   gamma delta"\n' > "${makefile}"
	_prune_var_flags "${makefile}" USE base "$(printf 'beta\ngamma\n')"
	run cat "${makefile}"
	assert_output 'USE="alpha delta"'
}

@test "_prune_var_flags: a different variable is pruned independently of USE" {
	printf '%s\n' 'USE="foo"' 'VIDEO_CARDS="foo nouveau"' > "${makefile}"
	_prune_var_flags "${makefile}" VIDEO_CARDS base "$(printf 'foo\n')"
	run cat "${makefile}"
	assert_output "$(printf 'USE="foo"\nVIDEO_CARDS="nouveau"')"
}

@test "_prune_var_flags: dropping every flag leaves an empty assignment" {
	printf 'USE="foo bar"\n' > "${makefile}"
	_prune_var_flags "${makefile}" USE base "$(printf 'foo\nbar\n')"
	run cat "${makefile}"
	assert_output 'USE=""'
}
