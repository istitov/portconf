#!/usr/bin/env bats
# Integration tests for etc_restore() and world_restore() — the -r and -wr
# handlers.  Both wrap the shared restore() helper which:
#   1. Lists only tarballs matching the requested prefix under arg1
#      (BRDIR or BRDIR/world).
#   2. Presents them via `select` (PS3 prompt).
#   3. Validates every member, extracts into a same-filesystem staging dir,
#      and swaps the completed target through the shared undo journal.
#
# `select` reads its choice from stdin in bash, so the same stdin-piping
# technique used in overlays.bats works here — no expect harness needed.
# Tests use `run … <<< "1"` to pick the first listed backup.
#
# Sandboxed via PORT_ETC + BRDIR + WORLD overrides made available by the
# 2026-05-14 path-overridability refactor.

load 'test_helper'

# ---------- etc_restore ----------

@test "etc_restore: extracts selected backup into sandboxed PORT_ETC" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"

	# Build a "backup" tarball matching the format backup() produces:
	# top-level entry "portage/<contents>", named portage_<timestamp>.tar.bz2.
	local staging="${TEST_ROOT}/staging"
	mkdir -p "${staging}/portage"
	printf 'sys-apps/grep static\n' > "${staging}/portage/package.use"
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${staging}" portage

	# A "current" PORT_ETC content that the restore should overwrite.
	printf 'OLD\n' > "${PORT_ETC}/should_be_gone"

	run etc_restore <<< "1"
	[ "$status" -eq 0 ]
	# After restore: package.use is the tarball's version; the pre-existing
	# scratch file is gone (the wipe-before-extract contract).
	run cat "${PORT_ETC}/package.use"
	assert_output --partial 'sys-apps/grep static'
	run ls "${PORT_ETC}/should_be_gone"
	assert_failure
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: prints 'Rolling back' status with PORT_ETC path" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"

	local staging="${TEST_ROOT}/staging"
	mkdir -p "${staging}/portage"
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${staging}" portage

	run etc_restore <<< "1"
	[[ "${output}" == *"Rolling back ${PORT_ETC}"* ]]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: lists available backups" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"
	local staging="${TEST_ROOT}/staging"
	mkdir -p "${staging}/portage"

	# Two backups; the select prompt should enumerate both.
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" -C "${staging}" portage
	tar -jcf "${BRDIR}/portage_24.02.02-12:00.tar.bz2" -C "${staging}" portage

	run etc_restore <<< "1"
	[[ "${output}" == *'Available backups'* ]]
	# Both timestamps appear in the select listing.
	[[ "${output}" == *'24.01.01-12:00'* ]]
	[[ "${output}" == *'24.02.02-12:00'* ]]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: force mode ignores foreign bz2 files" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage"
	printf 'OLD\n' > "${PORT_ETC}/state"
	printf 'RESTORED\n' > "${TEST_ROOT}/staging/portage/state"
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage
	printf 'foreign\n' > "${BRDIR}/zzz.bz2"
	printf 'foreign\n' > "${BRDIR}/world_99.01.01-00:00.tar.bz2"
	_set_action_mode force
	run etc_restore </dev/null
	[ "$status" -eq 0 ]
	[[ "$(cat "${PORT_ETC}/state")" == "RESTORED" ]]
	[[ "${output}" != *"zzz"* ]]
	[[ "${output}" != *"world_"* ]]
	rm -rf "${TEST_ROOT}"
}

# ---------- world_restore ----------

@test "world_restore: extracts world file from selected backup" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	# WORLD must end in literal "world" — restore() extracts into
	# ${WORLD%world} and the tarball's top-level entry is "world".
	mkdir -p "${TEST_ROOT}/world_dir" "${BRDIR}/world"
	WORLD="${TEST_ROOT}/world_dir/world"
	printf 'OLD\n' > "${WORLD}"

	# Build a world backup that world_backup would produce.
	local staging="${TEST_ROOT}/staging"
	mkdir -p "${staging}"
	printf 'app-portage/portconf\nsys-apps/portage\n' > "${staging}/world"
	tar -jcf "${BRDIR}/world/world_24.01.01-12:00.tar.bz2" \
		-C "${staging}" world

	run world_restore <<< "1"
	[ "$status" -eq 0 ]
	run cat "${WORLD}"
	assert_output --partial 'app-portage/portconf'
	rm -rf "${TEST_ROOT}"
}

