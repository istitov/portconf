# Shared bats setup for portconf unit tests.
#
# Usage from a .bats file:
#
#   load 'test_helper'
#   setup() { load_portconf; }
#
# Requires: dev-util/bats dev-util/bats-support dev-util/bats-assert
# and a Gentoo host with app-portage/eix installed (portconf's own deps).

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

# Source src/portconf.in with the command dispatch suppressed.
#
# portconf.in executes several Portage tools at source time (eix, profile
# tree reads via readlink + make.defaults sourcing) — these work fine on a
# real Gentoo host.  PORTCONF_NO_MAIN=1 skips the option-dispatch block at
# the bottom so sourcing only installs function definitions.
#
# Note: portconf.in resets 'set -euo pipefail' at line 4, so that is in
# effect for the rest of the source; the functions are defined correctly.
# bats spawns a fresh bash process per @test, so script-level globals set
# during sourcing (ARCH, PROFILE, PORT_ETC, …) don't leak between tests.
load_portconf() {
	set --
	export PORTCONF_NO_MAIN=1
	local was_errexit=
	[[ $- == *e* ]] && was_errexit=1
	# Save bats' EXIT trap before sourcing portconf.in.
	# portconf.in runs `trap _cleanup EXIT` at source time, which silently
	# replaces bats' own teardown trap.  When set -e later fires on a failing
	# assertion the shell exits via _cleanup instead of bats_teardown_trap,
	# so the test result is never reported and bats warns "Executed 0 tests".
	local saved_exit_trap
	saved_exit_trap="$(trap -p EXIT)"
	set +e
	# shellcheck source=../../src/portconf.in
	source "${BATS_TEST_DIRNAME}/../../src/portconf.in"
	# Restore whichever trap bats had registered before the source.
	eval "${saved_exit_trap:-trap - EXIT}"
	[[ $was_errexit ]] && set -e
	unset PORTCONF_NO_MAIN
	return 0
}

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
