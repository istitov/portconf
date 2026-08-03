#!/usr/bin/env bats
# Shared undo-journal and same-filesystem replacement primitives.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	TXN_ROOT="$(mktemp -d)"
}

teardown() {
	[[ -n "${_txn_open:-}" ]] && _txn_rollback || true
	teardown_test_portage
	rm -rf "${TXN_ROOT}"
}

@test "transaction: rollback restores a replaced file" {
	local target="${TXN_ROOT}/target" staged
	printf 'original\n' > "${target}"
	staged="$(_mktemp_near "${target}")"
	printf 'replacement\n' > "${staged}"
	_txn_begin
	_txn_replace "${staged}" "${target}"
	[[ "$(cat "${target}")" == 'replacement' ]]
	_txn_rollback
	[[ "$(cat "${target}")" == 'original' ]]
}

@test "transaction: commit keeps replacement and removes holders" {
	local target="${TXN_ROOT}/target" staged
	printf 'original\n' > "${target}"
	staged="$(_mktemp_near "${target}")"
	printf 'replacement\n' > "${staged}"
	_txn_begin
	_txn_replace "${staged}" "${target}"
	_txn_commit
	[[ "$(cat "${target}")" == 'replacement' ]]
	[[ -z "$(find "${TXN_ROOT}" -maxdepth 1 -name '.*.portconf-txn.*' -print -quit)" ]]
}

@test "transaction: snapshot rolls external edits back" {
	local target="${TXN_ROOT}/config"
	mkdir "${target}"
	printf 'before\n' > "${target}/repo.conf"
	_txn_begin
	_txn_snapshot "${target}"
	printf 'after\n' > "${target}/repo.conf"
	_txn_rollback
	[[ "$(cat "${target}/repo.conf")" == 'before' ]]
}

@test "transaction: quarantine rollback restores a directory tree" {
	local target="${TXN_ROOT}/repo"
	mkdir "${target}"
	printf 'payload\n' > "${target}/file"
	_txn_begin
	_txn_quarantine "${target}"
	[ ! -e "${target}" ]
	_txn_rollback
	[[ "$(cat "${target}/file")" == 'payload' ]]
}

@test "transaction: failed final rename restores the original" {
	local target="${TXN_ROOT}/target" staged fail_source
	printf 'original\n' > "${target}"
	staged="$(_mktemp_near "${target}")"
	printf 'replacement\n' > "${staged}"
	fail_source="${staged}"
	mv() {
		if [[ "$2" == "${fail_source}" ]];then
			return 1
		fi
		command mv "$@"
	}
	_txn_begin
	run _txn_replace "${staged}" "${target}"
	[ "$status" -ne 0 ]
	[[ "$(cat "${target}")" == 'original' ]]
}

@test "transaction: later holder-allocation failure rolls back earlier replacements" {
	local target_a="${TXN_ROOT}/target-a" target_b="${TXN_ROOT}/target-b"
	local staged_a staged_b
	printf 'original-a\n' > "${target_a}"
	printf 'original-b\n' > "${target_b}"
	staged_a="$(_mktemp_near "${target_a}")"
	staged_b="$(_mktemp_near "${target_b}")"
	printf 'replacement-a\n' > "${staged_a}"
	printf 'replacement-b\n' > "${staged_b}"
	mktemp() {
		[[ "$*" == *'.target-b.portconf-txn.'* ]] && return 1
		command mktemp "$@"
	}
	_txn_begin
	_txn_replace "${staged_a}" "${target_a}"
	if _txn_replace "${staged_b}" "${target_b}";then
		false
	fi
	[[ -z "${_txn_open}" ]]
	[[ "$(cat "${target_a}")" == 'original-a' ]]
	[[ "$(cat "${target_b}")" == 'original-b' ]]
}

@test "transaction: failed original restore keeps both copies recoverable" {
	local target="${TXN_ROOT}/target" staged holder
	printf 'original\n' > "${target}"
	staged="$(_mktemp_near "${target}")"
	printf 'replacement\n' > "${staged}"
	_txn_begin
	_txn_replace "${staged}" "${target}"
	holder="${_txn_holders[0]}"
	mv() {
		if [[ "$2" == "${holder}/original" && "$3" == "${target}" ]];then
			return 1
		fi
		command mv "$@"
	}
	if _txn_rollback;then
		false
	fi
	[[ "$(cat "${target}")" == 'replacement' ]]
	[[ "$(cat "${holder}/original")" == 'original' ]]
}

@test "transaction: cleanup rolls an open journal back before deleting stages" {
	local target="${TXN_ROOT}/target" staged
	printf 'original\n' > "${target}"
	staged="$(_mktemp_near "${target}")"
	printf 'replacement\n' > "${staged}"
	_txn_begin
	_txn_replace "${staged}" "${target}"
	_cleanup
	[[ "$(cat "${target}")" == 'original' ]]
}
