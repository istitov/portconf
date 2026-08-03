# Smoke-test bats helper.
#
# Smoke tests execute the BUILT src/portconf binary end-to-end on a real
# Gentoo host (or stage3 container in CI) and assert on stdout/exit code.
# Unlike unit and integration tests — which source portconf.in with the
# dispatch suppressed and stub Portage tooling — the smoke tier validates
# that the binary actually starts, dispatches flags, and consumes the
# output of real eix / eselect / portage on a modern profile tree without
# crashing.
#
# Smoke covers two tiers:
#   help.bats + profile.bats — read-only flags against the host's real
#     Portage tree.
#   mutating_flags.bats — every other dispatch arm, run with PORT_ETC /
#     BRDIR / PKGDB / DEP_PATH overridden to throwaway tmpdirs (made
#     possible by the path-overridability refactor at line 39-43 of
#     portconf.in) and the default dry-run mode to gate every persistent
#     mutation, including backups.  The smoke_sandbox helper below sets up
#     and tears down the tmpdirs.

source "${BATS_TEST_DIRNAME}/../test_helper.bash"

# Path to the built binary.  Substituted at configure time by autotools;
# falls back to ../../src/portconf so the file can be run from a build
# directory without prior `make install`.
PORTCONF_BIN="${BATS_TEST_DIRNAME}/../../src/portconf"

# Strip ANSI escape sequences from $output.  Smoke assertions check for
# substrings in colourised help/profile output; the terminal sequences
# would otherwise break naive grep-style matches.
strip_ansi() {
	printf '%s' "$1" | sed -E $'s/\x1b\\[[0-9;]*[a-zA-Z]//g'
}

# Assert that the (ANSI-stripped) output contains the given substring.
assert_output_contains() {
	local needle=$1 haystack
	haystack="$(strip_ansi "${output}")"
	if [[ "${haystack}" != *"${needle}"* ]]; then
		printf 'expected output to contain: %s\n--- actual ---\n%s\n' \
			"${needle}" "${haystack}" >&2
		return 1
	fi
}

# Create a sandboxed path environment for mutating-flag smoke tests and
# populate a representative PORT_ETC fixture.  Sets these test-scoped
# globals (each a fresh mktemp dir):
#   SMOKE_PORT_ETC, SMOKE_BRDIR, SMOKE_PKGDB, SMOKE_DEP
# Tests then invoke the binary like:
#   run env PORT_ETC="${SMOKE_PORT_ETC}" BRDIR="${SMOKE_BRDIR}" \
#       PKGDB="${SMOKE_PKGDB}" DEP_PATH="${SMOKE_DEP}" \
#       "${PORTCONF_BIN}" -p <flag>
# PORTCONF_CONF=/dev/null prevents host defaults from changing the requested
# action mode.  Dry-run never asks eix_method's cache-rebuild question.
smoke_sandbox() {
	SMOKE_PORT_ETC="$(mktemp -d)"
	SMOKE_BRDIR="$(mktemp -d)"
	SMOKE_PKGDB="$(mktemp -d)"
	SMOKE_DEP="$(mktemp -d)"
	# Representative fixture: sys-apps/grep is a core package present on
	# every Gentoo system, "static" is a long-stable IUSE entry.
	printf 'sys-apps/grep static\n' > "${SMOKE_PORT_ETC}/package.use"
	printf 'sys-apps/grep\n' > "${SMOKE_PORT_ETC}/package.mask"
	printf 'sys-apps/grep\n' > "${SMOKE_PORT_ETC}/package.unmask"
	printf 'sys-apps/grep ~amd64\n' > "${SMOKE_PORT_ETC}/package.accept_keywords"
	# make.conf is required by use_makeconf() and invalid_uses_make() — both
	# call `cp "${makefile}" "${tmp_file}"` where ${makefile} is empty
	# when neither /etc/make.conf nor ${PORT_ETC}/make.conf exists.
	# (NOTE: the makefile global is captured at portconf source time, so
	# the file must exist before the binary forks.)
	printf 'USE="x11"\n' > "${SMOKE_PORT_ETC}/make.conf"
}

# Clean up the sandbox set up by smoke_sandbox.  Idempotent.
smoke_cleanup() {
	[[ -n "${SMOKE_PORT_ETC:-}" ]] && rm -rf "${SMOKE_PORT_ETC}"
	[[ -n "${SMOKE_BRDIR:-}"    ]] && rm -rf "${SMOKE_BRDIR}"
	[[ -n "${SMOKE_PKGDB:-}"    ]] && rm -rf "${SMOKE_PKGDB}"
	[[ -n "${SMOKE_DEP:-}"      ]] && rm -rf "${SMOKE_DEP}"
}

# Convenience wrapper around `run` that injects the sandbox env-var spec
# and feeds "No" through every interactive prompt.  Usage:
#   smoke_run -p -ui
smoke_run() {
	run env \
		PORT_ETC="${SMOKE_PORT_ETC}" \
		BRDIR="${SMOKE_BRDIR}" \
		PKGDB="${SMOKE_PKGDB}" \
		DEP_PATH="${SMOKE_DEP}" \
		PORTCONF_CONF=/dev/null \
		"${PORTCONF_BIN}" "$@" <<< $'No\nNo\nNo\nNo\nNo\nNo\n'
}
