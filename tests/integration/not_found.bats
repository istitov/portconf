#!/usr/bin/env bats
# Integration tests for not_found().
#
# not_found has three independent removal mechanisms:
#
#   1. TRASH path  — first `eix -Ttc` call: reports not-installed/bad atoms
#                    grouped under their config-file path.
#   2. INVALID path — second `eix -Ttc` call: reports atoms that are syntactically
#                    invalid (format: "Invalid atom in /path: 'atom'").
#   3. emerge path  — `emerge --version 2>&1`: reports invalid atoms with
#                    "--- Invalid atom in /path: atom" lines.
#
# eix reads the real /etc/portage/ (not PORT_ETC) so it is stubbed in all
# tests.  emerge is always stubbed.  The three mechanisms are tested
# independently.
#
# TRASH-path stub note: eix is always called twice — once for TRASH and once
# for INVALID.  For tests targeting the TRASH path the stub returns TRASH
# format for all calls; for tests targeting the INVALID path the stub returns
# INVALID format.  The two formats parse into different variables, so they
# do not interfere with each other.
#
# emerge stub note: `printf '--- ...'` triggers bash's printf option parser
# on the leading `---`.  Use `echo` to avoid this.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# --- TRASH path (first eix call) ---

@test "not_found: atom listed in TRASH removed from package.use" {
	printf 'app-misc/gone\napp-misc/kept\n' > "${PORT_ETC}/package.use"
	eix() { printf '%s:\napp-misc/gone\n' "${PORT_ETC}/package.use"; }
	emerge() { :; }
	not_found
	run grep 'app-misc/gone' "${PORT_ETC}/package.use"
	assert_failure
}

@test "not_found: atom NOT in TRASH preserved in package.use" {
	printf 'app-misc/kept\n' > "${PORT_ETC}/package.use"
	eix() { printf '%s:\n' "${PORT_ETC}/package.use"; }
	emerge() { :; }
	not_found
	run grep 'app-misc/kept' "${PORT_ETC}/package.use"
	assert_success
}

# --- INVALID path (second eix call) ---
# The stub returns INVALID format on every call.  The TRASH path tries to
# remove "'app-misc/typo'" (with single quotes in the atom) from the file;
# the file only has bare "app-misc/typo" so sed finds no match and diff_ask
# exits as a no-op.  The INVALID path extracts the bare atom and removes it.

@test "not_found: atom in INVALID section removed from package.use" {
	printf 'app-misc/typo\napp-misc/kept\n' > "${PORT_ETC}/package.use"
	eix() {
		printf "Invalid atom in %s: 'app-misc/typo'\n" \
			"${PORT_ETC}/package.use"
	}
	emerge() { :; }
	not_found
	run grep 'app-misc/typo' "${PORT_ETC}/package.use"
	assert_failure
}

# --- emerge path ---
# emerge's `--version` output is the source here; use echo to avoid printf
# treating the leading "---" as an option flag.

@test "not_found: atom reported by emerge removed from package.use" {
	printf 'app-misc/broken\napp-misc/kept\n' > "${PORT_ETC}/package.use"
	eix() { :; }
	emerge() {
		echo "--- Invalid atom in ${PORT_ETC}/package.use: app-misc/broken"
	}
	not_found
	run grep 'app-misc/broken' "${PORT_ETC}/package.use"
	assert_failure
}

@test "not_found: atom NOT reported by emerge preserved in package.use" {
	printf 'app-misc/kept\n' > "${PORT_ETC}/package.use"
	eix() { :; }
	emerge() { :; }
	not_found
	run grep 'app-misc/kept' "${PORT_ETC}/package.use"
	assert_success
}

# --- no-collateral guarantees (the old unanchored sed failed these) ---

@test "not_found: removing an atom keeps a prefix-sibling atom" {
	# Removing app-misc/gone must NOT touch the distinct app-misc/gone-extra.
	printf 'app-misc/gone\napp-misc/gone-extra useflag\n' > "${PORT_ETC}/package.use"
	eix() { printf '%s:\napp-misc/gone\n' "${PORT_ETC}/package.use"; }
	emerge() { :; }
	not_found
	run grep -x 'app-misc/gone' "${PORT_ETC}/package.use"
	assert_failure
	run grep -F 'app-misc/gone-extra useflag' "${PORT_ETC}/package.use"
	assert_success
}

@test "not_found: removing an atom drops its whole line, not just the atom text" {
	# A package.use entry with flags must go entirely — no orphaned " flags".
	printf 'app-misc/gone someflag otherflag\napp-misc/kept\n' > "${PORT_ETC}/package.use"
	eix() { printf '%s:\napp-misc/gone\n' "${PORT_ETC}/package.use"; }
	emerge() { :; }
	not_found
	run grep -F 'someflag' "${PORT_ETC}/package.use"
	assert_failure
	run grep -x 'app-misc/kept' "${PORT_ETC}/package.use"
	assert_success
}

@test "not_found: an IGNORE'd atom is preserved on the INVALID path" {
	# The TRASH path always honored IGNORE; the INVALID + emerge paths now do
	# too.  An atom matching the user's IGNORE must survive even when eix calls
	# it invalid.
	printf 'app-misc/typo\napp-misc/kept\n' > "${PORT_ETC}/package.use"
	eix() { printf "Invalid atom in %s: 'app-misc/typo'\n" "${PORT_ETC}/package.use"; }
	emerge() { :; }
	IGNORE="app-misc/.*"
	not_found
	run grep -F 'app-misc/typo' "${PORT_ETC}/package.use"
	assert_success
}
