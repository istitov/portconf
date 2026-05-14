#!/usr/bin/env bats
# Integration tests for etc_restore() and world_restore() — the -r and -wr
# handlers.  Both wrap the shared restore() helper which:
#   1. Lists existing tarballs under arg1 (BRDIR or BRDIR/world).
#   2. Presents them via `select` (PS3 prompt).
#   3. On selection, wipes the destination's contents (arg5) and extracts
#      the chosen tarball into arg4.
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
