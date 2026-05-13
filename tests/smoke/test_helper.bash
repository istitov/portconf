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
# Smoke coverage is deliberately narrow: only flags that do not mutate
# /etc/portage and do not trigger backup() (which unconditionally writes
# to /var/lib/portconf regardless of --pretend).  See INSTALL for the
# rationale on smoke vs. integration scope.

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
