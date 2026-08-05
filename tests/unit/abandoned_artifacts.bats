#!/usr/bin/env bats
# Hard-kill residue cleanup and recovery policy.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	TEST_BRDIR="$(mktemp -d)"
	BRDIR="${TEST_BRDIR}"
	PORTCONF_LOCK_FILE="${BRDIR}/portconf.lock"
	_acquire_write_lock
}

teardown() {
	if [[ -n "${_write_lock_fd:-}" ]];then
		exec {_write_lock_fd}>&-
		_write_lock_fd=""
	fi
	teardown_test_portage
	rm -rf "${TEST_BRDIR}"
	[[ -n "${TEST_SWEEP_ROOT:-}" ]] && rm -rf "${TEST_SWEEP_ROOT}"
	return 0
}

_age_artifact() {
	touch -h -d '1 minute ago' "$1"
}

@test "abandoned artifacts: recursively removes old stages after locking" {
	local stage_file stage_dir
	mkdir -p "${PORT_ETC}/package.use/nested"
	stage_file="${PORT_ETC}/.make.conf.portconf-stage.A1b2C3"
	stage_dir="${PORT_ETC}/package.use/nested/.entry.portconf-stage.D4e5F6"
	printf 'partial\n' > "${stage_file}"
	mkdir "${stage_dir}"
	printf 'partial\n' > "${stage_dir}/content"
	_age_artifact "${stage_file}"
	_age_artifact "${stage_dir}"

	_sweep_abandoned_artifacts

	[[ ! -e "${stage_file}" ]]
	[[ ! -e "${stage_dir}" ]]
	[[ -d "${PORT_ETC}/package.use/nested" ]]
}

@test "abandoned artifacts: refuses cleanup without the writer lock" {
	local stage="${PORT_ETC}/.make.conf.portconf-stage.A1b2C3"
	printf 'partial\n' > "${stage}"
	_age_artifact "${stage}"
	exec {_write_lock_fd}>&-
	_write_lock_fd=""

	run _sweep_abandoned_artifacts

	[ "${status}" -ne 0 ]
	[[ "${output}" == *'without the writer lock'* ]]
	[[ "$(cat "${stage}")" == 'partial' ]]
}

@test "abandoned artifacts: refuses a filesystem-root sweep" {
	PORT_ETC="/"

	run _sweep_abandoned_artifacts

	[ "${status}" -ne 0 ]
	[[ "${output}" == *'at filesystem root'* ]]
}

@test "abandoned artifacts: leaves artifacts created after process start" {
	local stage="${PORT_ETC}/.make.conf.portconf-stage.A1b2C3"
	printf 'current\n' > "${stage}"
	touch -d '1 minute' "${stage}"

	_sweep_abandoned_artifacts

	[[ -f "${stage}" ]]
}

@test "abandoned artifacts: removes an old empty transaction holder" {
	local holder="${PORT_ETC}/.make.conf.portconf-txn.A1b2C3"
	mkdir "${holder}"
	_age_artifact "${holder}"

	_sweep_abandoned_artifacts

	[[ ! -e "${holder}" ]]
}

@test "abandoned artifacts: preserves all recovery material and blocks apply" {
	local holder stage
	holder="${PORT_ETC}/.make.conf.portconf-txn.A1b2C3"
	stage="${PORT_ETC}/.make.conf.portconf-stage.D4e5F6"
	mkdir "${holder}"
	printf 'original\n' > "${holder}/original"
	printf 'replacement\n' > "${stage}"
	_age_artifact "${holder}"
	_age_artifact "${stage}"

	run _sweep_abandoned_artifacts

	[ "${status}" -ne 0 ]
	[[ "${output}" == *'recoverable abandoned transaction holder'* ]]
	[[ "$(cat "${holder}/original")" == 'original' ]]
	[[ "$(cat "${stage}")" == 'replacement' ]]
}

@test "abandoned artifacts: a sibling of a sweep root is left alone" {
	# Every sweep root must be a directory portconf itself stages into, never
	# a PARENT of one.  DEP_PATH is the case that bites: relocating it (which
	# every test tier does) puts its parent in a shared temp directory, so a
	# parent-scoped sweep inspected — and refused to run because of —
	# artifacts belonging to entirely unrelated trees.
	local root holder
	TEST_SWEEP_ROOT="$(mktemp -d)"
	root="${TEST_SWEEP_ROOT}"
	mkdir -p "${root}/cache/dep"
	DEP_PATH="${root}/cache/dep"
	holder="${root}/cache/.unrelated.portconf-txn.A1b2C3"
	mkdir "${holder}"
	printf 'someone else\n' > "${holder}/original"
	_age_artifact "${holder}"

	run _sweep_abandoned_artifacts

	[ "${status}" -eq 0 ]
	[[ -f "${holder}/original" ]]
}
