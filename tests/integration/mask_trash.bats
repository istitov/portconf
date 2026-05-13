#!/usr/bin/env bats
# Integration tests for mask_trash() — detects atoms that appear in BOTH
# ${PORT_ETC}/package.mask AND ${PORT_ETC}/package.unmask (unconditionally,
# i.e. no version qualifier) and removes the mask entry, since the unmask
# cancels it out.
#
# Uses real qatom (app-portage/portage-utils) to parse atoms; the version-
# comparison branches that exercise real eix are not covered here because
# they would tie the test result to specific upstream versions of test
# packages.  Coverage focuses on the unconditional-atom branch — by far
# the most common stupid-mask pattern in user configs.
#
# Test atom: sys-apps/grep — installed in every working Gentoo system,
# core enough that no version pinning is required.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# --- redundant entry: same atom in mask AND unmask ---

@test "mask_trash: same atom in mask & unmask — removed from mask" {
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.mask"
	assert_failure
}

@test "mask_trash: same atom in mask & unmask — unmask entry preserved" {
	# mask_trash only mutates package.mask; cleaning up redundant unmask
	# entries is stupid_unmask's job.
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.unmask"
	assert_success
}

@test "mask_trash: redundant detection prints 'Incorrect'" {
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	run mask_trash
	[[ "${output}" == *'Incorrect'* ]]
}

# --- no redundancy: mask without matching unmask ---

@test "mask_trash: atom only in mask (no matching unmask) — preserved" {
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.mask"
	printf '\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.mask"
	assert_success
}

@test "mask_trash: atom only in unmask (no matching mask) — preserved" {
	printf '\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.unmask"
	assert_success
}

@test "mask_trash: different atoms in mask vs unmask — both preserved" {
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/portage\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.mask"
	assert_success
	run grep -F 'sys-apps/portage' "${PORT_ETC}/package.unmask"
	assert_success
}

# --- mixed file: only the redundant entry is removed ---

@test "mask_trash: mixed mask file — redundant entry removed" {
	printf 'sys-apps/grep\nsys-apps/portage\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	# grep is redundant (matched by unmask) → removed.
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.mask"
	assert_failure
}

@test "mask_trash: mixed mask file — non-redundant entry preserved" {
	printf 'sys-apps/grep\nsys-apps/portage\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	# portage has no matching unmask → preserved.
	run grep -F 'sys-apps/portage' "${PORT_ETC}/package.mask"
	assert_success
}

# --- comment lines: ignored by package_envs (awk filter '^[^#]') ---

@test "mask_trash: comment lines in mask are preserved" {
	printf '# header comment\nsys-apps/grep\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/portage\n' > "${PORT_ETC}/package.unmask"  # no overlap
	mask_trash
	run grep -F '# header comment' "${PORT_ETC}/package.mask"
	assert_success
}
