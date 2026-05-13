#!/usr/bin/env bats
# Integration tests for stupid_unmask() — detects entries in
# ${PORT_ETC}/package.unmask that don't actually do anything (the package
# isn't masked at the profile level, so the unmask is a no-op).
#
# Sets four EIX_* env vars to drive `eix -Tc#` (test-obsolete, compact,
# pure-package) into reporting these stupid unmasks:
#   REDUNDANT_IF_IN_UNMASK=all
#   REDUNDANT_IF_IN_MASK=no
#   TEST_FOR_NONEXISTENT=true
#   REDUNDANT_IF_UNMASK_NO_CHANGE=all
#
# Then for each reported atom, the function inspects installed/masked
# state via `eix --installed-masked` and `eix -Iqe` to label the entry
# as "stupid entry" vs "stupid entry (!installed)" before removing it.
#
# eix reads the real /etc/portage/ (not PORT_ETC) — same constraint as
# not_found.bats — so eix is stubbed.  qatom IS used for real (against
# the line content the test fixture controls).

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# Dispatching eix stub: -Tc# returns a fixed atom list; --installed-masked
# returns 1 (atom not masked) so every atom counts as stupid; -Iqe returns
# 0 (atom installed) so the label is "stupid entry:" rather than
# "stupid entry (!installed):".
_eix_dispatch_installed() {
	case "$*" in
		*'-Tc#'*)                  printf '%s\n' "${EIX_TRASH_ATOMS:-}";;
		*'--installed-masked'*)    return 1;;
		*'-Iqe'*)                  return 0;;
		*)                          return 0;;
	esac
}

# Same dispatch but -Iqe returns 1 → atom not installed → "!installed" label.
_eix_dispatch_not_installed() {
	case "$*" in
		*'-Tc#'*)                  printf '%s\n' "${EIX_TRASH_ATOMS:-}";;
		*'--installed-masked'*)    return 1;;
		*'-Iqe'*)                  return 1;;
		*)                          return 0;;
	esac
}

# --- baseline: unmask of an installed, NOT-actually-masked package ---

@test "stupid_unmask: installed non-masked package — removed as stupid" {
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	EIX_TRASH_ATOMS='sys-apps/grep'
	eix() { _eix_dispatch_installed "$@"; }
	stupid_unmask
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.unmask"
	assert_failure
}

@test "stupid_unmask: stupid-entry detection prints 'stupid entry'" {
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	EIX_TRASH_ATOMS='sys-apps/grep'
	eix() { _eix_dispatch_installed "$@"; }
	run stupid_unmask
	[[ "${output}" == *'stupid entry'* ]]
}

@test "stupid_unmask: non-installed atom labelled '!installed'" {
	printf 'nonexistent/pkg\n' > "${PORT_ETC}/package.unmask"
	EIX_TRASH_ATOMS='nonexistent/pkg'
	eix() { _eix_dispatch_not_installed "$@"; }
	run stupid_unmask
	[[ "${output}" == *'!'*'installed'* ]]
}

# --- atom NOT reported by eix -Tc# — file unchanged ---

@test "stupid_unmask: atom not in eix output — preserved in package.unmask" {
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	EIX_TRASH_ATOMS=''
	eix() { _eix_dispatch_installed "$@"; }
	stupid_unmask
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.unmask"
	assert_success
}

# --- multiple atoms: only the stupid ones are removed ---

@test "stupid_unmask: mixed file — stupid unmasks removed" {
	printf 'sys-apps/grep\nsys-apps/portage\n' > "${PORT_ETC}/package.unmask"
	EIX_TRASH_ATOMS=$'sys-apps/grep\nsys-apps/portage'
	eix() { _eix_dispatch_installed "$@"; }
	stupid_unmask
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.unmask"
	assert_failure
	run grep -F 'sys-apps/portage' "${PORT_ETC}/package.unmask"
	assert_failure
}

@test "stupid_unmask: mixed file — non-flagged atom preserved" {
	printf 'sys-apps/grep\nsys-apps/portage\n' > "${PORT_ETC}/package.unmask"
	# Only sys-apps/grep is stupid; sys-apps/portage stays.
	EIX_TRASH_ATOMS='sys-apps/grep'
	eix() { _eix_dispatch_installed "$@"; }
	stupid_unmask
	run grep -F 'sys-apps/portage' "${PORT_ETC}/package.unmask"
	assert_success
}

# --- comment lines: should be preserved ---

@test "stupid_unmask: comment lines preserved" {
	# remove_trash operates via sed -e "s|${line}||" on matched atom
	# lines, not comment lines.  A header comment must survive.
	printf '# my custom unmasks\nsys-apps/grep\n' \
		> "${PORT_ETC}/package.unmask"
	stupid_unmask
	run grep -F '# my custom unmasks' "${PORT_ETC}/package.unmask"
	assert_success
}

# --- missing package.unmask: file_or_dir returns 1, no crash ---

@test "stupid_unmask: missing package.unmask — no-op, no crash" {
	# stupid_unmask is wrapped in file_or_dir which gracefully reports
	# "No such file or directory" and returns 1 when the target is missing.
	# Must NOT crash bats (set -euo pipefail) nor leave EIX_* exported on
	# exit (the function unsets them at the bottom — verified by test 7).
	[[ ! -e "${PORT_ETC}/package.unmask" ]]
	run stupid_unmask
	# Exit status is unspecified by the file_or_dir contract; the test
	# just verifies the function doesn't kill bats with SIGABRT/SIGINT.
	[[ "$status" -ne 130 && "$status" -ne 134 ]]
}

# --- env-var hygiene: stupid_unmask exports four EIX_* vars temporarily ---

@test "stupid_unmask: unsets EIX_* env vars after completion" {
	# The four REDUNDANT_IF_* / TEST_FOR_NONEXISTENT vars are set at
	# entry and unset on exit (line 1448 of portconf.in).  Leaking them
	# into subsequent dispatch steps would taint other eix calls.
	printf 'sys-apps/grep\n' > "${PORT_ETC}/package.unmask"
	stupid_unmask
	[[ -z "${REDUNDANT_IF_IN_UNMASK:-}" ]]
	[[ -z "${REDUNDANT_IF_IN_MASK:-}" ]]
	[[ -z "${TEST_FOR_NONEXISTENT:-}" ]]
	[[ -z "${REDUNDANT_IF_UNMASK_NO_CHANGE:-}" ]]
}
