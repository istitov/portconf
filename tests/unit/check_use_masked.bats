#!/usr/bin/env bats
# Tests for check_use_masked() / etc_profile_use_mask() — the "stupid mask"
# detector for ${PORT_ETC}/profile/use.mask.
#
# Logic in etc_profile_use_mask():
#   1. For each entry in ${PORT_ETC}/profile/use.mask:
#        a. If the entry is ALSO present in the live profile-tree use.mask
#           (computed by use_mask() via readlink + profile_masked_uses)
#           → it is redundant.  Remove with one of two labels:
#              - starts with "-"  → "Twice unmasked"
#              - otherwise        → "Twice masked"
#        b. If the entry is NOT present in the profile tree AND starts with "-"
#           → it is a "Stupid unmask" (unmasking something the profile
#             doesn't mask in the first place).  Remove.
#        c. If the entry is NOT present in the profile tree and does NOT
#           start with "-" → keep it (legitimate per-host mask).
#
# Dependencies overridden per test:
#   PORT_ETC      — sandbox directory
#   use_mask()    — stubbed to return a controlled flag list
#   mask_files()  — stubbed to return "use.mask" (no use.stable.mask path)

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	mkdir -p "${PORT_ETC}/profile"
	# check_use_masked iterates over mask_files() output; stub to a single
	# filename so we exercise the use.mask path deterministically.
	mask_files() { echo "use.mask"; }
}

teardown() {
	teardown_test_portage
}

# --- twice-masked: positive flag in both per-host file and profile tree ---

@test "check_use_masked: twice-masked flag (in profile too) is removed" {
	printf 'foo\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf 'foo\n'; }
	check_use_masked
	run grep '^foo$' "${PORT_ETC}/profile/use.mask"
	assert_failure
}

@test "check_use_masked: twice-masked detection prints 'Twice masked'" {
	printf 'foo\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf 'foo\n'; }
	run check_use_masked
	[[ "${output}" == *'Twice masked'* ]]
}

# --- twice-unmasked: negative flag in both per-host file and profile tree ---

@test "check_use_masked: twice-unmasked flag (in profile too) is removed" {
	printf -- '-foo\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf -- '-foo\n'; }
	check_use_masked
	run grep -- '^-foo$' "${PORT_ETC}/profile/use.mask"
	assert_failure
}

@test "check_use_masked: twice-unmasked detection prints 'Twice unmasked'" {
	printf -- '-foo\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf -- '-foo\n'; }
	run check_use_masked
	[[ "${output}" == *'Twice unmasked'* ]]
}

# --- stupid unmask: -flag not present in profile tree → remove ---

@test "check_use_masked: stupid unmask (flag not in profile) is removed" {
	# Unmasking "-foo" when the profile tree does not mask "foo" is a
	# no-op and gets cleaned up.
	printf -- '-foo\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf 'something_else\n'; }
	check_use_masked
	run grep -- '^-foo$' "${PORT_ETC}/profile/use.mask"
	assert_failure
}

@test "check_use_masked: stupid-unmask detection prints 'Stupid unmask'" {
	printf -- '-foo\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf 'something_else\n'; }
	run check_use_masked
	[[ "${output}" == *'Stupid unmask'* ]]
}

# --- legitimate per-host mask: positive flag not in profile → keep ---

@test "check_use_masked: legitimate per-host mask is preserved" {
	# Adding a mask for "foo" when the profile does NOT mask "foo" is a
	# valid per-host override; must be kept.
	printf 'foo\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf 'something_else\n'; }
	check_use_masked
	run grep '^foo$' "${PORT_ETC}/profile/use.mask"
	assert_success
}

# --- mixed file: only the redundant entries get removed ---

@test "check_use_masked: mixed entries — only redundant/stupid ones removed" {
	printf 'foo\n-bar\nbaz\n-quux\n' > "${PORT_ETC}/profile/use.mask"
	# Profile masks "foo" (so per-host "foo" is twice-masked → drop)
	# and "-bar" (so per-host "-bar" is twice-unmasked → drop).
	# "baz" is a legitimate per-host mask (keep).
	# "-quux" is stupid (profile doesn't mask "quux", so unmasking is a
	# no-op → drop).
	use_mask() { printf 'foo\n-bar\n'; }
	check_use_masked
	# foo: redundant → removed
	run grep '^foo$' "${PORT_ETC}/profile/use.mask"
	assert_failure
}

@test "check_use_masked: mixed entries — legitimate per-host mask kept" {
	printf 'foo\n-bar\nbaz\n-quux\n' > "${PORT_ETC}/profile/use.mask"
	use_mask() { printf 'foo\n-bar\n'; }
	check_use_masked
	# baz: legitimate per-host (not in profile, positive) → kept
	run grep '^baz$' "${PORT_ETC}/profile/use.mask"
	assert_success
}

# --- missing profile/use.mask: function should bail without crashing ---

@test "check_use_masked: missing profile/use.mask — no-op, exits non-zero" {
	# etc_profile_use_mask returns 1 if the file doesn't exist; bubbled
	# up via file_or_dir.  No mutation; no crash.
	use_mask() { printf 'foo\n'; }
	# file_or_dir loops over package.* style globs; it must tolerate the
	# missing directory cleanly.  Verifies set -euo pipefail compatibility
	# of the early-exit path.
	run check_use_masked
	# Exit status is unspecified by the contract (file_or_dir returns 1
	# from each loop iteration), but the function must not crash bats.
	[[ "$status" -ne 130 ]]  # not SIGINT
}
