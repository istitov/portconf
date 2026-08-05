#!/usr/bin/env bats
# The invariant the ten-mode release claim rests on.
#
# The four invariants that claim already asserted — clean exit, no invented
# entries, no new duplicates, second-run idempotence — are every one of them
# satisfied by deleting an entire class of files.  That is precisely what the
# pre-2.0.6 environment cleanup did: it removed every file under env/ and
# emptied every package.env fragment, and the sweep reported all four checks
# green because wiping a file class exits cleanly, invents nothing, leaves no
# duplicate, and is perfectly idempotent on the second run.
#
# This adds the missing fifth: over a fixture in which nothing is legitimately
# removable, a mutating mode may rewrite a file's contents but must not make a
# file disappear.

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH (portconf needs it at startup)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
	_seed_full_fixture
}

teardown() {
	prop_cleanup
}

# Every file class a mutating mode touches, all of it valid and none of it
# removable by contract: the atom is installed, both environment configs are
# referenced, and no file is comment-only (which would legitimately vanish
# under -c/-ac followed by the empty-file sweep).
#
# sys-apps/grep is the project's standard fixture atom — a @system package on
# every Gentoo install, so PKGDB and eix agree it exists.  "static" is a real
# flag on it, so -ui/-uf have nothing valid to prune.
_seed_full_fixture() {
	mkdir -p "${PROP_PORT_ETC}/package.use" \
		"${PROP_PORT_ETC}/package.accept_keywords" \
		"${PROP_PORT_ETC}/package.env" \
		"${PROP_PORT_ETC}/env/sys-apps" \
		"${PROP_PKGDB}/sys-apps/grep-1.0"
	printf '# header comment\nsys-apps/grep static # inline\n' \
		> "${PROP_PORT_ETC}/package.use/main"
	printf '# header comment\nsys-apps/grep ~testarch # inline\n' \
		> "${PROP_PORT_ETC}/package.accept_keywords/main"
	printf 'sys-apps/grep sys-apps/grep.conf shared.conf\n' \
		> "${PROP_PORT_ETC}/package.env/main"
	printf 'synthetic env\n' > "${PROP_PORT_ETC}/env/sys-apps/grep.conf"
	printf 'shared env\n' > "${PROP_PORT_ETC}/env/shared.conf"
}

_file_inventory() {
	( cd "$1" && find . -type f | sort )
}

@test "property: every mutating mode preserves the file inventory" {
	local mode before after
	before="$(_file_inventory "${PROP_PORT_ETC}")"

	# The ten modes named in the release notes.
	for mode in -us -s -ku -ko -c -ac -ui -uf -t -f;do
		prop_apply "${mode}"
		if [[ "${status}" -ne 0 ]];then
			printf '%s exited %s:\n%s\n' "${mode}" "${status}" "${output}" >&2
			return 1
		fi
		after="$(_file_inventory "${PROP_PORT_ETC}")"
		if [[ "${after}" != "${before}" ]];then
			printf '%s changed the file inventory:\n' "${mode}" >&2
			diff <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") >&2 || true
			return 1
		fi
	done
}

@test "property: trash and full keep every referenced environment config" {
	# The specific class the pre-2.0.6 cleanup destroyed, asserted by count so
	# the check cannot be satisfied by substituting one file for another.
	local mode envs frags
	for mode in -t -f;do
		prop_apply "${mode}"
		[ "${status}" -eq 0 ]
		envs="$(find "${PROP_PORT_ETC}/env" -type f | wc -l)"
		frags="$(find "${PROP_PORT_ETC}/package.env" -type f | wc -l)"
		[ "${envs}" -eq 2 ]
		[ "${frags}" -eq 1 ]
		[ -s "${PROP_PORT_ETC}/package.env/main" ]
	done
}
