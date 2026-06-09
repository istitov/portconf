#!/usr/bin/env bats
# Property tests for USE-flag sorting (-us) and the -s sort composite.
#
# Drives the built binary with -y over synthetic fixtures and asserts the
# transform invariants (idempotence, no duplicate flag, inventory preserved),
# not a golden string.  See tests/property/test_helper.bash for the harness
# and the anonymity rationale for the fake atoms/flags used here.

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH (portconf needs it at startup)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
}

teardown() {
	prop_cleanup
}

@test "property: -us dedups USE flags (last-state-wins), no dup, idempotent, inventory kept" {
	printf '%s\n' \
		'# why alpha wants these' \
		'cat-test/alpha zoo bar bar apple' \
		'cat-demo/gamma xyz abc xyz' \
		'cat-test/beta -foo foo' \
		> "${PROP_PORT_ETC}/package.use"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.use")"

	prop_apply -us
	[ "${status}" -eq 0 ]

	# No base flag may survive twice on any line.
	assert_no_dup_flags "${PROP_PORT_ETC}/package.use"
	# Every atom carried at least one flag, so none is dropped.
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.use"
	# Last-state-wins resolved the -foo/foo conflict to plain foo.
	run grep -E '^cat-test/beta foo$' "${PROP_PORT_ETC}/package.use"
	assert_success
	# Header comment travelled with its atom.
	run grep -F '# why alpha wants these' "${PROP_PORT_ETC}/package.use"
	assert_success

	assert_idempotent -us
}

@test "property: -us merges duplicate atom lines into one, no dup, idempotent" {
	printf '%s\n' \
		'cat-test/alpha bar' \
		'cat-test/alpha baz bar' \
		> "${PROP_PORT_ETC}/package.use"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.use")"

	prop_apply -us
	[ "${status}" -eq 0 ]

	# The two lines for the same atom collapse to exactly one.
	run bash -c "grep -c '^cat-test/alpha ' '${PROP_PORT_ETC}/package.use'"
	assert_output "1"
	assert_no_dup_flags "${PROP_PORT_ETC}/package.use"
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.use"

	assert_idempotent -us
}

@test "property: -us preserves a header block and an inline comment" {
	printf '%s\n' \
		'# block line one' \
		'# block line two' \
		'cat-test/alpha foo bar # keep me inline' \
		> "${PROP_PORT_ETC}/package.use"

	prop_apply -us
	[ "${status}" -eq 0 ]

	run cat "${PROP_PORT_ETC}/package.use"
	assert_line --partial 'block line one'
	assert_line --partial 'block line two'
	assert_line --partial 'keep me inline'
	assert_no_dup_flags "${PROP_PORT_ETC}/package.use"

	assert_idempotent -us
}

@test "property: -us on directory-layout package.use dedups + idempotent" {
	# Modern Gentoo layout: package.use is a directory of fragments.  This
	# exercises file_or_dir's directory branch + the fd-9 diff_ask reroute.
	rm -f "${PROP_PORT_ETC}/package.use"
	mkdir "${PROP_PORT_ETC}/package.use"
	printf '%s\n' \
		'cat-test/alpha foo foo bar' \
		'cat-demo/gamma baz -baz' \
		> "${PROP_PORT_ETC}/package.use/frag"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.use")"

	prop_apply -us
	[ "${status}" -eq 0 ]

	assert_no_dup_flags "${PROP_PORT_ETC}/package.use"
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.use"
	# baz/-baz resolves last-state-wins to -baz.
	run grep -E '^cat-demo/gamma -baz$' "${PROP_PORT_ETC}/package.use/frag"
	assert_success

	assert_idempotent -us
}

@test "property: -s sort composite holds invariants across multiple package.* files" {
	printf '%s\n' \
		'cat-test/alpha bar bar foo' \
		'cat-demo/gamma baz' \
		> "${PROP_PORT_ETC}/package.use"
	printf '%s\n' \
		'cat-demo/gamma ~testarch testarch' \
		'cat-test/alpha ~testarch ~testarch' \
		> "${PROP_PORT_ETC}/package.accept_keywords"
	printf '%s\n' \
		'cat-test/zeta' \
		'cat-demo/early' \
		> "${PROP_PORT_ETC}/package.mask"

	local use_before kw_before mask_before
	use_before="$(atoms_of "${PROP_PORT_ETC}/package.use")"
	kw_before="$(atoms_of "${PROP_PORT_ETC}/package.accept_keywords")"
	mask_before="$(atoms_of "${PROP_PORT_ETC}/package.mask")"

	prop_apply -s
	[ "${status}" -eq 0 ]

	assert_no_dup_flags "${PROP_PORT_ETC}/package.use"
	assert_no_dup_flags "${PROP_PORT_ETC}/package.accept_keywords"
	assert_atoms_equal "${use_before}"  "${PROP_PORT_ETC}/package.use"
	assert_atoms_equal "${kw_before}"   "${PROP_PORT_ETC}/package.accept_keywords"
	assert_atoms_equal "${mask_before}" "${PROP_PORT_ETC}/package.mask"

	assert_idempotent -s
}
