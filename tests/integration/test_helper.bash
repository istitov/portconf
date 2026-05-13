# Shared bats setup for portconf integration tests.
#
# Same load_portconf / make_test_portage infrastructure as the unit helper,
# plus a tput no-op stub (check_uses uses tput for cursor positioning, which
# corrupts bats' FD management in a non-TTY environment).
#
# Each integration test file stubs its own external tools (eix, emerge,
# qatom, agrep) in setup() or per-test, since the required output varies.

: "${BATS_HELPER_DIR:=}"
_portconf_find_bats_helper() {
	local lib=$1 d
	for d in "${BATS_HELPER_DIR}" /usr/share /usr/lib /usr/lib64 /usr/local/share; do
		[[ "$d" && -f "$d/${lib}/load.bash" ]] && { echo "$d/${lib}/load"; return; }
	done
	echo "ERROR: could not find ${lib}/load.bash; set BATS_HELPER_DIR" >&2
	return 1
}
load "$(_portconf_find_bats_helper bats-support)"
load "$(_portconf_find_bats_helper bats-assert)"

load_portconf() {
	set --
	export PORTCONF_NO_MAIN=1
	local was_errexit=
	[[ $- == *e* ]] && was_errexit=1
	local saved_exit_trap
	saved_exit_trap="$(trap -p EXIT)"
	set +e
	# shellcheck source=../../src/portconf.in
	source "${BATS_TEST_DIRNAME}/../../src/portconf.in"
	eval "${saved_exit_trap:-trap - EXIT}"
	[[ $was_errexit ]] && set -e
	unset PORTCONF_NO_MAIN
	return 0
}

make_test_portage() {
	TEST_PORT_ETC="$(mktemp -d)"
	PORT_ETC="${TEST_PORT_ETC}"
	yes="1"
	PRETEND=""
	eend()   { return "${1:-0}"; }
	ebegin() { :; }
	tput()   { :; }
}

teardown_test_portage() {
	[[ -n "${TEST_PORT_ETC:-}" ]] && rm -rf "${TEST_PORT_ETC}"
}
