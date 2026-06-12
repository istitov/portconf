#!/usr/bin/env bats
# Integration tests for not_if (the force_not_installed / -ft backbone): drops
# package.* atoms whose target package is NOT installed, keeps installed ones.
#
# not_if probes install state with qlist against the real Portage vdb, so the
# installed-set is controlled here by STUBBING qlist -- qatom stays REAL, since
# the "<unset>" placeholder it emits for a blank / categoryless line is exactly
# what the skip-guard under test must catch.  Atoms are synthetic cat-test/*.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() { teardown_test_portage; }

# Only cat-test/keep reads as installed -- installed() just checks that field 2
# of `qlist -ICSec` is non-empty, so one stub serves every call.
_stub_qlist() {
	qlist() {
		case "$*" in
			*cat-test/keep*) echo "slot cat-test/keep-1.0" ;;
			*) : ;;
		esac
	}
}

@test "not_if: removes a not-installed atom, keeps an installed one" {
	_stub_qlist
	package="${PORT_ETC}/package.use"
	printf '%s\n' "cat-test/keep flag" "cat-test/gone flag" > "${package}"
	tmp_package="$(_mktemp)"; cp "${package}" "${tmp_package}"
	run not_if
	[ "$status" -eq 0 ]
	grep -q 'cat-test/keep'   "${tmp_package}"   # installed   -> kept
	! grep -q 'cat-test/gone' "${tmp_package}"   # uninstalled -> removed
}

@test "not_if: a blank line is skipped, never probed/printed as <unset>" {
	_stub_qlist
	package="${PORT_ETC}/package.use"
	# Blank line between two real atoms -- a very common package.use shape.
	# Pre-fix this parsed to qatom's "<unset>/<unset>" and printed a bogus
	# "Not installed <unset>/..." line (cosmetic, but wrong).
	printf '%s\n' "cat-test/keep flag" "" "cat-test/gone flag" > "${package}"
	tmp_package="$(_mktemp)"; cp "${package}" "${tmp_package}"
	run not_if
	[ "$status" -eq 0 ]
	[[ "${output}" != *'<unset>'* ]]             # blank line did not surface
	grep -q 'cat-test/keep'   "${tmp_package}"   # real atoms still handled
	! grep -q 'cat-test/gone' "${tmp_package}"   # around the blank
}
