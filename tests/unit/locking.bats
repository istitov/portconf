#!/usr/bin/env bats
# Process-wide writer-lock policy and contention behaviour.

load 'test_helper'

setup() {
	load_portconf
	LOCK_ROOT="$(mktemp -d)"
	PORTCONF_LOCK_FILE="${LOCK_ROOT}/portconf.lock"
}

teardown() {
	if [[ -n "${_write_lock_fd:-}" ]];then
		exec {_write_lock_fd}>&-
		_write_lock_fd=""
	fi
	rm -rf "${LOCK_ROOT}"
}

@test "_needs_write_lock: true for every mutating short flag" {
	local flag
	for flag in -b -r -s -us -ui -um -sup -uf -ko -ku -t -sm -sum -ft \
		-c -ac -f -f2d -d2f -wb -wr -wg -fr;do
		_needs_write_lock "${flag}" || false
	done
}

@test "_needs_write_lock: true for every mutating long flag" {
	local flag
	for flag in --backup --restore --sort --use-sort --use-invalid --use-make \
		--stupid-use-profile --use-full --keyword-one --keyword-uniq --trash \
		--stupid-mask --stupid-unmask --force-trash --rm-comments \
		--rm-all-comments --full --files-2-dirs --dirs-2-files --world-backup \
		--world-restore --world-regen --fix-repos;do
		_needs_write_lock "${flag}" || false
	done
}

@test "_needs_write_lock: false for read-only and mode-only tokens" {
	local flag
	for flag in -apu -pu -cpu -V -h -p -y --ask --force --version --help;do
		if _needs_write_lock "${flag}";then false;fi
	done
}

@test "_acquire_write_lock: creates and holds the configured lock" {
	_acquire_write_lock
	[ -f "${PORTCONF_LOCK_FILE}" ]
	if flock -n "${PORTCONF_LOCK_FILE}" -c true;then
		false
	fi
}

@test "_acquire_write_lock: contention fails clearly" {
	exec 8>>"${PORTCONF_LOCK_FILE}"
	flock -n 8
	run _acquire_write_lock
	[ "$status" -ne 0 ]
	[[ "${output}" == *'another applying process is already running'* ]]
	exec 8>&-
}

@test "_acquire_write_lock: refuses a symlink lock path" {
	printf 'do not touch\n' > "${LOCK_ROOT}/target"
	ln -s "${LOCK_ROOT}/target" "${PORTCONF_LOCK_FILE}"
	run _acquire_write_lock
	[ "$status" -ne 0 ]
	[[ "${output}" == *'refusing unsafe lock path'* ]]
	[[ "$(cat "${LOCK_ROOT}/target")" == 'do not touch' ]]
}
