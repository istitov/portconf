#!/usr/bin/env bats
# Smoke: NO_COLOR + non-TTY suppression of ANSI escape sequences.
#
# Pre-fix: every printf '%b\n' "${green}...${restore}" emitted raw
# \033[01;32m sequences into pipes / files, breaking machine-readable
# usage of -V, -apu, -cpu, etc.  Post-fix: color codes set to empty
# strings at init time when stdout isn't a TTY OR NO_COLOR is set.
#
# Bats' `run` always captures stdout via a pipe, so [ -t 1 ] is always
# false from the binary's perspective in these tests — i.e., color
# codes should never appear.

load test_helper

@test "no_color: --version output contains no ANSI escapes" {
	run "${PORTCONF_BIN}" --version
	[ "$status" -eq 0 ]
	# ESC = \x1b (decimal 27).  Any byte-pattern starting with that is
	# an ANSI escape; reject all.
	[[ "${output}" != *$'\033'* ]]
}

@test "no_color: --help output contains no ANSI escapes" {
	run "${PORTCONF_BIN}" --help
	[ "$status" -eq 0 ]
	[[ "${output}" != *$'\033'* ]]
}

@test "no_color: -apu output contains no ANSI escapes (non-TTY)" {
	if ! command -v eselect >/dev/null || ! command -v eix >/dev/null; then
		skip "eselect/eix not on PATH"
	fi
	if [[ ! -L /etc/portage/make.profile && ! -L /etc/make.profile ]]; then
		skip "no make.profile symlink"
	fi
	run "${PORTCONF_BIN}" -apu
	[ "$status" -eq 0 ]
	[[ "${output}" != *$'\033'* ]]
}

@test "no_color: NO_COLOR=1 forces suppression even on TTY" {
	# Bats run is already non-TTY so this is belt-and-suspenders, but
	# also documents the contract: NO_COLOR honored alongside ! -t 1.
	NO_COLOR=1 run "${PORTCONF_BIN}" --help
	[ "$status" -eq 0 ]
	[[ "${output}" != *$'\033'* ]]
}
