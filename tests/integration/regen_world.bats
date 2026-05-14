#!/usr/bin/env bats
# Integration tests for regen_world() — the -wg handler that rebuilds
# the @world file to contain only direct user installs (excluding
# dependencies, virtuals, and library packages).
#
# Stubs the four real Portage tools regen_world consumes:
#   qlist -CI                                 → installed-package list
#   emerge -eopd --columns --with-bdeps=y     → dep-tree pretend output
#   emerge -epO system                        → system-set pretend
#   emerge -pc                                → depclean pretend
#
# Sandboxes WORLD via the env override.  Pipes "No" to the interactive
# "save some packages?" prompts.
#
# Coverage focus: the filter logic at line ~1596 — an installed atom is
# added to the new world unless (a) it's listed in pretend, (b) it
# matches "*-libs/", or (c) it matches "virtual/".  Plus the diff_ask
# auto-apply contract under yes="1".

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
	# Sandbox WORLD.  Must end in literal "world" — the script does
	# string manipulation that assumes this filename.
	TEST_ROOT="$(mktemp -d)"
	mkdir -p "${TEST_ROOT}/world_dir"
	WORLD="${TEST_ROOT}/world_dir/world"
	printf 'app-misc/foo\ndev-libs/bar\nvirtual/baz\nsys-apps/portage\n' > "${WORLD}"
}

teardown() {
	teardown_test_portage
	[[ -n "${TEST_ROOT:-}" ]] && rm -rf "${TEST_ROOT}"
}

# Dispatching qlist stub.  Strips -* flags from argv to find atom args.
#   No atom args → return the canonical installed list (QLIST_INSTALLED).
#                  This matches real qlist -CI behaviour when invoked
#                  without filter args (it lists every installed package).
#                  NOTE: regen_world line ~1594 unconditionally pipes
#                  through `qlist -CI $(emerge -epO system | awk ...)`,
#                  and when emerge -epO produces empty output this becomes
#                  `qlist -CI` with no atom args → returns ALL installed →
#                  every atom ends up in pretend → nothing gets cleaned.
#                  Tests set EMERGE_SYSTEM to drive this path explicitly.
#   With atom args → emit each one (simulates the "filter installed by
#                    these atoms" behaviour qlist -CI <atoms> performs).
qlist() {
	local -a atoms=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
			-*) shift ;;
			*)  atoms+=("$1"); shift ;;
		esac
	done
	if [[ ${#atoms[@]} -eq 0 ]]; then
		printf '%s\n' "${QLIST_INSTALLED:-}"
	else
		printf '%s\n' "${atoms[@]}"
	fi
}

# Dispatching emerge stub:
#   -eopd --columns ... → dep-tree pretend (sets which atoms are "in pretend"
#                         and therefore EXCLUDED from new world)
#   -epO system         → system-set list (further refined via qlist)
#   -pc                 → depclean output (empty by default → ask() returns
#                         early without prompting)
#   -Own ...            → never called in these tests (we pipe "No")
emerge() {
	case "$*" in
		*'-eopd'*)
			# Emit one [ebuild] line per atom in EMERGE_PRETEND.  awk $4
			# extracts the atom — match the column layout `[ebuild U ] <atom>`.
			local atom
			for atom in ${EMERGE_PRETEND:-}; do
				printf '[ebuild U ] %s USE="x"\n' "${atom}"
			done
			;;
		*'-epO'*)
			# System set: emit `[ebuild ...] <atom>` lines.  Empty by
			# default — no atoms get added from the system-set path.
			local atom
			for atom in ${EMERGE_SYSTEM:-}; do
				printf '[ebuild U ] %s USE="x"\n' "${atom}"
			done
			;;
		*'-pc'*)
			# Depclean pretend.  Empty list = nothing to save = ask()
			# returns 0 without prompting.
			printf 'All selected packages: %s\n' "${EMERGE_DEPCLEAN:-}"
			;;
		*)
			return 0
			;;
	esac
}

# --- core filter logic ---

# Tests can leave EMERGE_SYSTEM unset (empty system-set output).  The
# HIGH#3 fix in regen_world guards the qlist-CI call with an empty-args
# check, so an empty EMERGE_SYSTEM no longer pollutes pretend with the
# entire installed list.

@test "regen_world: 'virtual/' atoms are excluded from new world" {
	QLIST_INSTALLED=$'app-misc/foo\nvirtual/baz'
	EMERGE_PRETEND=""
	regen_world <<< $'No\nNo\nNo\nNo\n'
	run cat "${WORLD}"
	assert_output --partial 'app-misc/foo'
	[[ "${output}" != *'virtual/baz'* ]]
}

@test "regen_world: '*-libs/' atoms are excluded from new world" {
	QLIST_INSTALLED=$'app-misc/foo\ndev-libs/bar'
	EMERGE_PRETEND=""
	regen_world <<< $'No\nNo\nNo\nNo\n'
	run cat "${WORLD}"
	assert_output --partial 'app-misc/foo'
	[[ "${output}" != *'dev-libs/bar'* ]]
}

@test "regen_world: atoms appearing in 'emerge -eopd' pretend are excluded" {
	QLIST_INSTALLED=$'app-misc/foo\napp-misc/bar'
	EMERGE_PRETEND='app-misc/foo'
	regen_world <<< $'No\nNo\nNo\nNo\n'
	run cat "${WORLD}"
	assert_output --partial 'app-misc/bar'
	[[ "${output}" != *'app-misc/foo'* ]]
}

@test "regen_world: 'Result:' header printed after regeneration" {
	QLIST_INSTALLED='app-misc/foo'
	EMERGE_PRETEND=""
	run regen_world <<< $'No\nNo\nNo\nNo\n'
	[[ "${output}" == *'Result'* ]]
}

@test "regen_world: empty emerge -epO system → qlist guard prevents pollution" {
	# Regression test for HIGH#3.  Pre-fix: an empty EMERGE_SYSTEM made
	# `qlist -CI $(empty)` return ALL installed → every atom landed in
	# pretend → @world cleanup was a no-op.  Post-fix: the guard skips
	# the qlist call entirely when no system atoms are emitted, and the
	# eopd-only `pretend` is used as-is.
	QLIST_INSTALLED='app-misc/foo'
	EMERGE_PRETEND=""        # no deps blocking foo
	EMERGE_SYSTEM=""         # critical: empty system set
	regen_world <<< $'No\nNo\nNo\nNo\n'
	run cat "${WORLD}"
	# foo must be ADDED to new world (it's not a dep and not virtual/
	# and not -libs/).  Pre-fix bug would have left WORLD empty because
	# foo would have been spuriously added to pretend via the qlist
	# fallback.
	assert_output --partial 'app-misc/foo'
}

@test "regen_world: empty installed → empty new world" {
	QLIST_INSTALLED=""
	EMERGE_PRETEND=""
	EMERGE_SYSTEM=""
	regen_world <<< $'No\nNo\nNo\nNo\n'
	run cat "${WORLD}"
	[[ -z "$(tr -d $'\n\t ' <<< "${output}")" ]]
}

@test "regen_world: 'world++:' status emitted for each kept atom" {
	QLIST_INSTALLED=$'app-misc/foo\napp-misc/bar'
	EMERGE_PRETEND=""
	EMERGE_SYSTEM=""
	run regen_world <<< $'No\nNo\nNo\nNo\n'
	[[ "${output}" == *'world++:'* ]]
	[[ "${output}" == *'app-misc/foo'* ]]
	[[ "${output}" == *'app-misc/bar'* ]]
}
