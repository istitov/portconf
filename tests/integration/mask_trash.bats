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

# --- versioned atoms: msw != "(null)" branch ---------------------------
#
# The original 9 tests covered only the msw==(null) unconditional path.
# The version-comparison code at lines 1413-1442 of portconf.in is much
# more involved and was entirely untested before this section.

@test "mask_trash: versioned mask + unconditional unmask → mask removed" {
	# A versioned mask "<sys-apps/grep-99" is fully subsumed by an
	# unconditional unmask "sys-apps/grep" (which permits all versions).
	# Hits the msw!=(null) && usw==(null) && uslot==(null) branch
	# (line 1414-1415) → non_slot_output → mask entry removed.
	printf '<sys-apps/grep-99\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F '<sys-apps/grep-99' "${PORT_ETC}/package.mask"
	assert_failure
}

@test "mask_trash: versioned mask + unconditional unmask — prints atom-with-op" {
	# non_slot_output prints "${msw}${mcategory}/${mpn}-${mver}" — the
	# operator and version are visible in the warning.
	printf '<sys-apps/grep-99\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	run mask_trash
	[[ "${output}" == *'<sys-apps/grep'* ]]
}

@test "mask_trash: >= mask + >= unmask, same direction — mask flagged" {
	# Both have ">"-class operators; the inner branch at line 1419-1421
	# triggers non_slot_output when versions_diff != "1" AND
	# versions_btwn is empty (i.e., no intermediate version available
	# in the tree to differentiate them).
	#
	# >=grep-1.0 says "mask 1.0 and newer".  >=grep-1.0 unmask says
	# "unmask 1.0 and newer".  Identical scope → mask is redundant.
	printf '>=sys-apps/grep-1.0\n' > "${PORT_ETC}/package.mask"
	printf '>=sys-apps/grep-1.0\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	# Identical versions: ver_diff returns 0 (not "1" → equal), no
	# intermediates → non_slot_output fires → mask removed.
	run grep -F '>=sys-apps/grep-1.0' "${PORT_ETC}/package.mask"
	assert_failure
}

@test "mask_trash: < mask + < unmask, same version — mask flagged" {
	# Symmetric <-side branch at line 1425-1429.  <grep-9.0 masks
	# everything BELOW 9.0; matching unmask same scope → redundant.
	printf '<sys-apps/grep-9.0\n' > "${PORT_ETC}/package.mask"
	printf '<sys-apps/grep-9.0\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F '<sys-apps/grep-9.0' "${PORT_ETC}/package.mask"
	assert_failure
}

@test "mask_trash: >= mask + < unmask (different directions) — preserved" {
	# Direction mismatch: the inner branches only fire when both sides
	# point the same way.  ">=mask vs <unmask" doesn't satisfy any of
	# the inner conditions → mask kept.
	printf '>=sys-apps/grep-1.0\n' > "${PORT_ETC}/package.mask"
	printf '<sys-apps/grep-9.0\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F '>=sys-apps/grep-1.0' "${PORT_ETC}/package.mask"
	assert_success
}

@test "mask_trash: slot-qualified atoms — same slot on both sides flagged" {
	# msw==(null) but slot is set: the slot-comparison branch at
	# lines 1430-1442 handles this.  Same slot on both, usw==(null) →
	# slot_output → mask removed.
	printf 'sys-apps/grep:0\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep:0\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F 'sys-apps/grep:0' "${PORT_ETC}/package.mask"
	assert_failure
}

@test "mask_trash: slot-qualified atoms — different slots preserved" {
	# Different slots → mslot != uslot → slot-comparison branch skipped
	# → mask preserved.
	printf 'sys-apps/grep:0\n' > "${PORT_ETC}/package.mask"
	printf 'sys-apps/grep:1\n' > "${PORT_ETC}/package.unmask"
	mask_trash
	run grep -F 'sys-apps/grep:0' "${PORT_ETC}/package.mask"
	assert_success
}
