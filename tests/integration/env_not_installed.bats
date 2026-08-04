#!/usr/bin/env bats
# Integration tests for env_not_installed -- removes env/<cat>/<pn> files whose
# target package is not installed in ${PKGDB}.
#
# These are NEW with the #118 rewrite, which made the function testable and the
# slot branch reachable.  Before it:
#   * `cut -d/ -f5-` hardcoded a /etc/portage-depth root, so under a sandbox
#     PORT_ETC (deeper) the file name parsed as `env/<cat>/<pn>` and matched
#     nothing -> the function silently did nothing in any test harness;
#   * the default whitespace `qatom` output collapsed the empty PR column, so a
#     `<cat>/<pn>:slot` name's slot landed in the `rev` field without a colon
#     and the slot branch never ran (and `ver="<unset>"` was never cleared,
#     since the code tested `== "(null)"`, so every slot file fell into the
#     pinned-version branch and was wrongly removed as `<cat>/<pn>-<unset>`).
# The rewrite slices the last two path components (depth-independent) and
# reparses with `qatom -F` (pipe-separated), like package_envs.
#
# qatom (app-portage/portage-utils) is real; PKGDB is a throwaway sandbox so the
# installed-set is fully controlled.  Atoms are synthetic cat-test/* — never the
# host's real packages.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	TEST_PKGDB="$(mktemp -d)"
	PKGDB="${TEST_PKGDB}"
	mkdir -p "${PORT_ETC}/env/cat-test"
}

teardown() {
	teardown_test_portage
	[[ -n "${TEST_PKGDB:-}" ]] && rm -rf "${TEST_PKGDB}"
}

# Mark a package version installed in the sandbox PKGDB.
#   _install cat/pn-ver [SLOT-content]
_install() {
	local d="${TEST_PKGDB}/$1"
	mkdir -p "${d}"
	[[ -n "${2:-}" ]] && printf '%s\n' "$2" > "${d}/SLOT"
	return 0   # don't let the [[ ]] && … above leak a non-zero exit under set -e
}

# --- plain <cat>/<pn> (no version, no slot): any installed version counts ---

@test "env_not_installed: removes env file for an uninstalled package" {
	: > "${PORT_ETC}/env/cat-test/foo"
	env_not_installed
	[[ ! -e "${PORT_ETC}/env/cat-test/foo" ]]
}

@test "env_not_installed: keeps env file when any version is installed" {
	: > "${PORT_ETC}/env/cat-test/bar"
	_install "cat-test/bar-1.0"
	env_not_installed
	[[ -e "${PORT_ETC}/env/cat-test/bar" ]]
}

# --- slot-qualified <cat>/<pn>:slot (the branch the old parse never reached) ---

@test "env_not_installed: slot file kept when the EXACT slot is installed" {
	: > "${PORT_ETC}/env/cat-test/baz:2"
	_install "cat-test/baz-1.0" "2"
	env_not_installed
	[[ -e "${PORT_ETC}/env/cat-test/baz:2" ]]
}

@test "env_not_installed: slot match is exact, not substring (:1 vs installed slot 10 -> removed)" {
	: > "${PORT_ETC}/env/cat-test/baz:1"
	_install "cat-test/baz-2.0" "10"
	env_not_installed
	[[ ! -e "${PORT_ETC}/env/cat-test/baz:1" ]]
}

@test "env_not_installed: subslot ignored -- :0 kept when installed SLOT is 0/2.30" {
	: > "${PORT_ETC}/env/cat-test/qux:0"
	_install "cat-test/qux-3.0" "0/2.30"
	env_not_installed
	[[ -e "${PORT_ETC}/env/cat-test/qux:0" ]]
}

@test "env_not_installed: slot file removed when no installed version occupies the slot" {
	: > "${PORT_ETC}/env/cat-test/quux:5"
	_install "cat-test/quux-1.0" "0"
	env_not_installed
	[[ ! -e "${PORT_ETC}/env/cat-test/quux:5" ]]
}

# --- version-pinned <cat>/<pn>-ver ---

@test "env_not_installed: pinned version kept when that exact version is installed" {
	: > "${PORT_ETC}/env/cat-test/zap-1.5"
	_install "cat-test/zap-1.5"
	env_not_installed
	[[ -e "${PORT_ETC}/env/cat-test/zap-1.5" ]]
}

@test "env_not_installed: pinned version removed when a different version is installed" {
	: > "${PORT_ETC}/env/cat-test/zap-1.5"
	_install "cat-test/zap-2.0"
	env_not_installed
	[[ ! -e "${PORT_ETC}/env/cat-test/zap-1.5" ]]
}

# --- IGNORE protects a matching entry from removal ---

@test "env_not_installed: IGNORE_PN protects an uninstalled package's env file" {
	: > "${PORT_ETC}/env/cat-test/keepme"
	IGNORE_PN="keepme"; _compute_ignore
	env_not_installed
	[[ -e "${PORT_ETC}/env/cat-test/keepme" ]]
}

# --- several stale files in ONE run (the %-joined RM consume-loop regression) ---

@test "env_not_installed: removes ALL stale env files when several are uninstalled at once" {
	# Two uninstalled packages -> both accumulate in the single %-joined RM
	# string.  The old `IFS='%' read -r target` consumed the whole "p1%p2"
	# blob in one iteration, so remove_ask got a single bogus combined path
	# and NEITHER file was removed.  Every other test stages exactly one stale
	# file, where the degenerate single-element list happened to work -- so the
	# multi-file path had zero coverage.
	: > "${PORT_ETC}/env/cat-test/gone_one"
	: > "${PORT_ETC}/env/cat-test/gone_two"
	env_not_installed
	[[ ! -e "${PORT_ETC}/env/cat-test/gone_one" ]]
	[[ ! -e "${PORT_ETC}/env/cat-test/gone_two" ]]
}

@test "env_not_installed: checks env.d even when env is absent" {
	rm -rf "${PORT_ETC}/env"
	mkdir -p "${PORT_ETC}/env.d/cat-test"
	: > "${PORT_ETC}/env.d/cat-test/gone"
	env_not_installed
	[[ ! -e "${PORT_ETC}/env.d/cat-test/gone" ]]
}

@test "env_not_installed: does not replay env removals while processing env.d" {
	mkdir -p "${PORT_ETC}/env.d/cat-test"
	: > "${PORT_ETC}/env/cat-test/env_gone"
	: > "${PORT_ETC}/env.d/cat-test/envd_gone"
	local calls="${BATS_TEST_TMPDIR}/removed"
	remove_ask() {
		printf '%s\n' "$1" >> "${calls}"
		rm -rf -- "$1"
	}
	env_not_installed
	[[ "$(grep -Fxc "${PORT_ETC}/env/cat-test/env_gone" "${calls}")" -eq 1 ]]
	[[ "$(grep -Fxc "${PORT_ETC}/env.d/cat-test/envd_gone" "${calls}")" -eq 1 ]]
}

@test "env_not_installed: retains a directory containing only hidden files" {
	mkdir -p "${PORT_ETC}/env.d"
	: > "${PORT_ETC}/env.d/.keep"
	env_not_installed
	[[ -f "${PORT_ETC}/env.d/.keep" ]]
}
