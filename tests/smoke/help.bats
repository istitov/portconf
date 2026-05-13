#!/usr/bin/env bats
# Smoke: binary integrity and trivial dispatch paths.
#
# These tests don't touch Portage at all — they exercise help / version /
# no-op flag paths.  They catch:
#   - @PACKAGE_VERSION@ substitution failure (would show literal token)
#   - Early-init crash from set -euo pipefail regressions
#   - Help-text regression (one of the tab-indented option blocks dropped)
#   - Argument-stripping logic breakage (no-args & -p-alone-style cases)

load test_helper

@test "smoke: --help prints usage and exits 0" {
	run "${PORTCONF_BIN}" --help
	[ "$status" -eq 0 ]
	assert_output_contains 'Usage: portconf'
	assert_output_contains '--regen-cache'
	assert_output_contains '--use-full'
}

@test "smoke: -h is equivalent to --help" {
	run "${PORTCONF_BIN}" -h
	[ "$status" -eq 0 ]
	assert_output_contains 'Usage: portconf'
}

@test "smoke: --version reports package version" {
	run "${PORTCONF_BIN}" --version
	[ "$status" -eq 0 ]
	assert_output_contains 'portconf '
	# Version string must not contain the unsubstituted autotools token.
	[[ "${output}" != *'@PACKAGE_VERSION@'* ]]
}

@test "smoke: -V is equivalent to --version" {
	run "${PORTCONF_BIN}" -V
	[ "$status" -eq 0 ]
	assert_output_contains 'portconf '
}

@test "smoke: no arguments prints help" {
	run "${PORTCONF_BIN}"
	[ "$status" -eq 0 ]
	assert_output_contains 'Usage: portconf'
}

@test "smoke: unknown flag is silently ignored" {
	# Current behaviour: unknown options fall through the case statement
	# with no error.  Asserted here so a future "strict flags" change
	# surfaces in this tier, not as a user-bug report.
	run "${PORTCONF_BIN}" --this-flag-does-not-exist
	[ "$status" -eq 0 ]
}

@test "smoke: -p alone is a no-op (silently exits 0)" {
	# --pretend stripped from opts; resulting opts is whitespace, so the
	# dispatch loop iterates zero times.  No /etc/portage touch, no output.
	run "${PORTCONF_BIN}" -p
	[ "$status" -eq 0 ]
	[ -z "$(strip_ansi "${output}")" ] || \
		[[ "${output}" != *'Usage: portconf'* ]]
}

@test "smoke: -y alone is a no-op (silently exits 0)" {
	run "${PORTCONF_BIN}" -y
	[ "$status" -eq 0 ]
}

@test "smoke: -rc alone is a no-op (no eix-dep-key, opts stripped)" {
	# When -rc is passed without any flag that needs the eix cache
	# (-ui/-um/-uf/-t/-ft/-f), the dispatcher strips it and exits silently.
	# Asserts that eix_check() is NOT invoked in this path — otherwise the
	# command would block for many seconds rebuilding the cache.
	run timeout 5 "${PORTCONF_BIN}" -rc
	[ "$status" -eq 0 ]
}
