#!/usr/bin/env bats
# Tests for ver_diff and ver_btwn — the version comparison helpers used by
# mask_trash to decide whether masked/unmasked atom pairs are redundant.
#
# ver_diff V1 V2 → echoes:
#   "1"  if V1 > V2
#   "2"  if V2 > V1
#   "0"  if V1 = V2
#   (silent if versionsort cannot compare them)
#
# ver_btwn UPPER LOWER "v1 v2 …" → echoes "1" if any version in the
#   space-separated list is strictly between LOWER and UPPER; silent otherwise.
#
# Requires: app-portage/portage-utils (versionsort)

load 'test_helper'

setup() {
	load_portconf
}

# --- ver_diff ---

@test "ver_diff: first > second — returns 1" {
	run ver_diff 2.0 1.0
	assert_output "1"
}

@test "ver_diff: second > first — returns 2" {
	run ver_diff 1.0 2.0
	assert_output "2"
}

@test "ver_diff: equal versions — returns 0" {
	run ver_diff 1.0 1.0
	assert_output "0"
}

@test "ver_diff: multi-digit component (1.10 > 1.9, not lexicographic)" {
	run ver_diff 1.10 1.9
	assert_output "1"
}

@test "ver_diff: pre-release less than release (1.0_beta < 1.0)" {
	run ver_diff 1.0_beta 1.0
	assert_output "2"
}

@test "ver_diff: patchlevel greater than base (1.0_p1 > 1.0)" {
	run ver_diff 1.0_p1 1.0
	assert_output "1"
}

@test "ver_diff: three-component version comparison (1.2.3 > 1.2.2)" {
	run ver_diff 1.2.3 1.2.2
	assert_output "1"
}

@test "ver_diff: revision greater than base (1.0-r1 > 1.0)" {
	run ver_diff 1.0-r1 1.0
	assert_output "1"
}

# --- ver_btwn ---
# Signature: ver_btwn UPPER LOWER "space-separated version list"
# Returns "1" if any version in the list is strictly between LOWER and UPPER.

@test "ver_btwn: version strictly between bounds — returns 1" {
	run ver_btwn 3.0 1.0 "2.0"
	assert_output "1"
}

@test "ver_btwn: version equals lower bound — silent (not strictly between)" {
	run ver_btwn 3.0 1.0 "1.0"
	assert_output ""
}

@test "ver_btwn: version equals upper bound — silent (not strictly between)" {
	run ver_btwn 3.0 1.0 "3.0"
	assert_output ""
}

@test "ver_btwn: version below lower bound — silent" {
	run ver_btwn 3.0 1.0 "0.5"
	assert_output ""
}

@test "ver_btwn: version above upper bound — silent" {
	run ver_btwn 3.0 1.0 "4.0"
	assert_output ""
}

@test "ver_btwn: multiple versions, one between — returns 1" {
	run ver_btwn 3.0 1.0 "0.5 2.0 4.0"
	assert_output "1"
}

@test "ver_btwn: multiple versions, none between — silent" {
	run ver_btwn 3.0 1.0 "0.5 4.0"
	assert_output ""
}

@test "ver_btwn: pre-release is between bounds" {
	run ver_btwn 2.0 1.0 "1.5_beta"
	assert_output "1"
}
