#!/usr/bin/env bats
# Property tests for comment stripping: -c (rm_comments, standalone-only)
# and -ac (rm_all_comments, standalone + inline).
#
# The headline invariant is inventory-preservation: stripping comments must
# never drop an ATOM.  This is the portconf analogue of the udept
# filter_etc_file EOF-flush data-loss class — a streaming rewrite that loses
# the last block, or every other line, would shrink the atom set silently.
# A six-atom interleave is used as a deliberate guard for that "1-of-N
# survived" failure shape.

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH (portconf needs it at startup)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
}

teardown() {
	prop_cleanup
}

@test "property: -c strips standalone comments, keeps inline + every atom, idempotent" {
	printf '%s\n' \
		'# standalone one' \
		'cat-test/alpha foo' \
		'# standalone two' \
		'cat-demo/gamma bar # inline survives -c' \
		> "${PROP_PORT_ETC}/package.use"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.use")"

	prop_apply -c
	[ "${status}" -eq 0 ]

	# Atoms intact.
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.use"
	# Standalone comments gone.
	run grep -F 'standalone one' "${PROP_PORT_ETC}/package.use"
	assert_failure
	run grep -F 'standalone two' "${PROP_PORT_ETC}/package.use"
	assert_failure
	# Inline comment NOT a target of -c (it doesn't start a line).
	run grep -F 'inline survives -c' "${PROP_PORT_ETC}/package.use"
	assert_success

	assert_idempotent -c
}

@test "property: -ac strips all comments (standalone + inline), keeps every atom, idempotent" {
	printf '%s\n' \
		'# standalone one' \
		'cat-test/alpha foo' \
		'cat-demo/gamma bar # inline removed by -ac' \
		> "${PROP_PORT_ETC}/package.use"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.use")"

	prop_apply -ac
	[ "${status}" -eq 0 ]

	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.use"
	# No '#' may remain anywhere.
	run grep -F '#' "${PROP_PORT_ETC}/package.use"
	assert_failure
	# The atom + its flag survive the inline strip.
	run grep -E '^cat-demo/gamma bar$' "${PROP_PORT_ETC}/package.use"
	assert_success

	assert_idempotent -ac
}

@test "property: -c preserves all six atoms interleaved with comments (data-loss guard)" {
	printf '%s\n' \
		'# c0' \
		'cat-test/a0 f' \
		'cat-test/a1 f' \
		'# c2' \
		'cat-test/a2 f' \
		'cat-test/a3 f' \
		'cat-test/a4 f' \
		'cat-test/a5 f' \
		> "${PROP_PORT_ETC}/package.use"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.use")"

	prop_apply -c
	[ "${status}" -eq 0 ]

	# All six must survive — not 1, not 3, not every-other-line.
	run bash -c "grep -c '^cat-test/a[0-9] ' '${PROP_PORT_ETC}/package.use'"
	assert_output "6"
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.use"

	assert_idempotent -c
}
