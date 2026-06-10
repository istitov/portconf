#!/usr/bin/env bats
# End-to-end tests for the status line printed after the dispatch loop.
#
# The unit tier (tests/unit/status_pc.bats) covers _status_pc's logic in
# isolation.  This tier drives the BUILT binary so the wiring is exercised end
# to end: diff_ask bumps the tallies during a real run and the dispatch loop
# calls _status_pc afterwards.  prop_apply always injects -y, so `prop_apply -p`
# runs the binary as `-y -p` -- the yes+pretend path behind the reported
# "portconf -p -y --use-full changes nothing, silently" confusion.

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH (portconf needs it at startup)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
}

teardown() {
	prop_cleanup
}

@test "status: applying a real change prints 'updated N file(s)'" {
	printf '%s\n' 'cat-test/alpha foo foo bar' > "${PROP_PORT_ETC}/package.use"
	prop_apply -us
	[ "${status}" -eq 0 ]
	assert_output --partial 'portconf: updated'
}

@test "status: a clean (idempotent) re-run prints 'no changes needed'" {
	printf '%s\n' 'cat-test/alpha foo foo bar' > "${PROP_PORT_ETC}/package.use"
	prop_apply -us                 # first run normalises the file
	[ "${status}" -eq 0 ]
	prop_apply -us                 # second run has nothing left to do
	[ "${status}" -eq 0 ]
	assert_output --partial 'portconf: no changes needed'
}

@test "status: -p -y (pretend wins) announces the dry run and writes nothing" {
	# Regression guard for 'portconf -p -y --use-full does nothing, silently'.
	# prop_apply injects -y, so this drives the binary as '-y -p -us'.
	printf '%s\n' 'cat-test/alpha foo foo bar' > "${PROP_PORT_ETC}/package.use"
	local before; before="$(cat "${PROP_PORT_ETC}/package.use")"
	prop_apply -p -us
	[ "${status}" -eq 0 ]
	assert_output --partial 'pretend (-p)'
	assert_output --partial 'nothing written'
	# pretend must not have touched the file
	run cat "${PROP_PORT_ETC}/package.use"
	assert_output "${before}"
}
