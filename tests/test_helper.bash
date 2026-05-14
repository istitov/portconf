# Shared bats infrastructure for unit and integration test suites.
#
# Provides:
#   _portconf_find_bats_helper  — locate bats-support / bats-assert
#   load_portconf               — source portconf.in with dispatch suppressed
#
# Sourced by tests/unit/test_helper.bash and tests/integration/test_helper.bash;
# each tier then defines its own make_test_portage / teardown_test_portage.

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
# portconf.in resets 'set -euo pipefail' at line 4, so that is in effect
# for the rest of the source; the functions are defined correctly.
# bats spawns a fresh bash process per @test, so script-level globals set
# during sourcing (ARCH, PROFILE, PORT_ETC, …) don't leak between tests.
load_portconf() {
	set --
	export PORTCONF_NO_MAIN=1
	local was_errexit= was_nounset=
	[[ $- == *e* ]] && was_errexit=1
	[[ $- == *u* ]] && was_nounset=1
	# Save bats' EXIT trap before sourcing portconf.in.
	# portconf.in runs `trap _cleanup EXIT` at source time, which silently
	# replaces bats' own teardown trap.  When set -e fires on a failing
	# assertion the shell exits via _cleanup instead of bats_teardown_trap,
	# so the test result is never reported.
	local saved_exit_trap
	saved_exit_trap="$(trap -p EXIT)"
	# Disable both set -e and set -u before sourcing.  Tests that call
	# load_portconf a SECOND time within the same @test (e.g. to test a
	# different PORTCONF_CONF input) would otherwise hit set -u while
	# re-sourcing /lib/gentoo/functions.sh, which references KSH_VERSION
	# without a default at line 45.  portconf.in itself sources functions.sh
	# BEFORE enabling set -u, so the first call works without this guard
	# — but the second call enters portconf.in with set -u already on.
	set +eu
	# shellcheck source=../src/portconf.in
	source "${BATS_TEST_DIRNAME}/../../src/portconf.in"
	eval "${saved_exit_trap:-trap - EXIT}"
	[[ $was_errexit ]] && set -e
	[[ $was_nounset ]] && set -u
	unset PORTCONF_NO_MAIN
	return 0
}
