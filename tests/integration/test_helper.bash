# Integration-test bats helper.
#
# Loads shared infrastructure from tests/test_helper.bash, then defines
# make_test_portage with an extra tput no-op stub.
#
# check_uses (called by invalid_uses) uses tput for cursor positioning;
# in a non-TTY bats environment this corrupts FD management.
#
# Each integration test file stubs its own external tools (eix, emerge,
# qatom, agrep) in setup() or per-test, since required output varies.

source "${BATS_TEST_DIRNAME}/../test_helper.bash"

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
