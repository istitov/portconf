#!/usr/bin/env bats
# Integration tests for backup() with PORT_ETC + BRDIR overridden.
#
# The path-handling refactor (see commit history) made backup() derive
# its tar working-dir from ${PORT_ETC%/*} (parent) and ${PORT_ETC##*/}
# (basename), gated the legacy /etc/make.conf inclusion on
# PORT_ETC == /etc/portage, and routed all output through the configured
# config tree.  These tests verify that contract.
#
# A unit-tier backup test (tests/unit/backup.bats) already covers the
# rotation and timestamp-skip logic with the canonical /etc/portage
# layout in mind; this integration tier specifically exercises the
# OVERRIDDEN paths.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	# Sandbox both BRDIR and PORT_ETC.  Use a structured layout so that
	# ${PORT_ETC%/*} (parent) and ${PORT_ETC##*/} (basename) come out
	# stably for assertions.
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"
	# Populate a couple of typical config files so the tar isn't empty.
	printf 'sys-apps/grep static\n' > "${PORT_ETC}/package.use"
	printf 'USE="x11"\n' > "${PORT_ETC}/make.conf"
	COUNT=10
}

teardown() {
	teardown_test_portage
	[[ -n "${TEST_ROOT:-}" ]] && rm -rf "${TEST_ROOT}"
}

@test "backup: sandboxed PORT_ETC produces tarball in sandboxed BRDIR" {
	backup
	# Exactly one new tarball under the sandboxed BRDIR.
	[[ "$(ls "${BRDIR}" | wc -l)" -eq 1 ]]
	run ls "${BRDIR}/"
	[[ "${output}" =~ ^portage_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+:[0-9]+:[0-9]+\.tar\.bz2$ ]]
}

@test "backup: tarball contains the sandboxed PORT_ETC contents" {
	backup
	local tarball
	tarball="$(ls "${BRDIR}/"*.tar.bz2)"
	run tar -tjf "${tarball}"
	assert_success
	# The tar entry is the basename of PORT_ETC (i.e. "portage"), and
	# package.use must be present.
	[[ "${output}" == *'portage/package.use'* ]]
}

@test "backup: tarball excludes portconf staging and transaction artifacts" {
	mkdir -p "${PORT_ETC}/package.mask/.entry.portconf-txn.A1b2C3"
	printf 'partial rewrite\n' > "${PORT_ETC}/.make.conf.portconf-stage.D4e5F6"
	printf 'saved original\n' > "${PORT_ETC}/package.mask/.entry.portconf-txn.A1b2C3/original"

	backup

	local tarball
	tarball="$(ls "${BRDIR}/"*.tar.bz2)"
	run tar -tjf "${tarball}"
	assert_success
	[[ "${output}" != *'.portconf-stage.'* ]]
	[[ "${output}" != *'.portconf-txn.'* ]]
}

@test "backup: tarball does NOT include host /etc/make.conf when PORT_ETC overridden" {
	# Critical safety property: a sandboxed PORT_ETC must never pull the
	# host's legacy /etc/make.conf into a test tarball.  The legacy
	# fallback is gated on PORT_ETC == /etc/portage exactly to prevent
	# this leak.
	backup
	local tarball
	tarball="$(ls "${BRDIR}/"*.tar.bz2)"
	# tar entries under the override should ONLY be under the basename
	# of the configured PORT_ETC ("portage/...").  No bare "make.conf"
	# at the top level of the archive.
	run tar -tjf "${tarball}"
	[[ "${output}" != *$'\nmake.conf'* ]]
	# The package.use we added is captured (sanity check).
	[[ "${output}" == *'portage/package.use'* ]]
}

@test "backup: status line announces the configured PORT_ETC path" {
	# After the refactor the announcement uses ${PORT_ETC} verbatim
	# instead of the literal "/etc/portage" string — visible feedback
	# that the override is in effect.
	run backup
	[[ "${output}" == *"${PORT_ETC}"*'backup'* ]]
}

@test "backup: idempotent — re-running when nothing changed produces no new tarball" {
	backup
	# Force PORT_ETC entries' mtimes to be older than the tarball.
	find "${PORT_ETC}" -type f -exec touch -d '1 minute ago' {} +
	run backup
	[[ "${output}" == *'already up-to-date'* ]]
	[[ "$(ls "${BRDIR}" | wc -l)" -eq 1 ]]
}