@test "world_restore: no destination-wipe (4-arg call) — pre-existing files in WORLD's dir survive" {
	# world_restore passes only 4 args to restore(), so the wipe-before-
	# extract branch never fires.  This is intentional: WORLD's parent is
	# /var/lib/portage/, which contains lots of unrelated portage state
	# (config-protect, world_sets, news/, etc.) that must NOT be wiped.
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${TEST_ROOT}/world_dir" "${BRDIR}/world"
	WORLD="${TEST_ROOT}/world_dir/world"
	# A pre-existing sibling file that must survive a restore.
	printf 'IMPORTANT\n' > "${TEST_ROOT}/world_dir/world_sets"

	local staging="${TEST_ROOT}/staging"
	mkdir -p "${staging}"
	printf 'newcontent\n' > "${staging}/world"
	tar -jcf "${BRDIR}/world/world_24.01.01-12:00.tar.bz2" \
		-C "${staging}" world

	run world_restore <<< "1"
	# world_sets must still exist — restore() didn't clear the parent dir.
	run ls "${TEST_ROOT}/world_dir/world_sets"
	assert_success
	rm -rf "${TEST_ROOT}"
}

# ---------- restore() safety: never wipe without a verified extract ----------

@test "etc_restore: corrupt tarball leaves PORT_ETC intact (validate before wipe)" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"
	printf 'KEEP\n' > "${PORT_ETC}/should_survive"
	# Not a valid archive — tar -tf must reject it before any wipe happens.
	printf 'this is not a tarball\n' > "${BRDIR}/portage_24.01.01-12:00.tar.bz2"
	run etc_restore <<< "1"
	[ "$status" -eq 1 ]
	[[ "${output}" == *'unsafe, unreadable, or corrupt'* ]]
	# The live tree must be untouched.
	run cat "${PORT_ETC}/should_survive"
	assert_output 'KEEP'
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: out-of-range menu choice does not wipe PORT_ETC" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"
	printf 'KEEP\n' > "${PORT_ETC}/should_survive"
	local staging="${TEST_ROOT}/staging"
	mkdir -p "${staging}/portage"
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" -C "${staging}" portage
	# "99" is out of range → select leaves answer empty → must re-prompt, not wipe.
	run etc_restore <<< "99"
	[[ "${output}" == *'Invalid choice'* ]]
	run cat "${PORT_ETC}/should_survive"
	assert_output 'KEEP'
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: empty backup dir reports cleanly without aborting" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"
	run etc_restore <<< "1"
	[ "$status" -eq 0 ]
	[[ "${output}" == *'No backups'* ]]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: empty inventory does not leak nullglob" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}"
	shopt -u nullglob

	etc_restore </dev/null >/dev/null

	run shopt -p nullglob
	assert_output 'shopt -u nullglob'
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: sibling-prefix member is rejected without an out-of-root write" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage-sibling"
	printf 'KEEP\n' > "${PORT_ETC}/should_survive"
	printf 'ESCAPE\n' > "${TEST_ROOT}/staging/portage-sibling/owned"
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage-sibling
	run etc_restore <<< "1"
	[ "$status" -eq 1 ]
	[[ "${output}" == *'unsafe, unreadable, or corrupt'* ]]
	[[ "$(cat "${PORT_ETC}/should_survive")" == 'KEEP' ]]
	[ ! -e "${TEST_ROOT}/etc/portage-sibling" ]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: preserves a normal external make.profile symlink" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage"
	ln -s ../../profiles/default "${TEST_ROOT}/staging/portage/make.profile"
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage
	run etc_restore <<< "1"
	[ "$status" -eq 0 ]
	[ -L "${PORT_ETC}/make.profile" ]
	[[ "$(readlink "${PORT_ETC}/make.profile")" == "../../profiles/default" ]]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: archive member cannot write through an archived symlink" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage" "${TEST_ROOT}/outside"
	printf 'KEEP\n' > "${PORT_ETC}/state"
	ln -s ../../outside "${TEST_ROOT}/staging/portage/escape"
	printf 'ESCAPE\n' > "${TEST_ROOT}/payload"
	tar -cf "${BRDIR}/portage_24.01.01-12:00.tar" -C "${TEST_ROOT}/staging" portage
	tar --append --transform='s|^payload$|portage/escape/owned|' \
		-f "${BRDIR}/portage_24.01.01-12:00.tar" -C "${TEST_ROOT}" payload
	bzip2 "${BRDIR}/portage_24.01.01-12:00.tar"
	run etc_restore <<< "1"
	[ "$status" -eq 1 ]
	[[ "$(cat "${PORT_ETC}/state")" == "KEEP" ]]
	[ ! -e "${TEST_ROOT}/outside/owned" ]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: extraction failure leaves the live tree intact" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage"
	printf 'KEEP\n' > "${PORT_ETC}/should_survive"
	printf 'NEW\n' > "${TEST_ROOT}/staging/portage/new-file"
	command tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage
	tar() {
		[[ "$1" == "--extract" ]] && return 1
		command tar "$@"
	}
	run etc_restore <<< "1"
	[ "$status" -eq 1 ]
	[[ "${output}" == *'live target unchanged'* ]]
	[[ "$(command cat "${PORT_ETC}/should_survive")" == 'KEEP' ]]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: failed final rename rolls the original tree back" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage"
	printf 'KEEP\n' > "${PORT_ETC}/should_survive"
	printf 'NEW\n' > "${TEST_ROOT}/staging/portage/new-file"
	command tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage
	local failed=""
	mv() {
		if [[ -z "${failed}" && "$3" == "${PORT_ETC}" ]];then
			failed=1
			return 1
		fi
		command mv "$@"
	}
	run etc_restore <<< "1"
	[ "$status" -eq 1 ]
	[[ "$(command cat "${PORT_ETC}/should_survive")" == 'KEEP' ]]
	[ ! -e "${PORT_ETC}/new-file" ]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: restores archived file and directory permissions" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage/private"
	printf 'KEEP\n' > "${TEST_ROOT}/staging/portage/private/secret"
	chmod 0750 "${TEST_ROOT}/staging/portage/private"
	chmod 0600 "${TEST_ROOT}/staging/portage/private/secret"
	tar -jcf "${BRDIR}/portage_24.01.01-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage
	etc_restore <<< "1"
	[[ "$(stat -c %a "${PORT_ETC}/private")" == '750' ]]
	[[ "$(stat -c %a "${PORT_ETC}/private/secret")" == '600' ]]
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: force mode handles BRDIR with trailing slash" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf/"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage"
	printf 'sys-apps/grep static\n' > "${TEST_ROOT}/staging/portage/package.use"
	tar -jcf "${BRDIR}portage_24.01.01-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage
	_set_action_mode force

	run etc_restore
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Selecting newest backup: 24.01.01-12:00"* ]]
	run cat "${PORT_ETC}/package.use"
	assert_output --partial 'sys-apps/grep static'
	rm -rf "${TEST_ROOT}"
}

@test "etc_restore: follows symlinked backups in BRDIR" {
	load_portconf
	make_test_portage
	TEST_ROOT="$(mktemp -d)"
	PORT_ETC="${TEST_ROOT}/etc/portage"
	BRDIR="${TEST_ROOT}/var/lib/portconf/"
	mkdir -p "${PORT_ETC}" "${BRDIR}" "${TEST_ROOT}/staging/portage" "${TEST_ROOT}/link-target"
	printf 'sys-apps/grep static\n' > "${TEST_ROOT}/staging/portage/package.use"
	mkdir -p "${TEST_ROOT}/link-target"
	tar -jcf "${TEST_ROOT}/link-target/portage_24.02.02-12:00.tar.bz2" \
		-C "${TEST_ROOT}/staging" portage
	ln -s "${TEST_ROOT}/link-target/portage_24.02.02-12:00.tar.bz2" "${BRDIR}portage_24.02.02-12:00.tar.bz2"
	_set_action_mode force

	run etc_restore
	[ "$status" -eq 0 ]
	run cat "${PORT_ETC}/package.use"
	assert_output --partial 'sys-apps/grep static'
	rm -rf "${TEST_ROOT}"
}
