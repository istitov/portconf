#!/usr/bin/env bats
# Tests for world_backup() — creates a timestamped tarball of the world file
# in ${BRDIR}/world/, with rotation: when the count of existing backups
# reaches ${COUNT}, the oldest is deleted before the new one is created.
#
# Snapshots only when the world file is NEWER than the most recent backup.
#
# Dependencies overridden per test:
#   WORLD     — path to a scratch "world" file (note: filename MUST end in
#               "world" because the tar command derives the base dir via
#               ${WORLD%world} and tars the literal "world" entry)
#   BRDIR     — temp dir for backup output
#   COUNT     — rotation threshold (small values for test speed)

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	TEST_BRDIR="$(mktemp -d)"
	BRDIR="${TEST_BRDIR}"
	# WORLD must end in literal "world" because world_backup tars from
	# ${WORLD%world} with "world" as the relative path.  Live system uses
	# /var/lib/portage/world; we match the structure inside a tmp dir.
	mkdir -p "${TEST_BRDIR}/portage"
	WORLD="${TEST_BRDIR}/portage/world"
	printf 'sys-apps/portage\napp-portage/eix\n' > "${WORLD}"
	COUNT=10
}

teardown() {
	teardown_test_portage
	[[ -n "${TEST_BRDIR:-}" ]] && rm -rf "${TEST_BRDIR}"
}

# --- creation: fresh BRDIR/world/ gets one tarball ---

@test "world_backup: creates tarball in fresh BRDIR/world/" {
	world_backup
	run ls "${BRDIR}/world/"
	assert_success
	[[ "$(ls "${BRDIR}/world/" | wc -l)" -eq 1 ]]
}

@test "world_backup: COUNT=1 + empty world dir does not spuriously rotate" {
	# `wc -l <<< ""` counted an empty dir as 1, so count=1 >= COUNT=1 fired a
	# bare `rm "${world_dir}/"` (oldest empty): an error to stderr, and an abort
	# under the binary's set -e.  An empty dir must count as 0.
	COUNT=1
	local err; err="$(mktemp)"
	world_backup >/dev/null 2>"${err}"
	run cat "${err}"; rm -f "${err}"
	# no failed rotation rm of the backup directory itself reached stderr
	[[ "${output}" != *"${BRDIR}/world/"* ]]
	# and the backup was still created
	[ "$(ls -1 "${BRDIR}/world/"*.tar.bz2 2>/dev/null | wc -l)" -eq 1 ]
}

@test "world_backup: tarball filename matches world_<timestamp>.tar.bz2 pattern" {
	world_backup
	run ls "${BRDIR}/world/"
	[[ "${output}" =~ ^world_[0-9]+\.[0-9]+\.[0-9]+-[0-9]+:[0-9]+\.tar\.bz2$ ]]
}

@test "world_backup: tarball contains the world file" {
	world_backup
	local tarball
	tarball="$(ls "${BRDIR}/world/"*.tar.bz2)"
	run tar -tjf "${tarball}"
	assert_success
	[[ "${output}" == *'world'* ]]
}

@test "world_backup: tarball world file has the expected content" {
	world_backup
	local tarball extract_dir
	tarball="$(ls "${BRDIR}/world/"*.tar.bz2)"
	extract_dir="$(mktemp -d)"
	tar -xjf "${tarball}" -C "${extract_dir}"
	run cat "${extract_dir}/world"
	assert_output --partial 'sys-apps/portage'
	rm -rf "${extract_dir}"
}

# --- idempotency: world unchanged since last backup → no new tarball ---

@test "world_backup: idempotent — world file unchanged → no second tarball" {
	world_backup
	local first_count
	first_count="$(ls "${BRDIR}/world/" | wc -l)"
	# Ensure the world file's mtime is OLDER than the backup tarball.
	# The script's `(( world_update > portconf_update ))` guard then
	# returns the "already up-to-date" path.
	touch -d '1 minute ago' "${WORLD}"
	world_backup
	local second_count
	second_count="$(ls "${BRDIR}/world/" | wc -l)"
	[[ "${first_count}" -eq 1 && "${second_count}" -eq 1 ]]
}

@test "world_backup: prints 'already up-to-date' when world unchanged" {
	world_backup
	touch -d '1 minute ago' "${WORLD}"
	run world_backup
	[[ "${output}" == *'already up-to-date'* ]]
}

# --- rotation: count >= COUNT triggers deletion of the oldest tarball ---

@test "world_backup: rotation deletes oldest when count >= COUNT" {
	COUNT=2
	# Pre-seed two old backups with mtimes well in the past so they
	# sort before any newly-created backup.
	mkdir -p "${BRDIR}/world"
	: > "${BRDIR}/world/world_24.01.01-00:00.tar.bz2"
	: > "${BRDIR}/world/world_24.01.02-00:00.tar.bz2"
	touch -d '2 days ago'    "${BRDIR}/world/world_24.01.01-00:00.tar.bz2"
	touch -d '1 day ago'     "${BRDIR}/world/world_24.01.02-00:00.tar.bz2"
	# Make sure WORLD is newer than both, so a new backup is created.
	touch "${WORLD}"
	world_backup
	# After rotation: oldest (24.01.01) deleted, second seed survives,
	# new backup added → still 2 files.
	[[ "$(ls "${BRDIR}/world/" | wc -l)" -eq 2 ]]
	run ls "${BRDIR}/world/world_24.01.01-00:00.tar.bz2"
	assert_failure
}

@test "world_backup: rotation keeps the second-oldest after deleting oldest" {
	COUNT=2
	mkdir -p "${BRDIR}/world"
	: > "${BRDIR}/world/world_24.01.01-00:00.tar.bz2"
	: > "${BRDIR}/world/world_24.01.02-00:00.tar.bz2"
	touch -d '2 days ago' "${BRDIR}/world/world_24.01.01-00:00.tar.bz2"
	touch -d '1 day ago'  "${BRDIR}/world/world_24.01.02-00:00.tar.bz2"
	touch "${WORLD}"
	world_backup
	run ls "${BRDIR}/world/world_24.01.02-00:00.tar.bz2"
	assert_success
}
