#!/usr/bin/env bats
# Property tests for keyword dedup/sort: -ku (uniq_keywords -> sort_keys,
# last-state-wins per base) and -ko (sort_keywords -> keys, keep only the
# last token).
#
# Keyword tokens are SYNTHETIC arch names (~testarch, testarch, ~otherarch)
# chosen so they can never equal the host's real ACCEPT_KEYWORDS — that
# keeps stupid_keywords (which strips per-package keywords already implied
# by the system default) from removing them, so inventory-preservation
# holds on any host (stable or testing) regardless of the maintainer's
# actual arch.  We deliberately avoid bare (keyword-less) lines: their
# ~$ARCH fallback could be system-default and get stripped, which is
# host-dependent and not what these invariants are testing.

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH (portconf needs it at startup)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
}

teardown() {
	prop_cleanup
}

@test "property: -ku dedups keywords (last-state-wins), no dup, idempotent, inventory kept" {
	printf '%s\n' \
		'cat-test/alpha ~testarch testarch ~testarch' \
		'cat-demo/gamma ~otherarch ~otherarch' \
		> "${PROP_PORT_ETC}/package.accept_keywords"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.accept_keywords")"

	prop_apply -ku
	[ "${status}" -eq 0 ]

	assert_no_dup_flags "${PROP_PORT_ETC}/package.accept_keywords"
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.accept_keywords"
	# alpha: ~testarch/testarch/~testarch share base testarch; last state wins.
	run grep -E '^cat-test/alpha ~testarch$' "${PROP_PORT_ETC}/package.accept_keywords"
	assert_success

	assert_idempotent -ku
}

@test "property: -ku merges duplicate atom lines into one, idempotent" {
	printf '%s\n' \
		'cat-test/alpha ~testarch' \
		'cat-test/alpha testarch' \
		> "${PROP_PORT_ETC}/package.accept_keywords"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.accept_keywords")"

	prop_apply -ku
	[ "${status}" -eq 0 ]

	run bash -c "grep -c '^cat-test/alpha ' '${PROP_PORT_ETC}/package.accept_keywords'"
	assert_output "1"
	assert_no_dup_flags "${PROP_PORT_ETC}/package.accept_keywords"
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.accept_keywords"

	assert_idempotent -ku
}

@test "property: -ko keeps a single keyword per atom, no dup, idempotent, inventory kept" {
	printf '%s\n' \
		'cat-test/alpha ~testarch otherarch' \
		'cat-demo/gamma testarch' \
		> "${PROP_PORT_ETC}/package.accept_keywords"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.accept_keywords")"

	prop_apply -ko
	[ "${status}" -eq 0 ]

	assert_no_dup_flags "${PROP_PORT_ETC}/package.accept_keywords"
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.accept_keywords"
	# -ko keeps only the last token of the line.
	run grep -E '^cat-test/alpha otherarch$' "${PROP_PORT_ETC}/package.accept_keywords"
	assert_success

	assert_idempotent -ko
}

@test "property: -ku on directory-layout package.accept_keywords dedups + idempotent" {
	rm -f "${PROP_PORT_ETC}/package.accept_keywords"
	mkdir "${PROP_PORT_ETC}/package.accept_keywords"
	printf '%s\n' \
		'cat-test/alpha ~testarch ~testarch' \
		'cat-demo/gamma testarch ~testarch testarch' \
		> "${PROP_PORT_ETC}/package.accept_keywords/frag"
	local before
	before="$(atoms_of "${PROP_PORT_ETC}/package.accept_keywords")"

	prop_apply -ku
	[ "${status}" -eq 0 ]

	assert_no_dup_flags "${PROP_PORT_ETC}/package.accept_keywords"
	assert_atoms_equal "${before}" "${PROP_PORT_ETC}/package.accept_keywords"

	assert_idempotent -ku
}
