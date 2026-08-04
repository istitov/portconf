#!/usr/bin/env bats
# Integration tests for package_env() — the "remove references to env
# config files that no longer exist" handler.
#
# Coverage focus: the sed-replacement at line ~840 of portconf.in.
# Before commit cd75... (HIGH#1 fix), the sed pattern used raw ${line}
# and ${new_line} interpolation, which silently failed or corrupted the
# tmp file when the line contained sed metacharacters (`|`, `\`, `.`,
# `[`, `*`).  Atoms with USE-dep brackets (`sys-apps/grep[static]`) and
# any comment-with-pipe trigger the regex break.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	mkdir -p "${PORT_ETC}/env"
}

teardown() {
	teardown_test_portage
}

# --- happy path: missing conf removed cleanly ---

@test "package_env: missing conf is removed from atom line" {
	printf 'sys-apps/grep nonexistent.conf\n' > "${PORT_ETC}/package.env"
	package_env
	run grep -F 'nonexistent.conf' "${PORT_ETC}/package.env"
	assert_failure
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.env"
	assert_failure
}

@test "package_env: present conf is preserved" {
	# Create the env file that the atom line references.
	: > "${PORT_ETC}/env/keep.conf"
	printf 'sys-apps/grep keep.conf\n' > "${PORT_ETC}/package.env"
	package_env
	run grep -F 'keep.conf' "${PORT_ETC}/package.env"
	assert_success
}

@test "package_env: a present conf does NOT leak into the global IGNORE" {
	# Regression for the IGNORE-overload: package_env used to append every
	# still-existing conf basename to the GLOBAL IGNORE, polluting the pattern
	# that not_found / invalid_uses / env_not_installed all `grep -v` against
	# later in the same run -- so a conf named e.g. `static` silently filtered
	# out any atom containing that substring.  package_env must leave IGNORE
	# untouched.
	: > "${PORT_ETC}/env/keep.conf"
	printf 'sys-apps/grep keep.conf\n' > "${PORT_ETC}/package.env"
	local before="${IGNORE}"
	package_env
	[[ "${IGNORE}" == "${before}" ]] || {
		echo "IGNORE was mutated: before=[${before}] after=[${IGNORE}]" >&2
		false
	}
}

# --- sed-injection regression: USE-dep brackets in atom ---

@test "package_env: atom with [USE] brackets doesn't corrupt file" {
	# Pre-fix: the `[static]` in the atom would be interpreted by sed
	# as a character class opener, gobbling up to the next `]` and
	# producing garbage output.  Post-fix: the `[` is escaped before
	# interpolation and the substitution is exact.
	: > "${PORT_ETC}/env/keep.conf"
	printf 'sys-apps/grep[static] keep.conf nonexistent.conf\n' \
		> "${PORT_ETC}/package.env"
	package_env
	# The original atom should still be in the file (not corrupted).
	run grep -F 'sys-apps/grep[static]' "${PORT_ETC}/package.env"
	assert_success
	run grep -F 'keep.conf' "${PORT_ETC}/package.env"
	assert_success
	# The missing conf should have been removed.
	run grep -F 'nonexistent.conf' "${PORT_ETC}/package.env"
	assert_failure
}

# --- sed-injection regression: pipe character in line ---

@test "package_env: line with pipe char in comment doesn't corrupt file" {
	# Pre-fix: a `|` in the line (e.g., from a user's comment) became
	# the unescaped sed delimiter, splitting the s||| command and
	# producing a syntax error or silently truncating.
	printf 'sys-apps/grep miss.conf # alt | option\n' \
		> "${PORT_ETC}/package.env"
	package_env
	# The invalid entry disappears, but its annotation remains useful.
	run grep -F 'sys-apps/grep' "${PORT_ETC}/package.env"
	assert_failure
	run grep -Fx '# alt | option' "${PORT_ETC}/package.env"
	assert_success
}

# --- sed-injection regression: dot in conf name ---

@test "package_env: conf name with multiple dots is matched literally" {
	# Pre-fix: `.` in `some.thing.conf` matched ANY character via the
	# unescaped regex, potentially matching unintended substrings.
	# Post-fix: each `.` is escaped to match literally.
	: > "${PORT_ETC}/env/keep.conf"
	printf 'sys-apps/grep some.thing.conf keep.conf\n' \
		> "${PORT_ETC}/package.env"
	package_env
	# keep.conf must remain; some.thing.conf must be removed.
	run grep -F 'keep.conf' "${PORT_ETC}/package.env"
	assert_success
	run grep -F 'some.thing.conf' "${PORT_ETC}/package.env"
	assert_failure
}

# --- multiple confs on one line ---

@test "package_env: only the missing conf is removed from a multi-conf line" {
	: > "${PORT_ETC}/env/keep.conf"
	printf 'sys-apps/grep keep.conf nonexistent.conf\n' \
		> "${PORT_ETC}/package.env"
	package_env
	run grep -F 'keep.conf' "${PORT_ETC}/package.env"
	assert_success
	run grep -F 'nonexistent.conf' "${PORT_ETC}/package.env"
	assert_failure
}

@test "package_env_conf: references are global across directory fragments" {
	rm -f "${PORT_ETC}/package.env"
	mkdir -p "${PORT_ETC}/package.env"
	printf 'cat-test/a shared.conf\n' > "${PORT_ETC}/package.env/first"
	printf 'cat-test/b other.conf\n' > "${PORT_ETC}/package.env/second"
	printf 'shared\n' > "${PORT_ETC}/env/shared.conf"
	printf 'other\n' > "${PORT_ETC}/env/other.conf"

	package_env_conf

	[[ -f "${PORT_ETC}/env/shared.conf" ]]
	[[ -f "${PORT_ETC}/env/other.conf" ]]
}

@test "package_env: lines without config tokens pass through verbatim" {
	printf '%s\n' \
		'cat-test/bare' \
		'cat-test/annotated  # keep me' \
		> "${PORT_ETC}/package.env"

	package_env

	run cat "${PORT_ETC}/package.env"
	assert_output "$(printf 'cat-test/bare\ncat-test/annotated  # keep me')"
}
