# Unit-test bats helper.
#
# Loads shared infrastructure (bats-support, bats-assert, load_portconf)
# from tests/test_helper.bash, then defines make_test_portage / teardown.
#
# Requires: dev-util/bats dev-util/bats-support dev-util/bats-assert
# and a Gentoo host with app-portage/eix installed (portconf's own deps).

source "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Set up a scratch portage directory and redirect PORT_ETC to it.
# Call from setup() in file-operation test files.
make_test_portage() {
	TEST_PORT_ETC="$(mktemp -d)"
	PORT_ETC="${TEST_PORT_ETC}"
	yes="1"
	PRETEND=""
	# Gentoo's eend calls _update_tty_level which does `0<&1` (stdin ← stdout),
	# corrupting bats' internal fd management and killing the test subprocess.
	# Replace with a no-op that just returns the given exit code.
	eend() { return "${1:-0}"; }
	ebegin() { :; }
}

teardown_test_portage() {
	[[ -n "${TEST_PORT_ETC:-}" ]] && rm -rf "${TEST_PORT_ETC}"
}
