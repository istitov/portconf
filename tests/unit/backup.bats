#!/usr/bin/env bats
# Tests for backup() — creates a dated bz2 tarball of PORT_ETC under BRDIR
# when portage files are newer than the most recent backup.
#
# Decision logic:
#   etc_update    = max mtime of all files under PORT_ETC
#   portconf_update = max mtime of files in BRDIR (0 when BRDIR is empty)
#   if etc_update > portconf_update → create new tarball
#   after a verified archive publishes, trim oldest files down to COUNT
#
# tar is stubbed to avoid writing real archives.
# eend/ebegin are stubbed via make_test_portage.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	TEST_BRDIR="$(mktemp -d)"
	BRDIR="${TEST_BRDIR}"
	COUNT=3
	# Stub tar: just touch the named output file (arg 2 of -jcf NAME …)
	tar() { touch "${2}"; return 0; }
}

teardown() {
	teardown_test_portage
	[[ -n "${TEST_BRDIR:-}" ]] && rm -rf "${TEST_BRDIR}"
}

# helper: create a fake dated backup file in BRDIR
_fake_backup() {
	touch "${TEST_BRDIR}/portage_${1}.tar.bz2"
}

@test "backup: BRDIR empty — backup tarball created" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	backup
	run bash -c "ls '${TEST_BRDIR}' | grep -c 'portage_'"
	assert_output "1"
}

@test "backup: BRDIR empty — tarball has correct name prefix" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	backup
	run bash -c "ls '${TEST_BRDIR}' | grep '^portage_.*\.tar\.bz2$'"
	assert_success
}

@test "backup: archive stamp uses the calendar year" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	date() {
		[[ "$1" == '+%y.%m.%d-%H:%M:%S' ]] || return 1
		printf '27.01.01-00:00:00\n'
	}
	backup
	[[ -f "${TEST_BRDIR}/portage_27.01.01-00:00:00.tar.bz2" ]]
}

@test "backup: BRDIR newer than PORT_ETC — no tarball created" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	touch -d '2020-01-01' "${TEST_PORT_ETC}/package.use"
	_fake_backup "20.01.02-12:00"
	touch -d '2020-01-02' "${TEST_BRDIR}/portage_20.01.02-12:00.tar.bz2"
	local before
	before="$(ls "${TEST_BRDIR}" | sort)"
	backup
	run bash -c "ls '${TEST_BRDIR}' | sort"
	assert_output "${before}"
}

@test "backup: count reaches COUNT — oldest tarball removed before creating new" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	# Pre-populate with COUNT old backups, older than PORT_ETC
	_fake_backup "19.01.01-00:00"
	_fake_backup "19.06.01-00:00"
	_fake_backup "19.12.01-00:00"
	touch -d '2019-01-01' "${TEST_BRDIR}"/portage_19.*.tar.bz2
	COUNT=3
	backup
	# oldest (19.01.01) removed, total still 3
	run bash -c "ls '${TEST_BRDIR}' | grep -c 'portage_'"
	assert_output "3"
	run bash -c "ls '${TEST_BRDIR}' | grep '19.01.01'"
	assert_failure
}

@test "backup: count below COUNT — no removal, total increases by one" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	_fake_backup "19.01.01-00:00"
	touch -d '2019-01-01' "${TEST_BRDIR}/portage_19.01.01-00:00.tar.bz2"
	COUNT=3
	backup
	run bash -c "ls '${TEST_BRDIR}' | grep -c 'portage_'"
	assert_output "2"
}

@test "backup: empty PORT_ETC — empty etc_update defaults to 0, no arithmetic error" {
	# make_test_portage gives an empty PORT_ETC. With no files, timestamp emits
	# nothing, so etc_update must default to 0 (like portconf_update) — otherwise
	# `(( etc_update > portconf_update ))` raises a bash arithmetic syntax error
	# and wrongly falls through to "already up-to-date", skipping the backup.
	run backup
	assert_success
	refute_output --partial 'arithmetic syntax'
	refute_output --regexp 'line [0-9]+:'
}

@test "backup: archive creation failure retains every existing snapshot" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	_fake_backup "19.01.01-00:00"
	_fake_backup "19.02.01-00:00"
	touch -d '2019-01-01' "${BRDIR}"/portage_19.*.tar.bz2
	local before
	before="$(find "${BRDIR}" -maxdepth 1 -type f -printf '%f\n' | sort)"
	tar() { return 1; }
	run backup
	[ "$status" -ne 0 ]
	[[ "$(find "${BRDIR}" -maxdepth 1 -type f -printf '%f\n' | sort)" == "${before}" ]]
}

@test "backup: verification failure retains every existing snapshot" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	_fake_backup "19.01.01-00:00"
	touch -d '2019-01-01' "${BRDIR}/portage_19.01.01-00:00.tar.bz2"
	local before
	before="$(find "${BRDIR}" -maxdepth 1 -type f -printf '%f\n' | sort)"
	tar() {
		if [[ "$1" == "-jcf" ]];then touch "$2"; return 0; fi
		return 1
	}
	run backup
	[ "$status" -ne 0 ]
	[[ "$(find "${BRDIR}" -maxdepth 1 -type f -name 'portage_*.tar.bz2' -printf '%f\n' | sort)" == "${before}" ]]
}

@test "backup: newer world backup directory does not suppress portage backup" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	mkdir -p "${BRDIR}/world"
	touch -d 'next year' "${BRDIR}/world/world_future.tar.bz2"
	backup
	[ "$(find "${BRDIR}" -maxdepth 1 -type f -name 'portage_*.tar.bz2' | wc -l)" -eq 1 ]
}
