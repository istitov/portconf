#!/usr/bin/env bats
# Property test for invalid_uses (-ui) END-TO-END on the built binary with
# REAL eix + qatom metadata.
#
# This is the property-tier counterpart to tests/integration/invalid_uses.bats,
# which sources the function and stubs externals.  The 2.0.4 corruption bug
# lived in invalid_uses' agrep "did you mean" correction: it mis-mapped
# genuinely-removed flags to unrelated valid ones and duplicated them,
# breaking idempotence (gles1->test => "test test").  The fix DELETED that
# correction outright (an invalid flag is now just removed), so the binary no
# longer calls agrep at all.  This test asserts the invariants the bug
# violated, on the real built binary: the invalid flag is dropped, no
# duplicate flag is produced, and a second -ui is a no-op.
#
# Fixture: sys-apps/grep is a @system package on every Gentoo install (not
# fingerprinting), 'static' is one of its long-stable IUSE entries, and
# 'not_a_real_use_flag_xyz' is a token eix will never recognise.

load test_helper

setup() {
	command -v eix   >/dev/null || skip "eix not on PATH"
	command -v qatom >/dev/null || skip "qatom not on PATH (app-portage/portage-utils)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
}

teardown() {
	prop_cleanup
}

@test "property: -ui removes an invalid flag, creates no duplicate, is idempotent" {
	printf 'sys-apps/grep static not_a_real_use_flag_xyz\n' \
		> "${PROP_PORT_ETC}/package.use"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.use")"

	prop_apply -ui
	[ "${status}" -eq 0 ]

	# Invalid flag must be gone (removed, never "corrected" to something else).
	run grep -F 'not_a_real_use_flag_xyz' "${PROP_PORT_ETC}/package.use"
	assert_failure
	# No flag may appear twice — the exact shape of the agrep dup bug.
	assert_no_dup_flags "${PROP_PORT_ETC}/package.use"
	# No atom was invented (the sole atom may survive or, if it ends up
	# flag-less, be dropped — but nothing new may appear).
	assert_atoms_subset "${before}" "${PROP_PORT_ETC}/package.use"

	# Second -ui must change nothing: the regression made -ui non-idempotent.
	assert_idempotent -ui
}

@test "property: -ui on directory-layout package.use is idempotent, no dup" {
	rm -f "${PROP_PORT_ETC}/package.use"
	mkdir "${PROP_PORT_ETC}/package.use"
	printf 'sys-apps/grep static not_a_real_use_flag_xyz\n' \
		> "${PROP_PORT_ETC}/package.use/frag"

	prop_apply -ui
	[ "${status}" -eq 0 ]

	run grep -RF 'not_a_real_use_flag_xyz' "${PROP_PORT_ETC}/package.use"
	assert_failure
	assert_no_dup_flags "${PROP_PORT_ETC}/package.use"

	assert_idempotent -ui
}
