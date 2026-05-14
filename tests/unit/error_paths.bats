#!/usr/bin/env bats
# Tests for defensive error-path branches that the happy-path coverage
# doesn't exercise.  Each test stubs the relevant external dependency to
# simulate the failure condition.
#
# Covered:
#   eix_method  — "eix not installed" branch (line 235-239 of portconf.in)
#   eix_check   — same fallback if eix unavailable (line 209-211)
#   file_or_dir — missing-target branch (line 442-444)

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# --- eix_method: missing eix tool ---

@test "eix_method: eix not installed → prints diagnostic and exits 1" {
	# Stub eix to fail like a missing binary: --version returns empty.
	# eix_method's outer check `[[ -n "$(eix --version 2>/dev/null)" ]]`
	# then falls to the else-arm at line 235.
	eix() { return 127; }
	run eix_method
	[ "$status" -eq 1 ]
	[[ "${output}" == *'not installed'* ]]
}

@test "eix_check: eix not installed → prints diagnostic, eend 1 path" {
	# Same fallback wired into eix_check at line 209-211.  Unlike
	# eix_method, eix_check does NOT exit 1 — it just prints and
	# returns via eend.  Verify the diagnostic message fires.
	eix() { return 127; }
	run eix_check
	[[ "${output}" == *'not installed'* ]]
}

# --- file_or_dir: target missing ---

@test "file_or_dir: missing target — returns 1 with diagnostic" {
	# file_or_dir iterates ${PORT_ETC}/<target> globs.  When nothing
	# matches it prints "No such file or directory" (line 442) and
	# returns 1.  Used by every mask_trash / use_makeconf / check_use_masked
	# call to gate the per-file action — a return of 1 from file_or_dir
	# bubbles up through the caller's `|| return 1` chain.
	run file_or_dir "no_such_file_xyz" "Probing" "true"
	[ "$status" -eq 1 ]
	[[ "${output}" == *'No such file or directory'* ]]
}

@test "file_or_dir: present file — invokes the callback" {
	# Positive control: ensure the test atom triggers the callback.
	# Use a flag-file rather than a counter (counter inside ${} subshell
	# wouldn't survive — see memory: 'bash counter doesn't survive
	# $() subshell').
	local flag
	flag="$(mktemp)"
	printf 'sys-apps/grep static\n' > "${PORT_ETC}/package.use"
	rm "${flag}"
	_cb() { : > "${flag}"; }
	file_or_dir "package.use" "Probing" "_cb"
	[[ -f "${flag}" ]]
	rm -f "${flag}"
}

# --- backup: BRDIR missing → created ---

@test "backup: missing BRDIR auto-created" {
	# Line 244 of portconf.in: `[[ -d "${BRDIR}" ]] || mkdir -p "${BRDIR}"`
	# guarantees the backup dir exists.  Verify with a fresh nonexistent
	# path.
	local fresh
	fresh="$(mktemp -u -d)"  # path returned but NOT created
	BRDIR="${fresh}"
	[[ ! -d "${BRDIR}" ]]
	# Need a populated PORT_ETC so backup() has something to tar.
	printf 'USE="x"\n' > "${PORT_ETC}/make.conf"
	backup
	[[ -d "${BRDIR}" ]]
	rm -rf "${fresh}"
}
