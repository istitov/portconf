#!/usr/bin/env bats
# End-to-end contract for the process-wide action policy.

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH"
	smoke_sandbox
}

teardown() {
	smoke_cleanup
}

_write_commented_fixture() {
	printf '# remove me\nsys-apps/grep static\n' > "${SMOKE_PORT_ETC}/package.use"
}

_assert_no_backup() {
	[[ -z "$(find "${SMOKE_BRDIR}" -type f -name '*.tar.bz2' -print -quit)" ]]
}

_run_mode() {
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" \
		BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" \
		DEP_PATH="${SMOKE_DEP}" \
		PORTCONF_CONF=/dev/null \
		"${PORTCONF_BIN}" "$@"
}

@test "action mode: default is a dry-run, including backup" {
	_write_commented_fixture
	_run_mode -c
	[ "$status" -eq 0 ]
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == $'# remove me\nsys-apps/grep static' ]]
	_assert_no_backup
	assert_output_contains 'nothing written'
}

@test "action mode: --ask applies an accepted change" {
	_write_commented_fixture
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" DEP_PATH="${SMOKE_DEP}" \
		PORTCONF_CONF=/dev/null \
		"${PORTCONF_BIN}" --ask -c <<< $'Yes\n'
	[ "$status" -eq 0 ]
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == 'sys-apps/grep static' ]]
	[[ -n "$(find "${SMOKE_BRDIR}" -type f -name 'portage_*.tar.bz2' -print -quit)" ]]
}

@test "action mode: concurrent apply is rejected while dry-run remains available" {
	_write_commented_fixture
	local lock_file="${SMOKE_BRDIR}/.portconf.lock"
	exec 8>>"${lock_file}"
	flock -n 8
	_run_mode --force -c </dev/null
	[ "$status" -ne 0 ]
	assert_output_contains 'another applying process is already running'
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == $'# remove me\nsys-apps/grep static' ]]
	_run_mode -c
	[ "$status" -eq 0 ]
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == $'# remove me\nsys-apps/grep static' ]]
	exec 8>&-
}

@test "action mode: --force applies without reading stdin" {
	_write_commented_fixture
	_run_mode --force -c </dev/null
	[ "$status" -eq 0 ]
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == 'sys-apps/grep static' ]]
}

@test "action mode: -y remains a compatibility alias for --force" {
	_write_commented_fixture
	_run_mode -y -c </dev/null
	[ "$status" -eq 0 ]
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == 'sys-apps/grep static' ]]
}

@test "action mode: explicit pretend wins over legacy -y" {
	_write_commented_fixture
	_run_mode -y -p -c
	[ "$status" -eq 0 ]
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == $'# remove me\nsys-apps/grep static' ]]
	_assert_no_backup
}

@test "action mode: contradictory apply modes fail before dispatch" {
	_run_mode --ask --force -c
	[ "$status" -eq 2 ]
	assert_output_contains 'cannot be used together'
	_assert_no_backup
}

@test "action mode: --force does not collide with --force-trash" {
	_run_mode --force-trash
	[ "$status" -eq 0 ]
	[[ "$(cat "${SMOKE_PORT_ETC}/package.use")" == 'sys-apps/grep static' ]]
	_assert_no_backup
	[[ "$(strip_ansi "${output}")" != *'Unknown option'* ]]
}

@test "action mode: default dry-run does not convert files to directories" {
	_run_mode -f2d
	[ "$status" -eq 0 ]
	[ -f "${SMOKE_PORT_ETC}/package.use" ]
	_assert_no_backup
}

@test "action mode: default dry-run does not convert directories to files" {
	rm -f "${SMOKE_PORT_ETC}/package.use"
	mkdir "${SMOKE_PORT_ETC}/package.use"
	printf 'sys-apps/grep static\n' > "${SMOKE_PORT_ETC}/package.use/grep"
	_run_mode -d2f
	[ "$status" -eq 0 ]
	[ -d "${SMOKE_PORT_ETC}/package.use" ]
	[ -f "${SMOKE_PORT_ETC}/package.use/grep" ]
	_assert_no_backup
}

@test "action mode: default restore lists snapshots without extracting" {
	local marker="${SMOKE_PORT_ETC}/marker"
	printf 'live\n' > "${marker}"
	# Restore must return before inspecting or extracting archive members.
	printf 'not an archive\n' > "${SMOKE_BRDIR}/portage_26.08.03-12:00.tar.bz2"
	_run_mode -r
	[ "$status" -eq 0 ]
	[[ "$(cat "${marker}")" == 'live' ]]
	assert_output_contains 'dry-run, no restore performed'
}

@test "action mode: --force world restore selects the newest snapshot" {
	mkdir -p "${SMOKE_PORT_ETC}/world-dir" "${SMOKE_BRDIR}/world"
	local world_file="${SMOKE_PORT_ETC}/world-dir/world"
	local stage="${SMOKE_PORT_ETC}/world-stage"
	mkdir -p "${stage}"
	printf 'old snapshot\n' > "${stage}/world"
	tar -jcf "${SMOKE_BRDIR}/world/world_26.08.02-12:00.tar.bz2" -C "${stage}" world
	printf 'new snapshot\n' > "${stage}/world"
	tar -jcf "${SMOKE_BRDIR}/world/world_26.08.03-12:00.tar.bz2" -C "${stage}" world
	printf 'live\n' > "${world_file}"
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" DEP_PATH="${SMOKE_DEP}" \
		WORLD="${world_file}" PORTCONF_CONF=/dev/null \
		"${PORTCONF_BIN}" --force -wr </dev/null
	[ "$status" -eq 0 ]
	[[ "$(cat "${world_file}")" == 'new snapshot' ]]
	assert_output_contains 'Selecting newest backup'
}

@test "action mode: default world regeneration leaves world untouched" {
	mkdir -p "${SMOKE_PORT_ETC}/world-dir"
	local world_file="${SMOKE_PORT_ETC}/world-dir/world"
	printf 'sys-apps/portage\n' > "${world_file}"
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" DEP_PATH="${SMOKE_DEP}" \
		WORLD="${world_file}" PORTCONF_CONF=/dev/null \
		"${PORTCONF_BIN}" -wg
	[ "$status" -eq 0 ]
	[[ "$(cat "${world_file}")" == 'sys-apps/portage' ]]
	_assert_no_backup
	assert_output_contains 'Would regenerate'
}

@test "action mode: default overlay cleanup only reports unused repositories" {
	local repo="${SMOKE_PORT_ETC}/unused-repo"
	mkdir -p "${repo}" "${SMOKE_PORT_ETC}/repos.conf"
	printf '[unused]\nlocation = %s\n' "${repo}" > "${SMOKE_PORT_ETC}/repos.conf/unused.conf"
	_run_mode -fr
	[ "$status" -eq 0 ]
	[ -d "${repo}" ]
	[ -f "${SMOKE_PORT_ETC}/repos.conf/unused.conf" ]
	assert_output_contains 'Unused repos (would remove)'
}
