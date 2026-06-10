#!/usr/bin/env bats
# Integration tests for overlays() — the -fr (--fix-repos) handler.
#
# overlays() does four things in order:
#   1. Parse ${PORT_ETC}/repos.conf (file) and ${PORT_ETC}/repos.conf/*.conf
#      (glob) into a "<location> <name>" table.
#   2. For every installed package (${PKGDB}/<cat>/<pkg>/repository), read
#      the parent repo name.
#   3. For each parent repo, look up its location.  If missing →
#      TRASH_REPO; otherwise walk the tree for broken symlinks.
#   4. Build UNUSED = repos.conf entries (except DEFAULT and gentoo) that
#      aren't anyone's parent.
#
# After detection it prompts interactively to remove things (bad symlinks,
# unused overlays).  Tests pipe enough "No" responses to dismiss every
# prompt so the function completes without mutation.
#
# Sandboxing via the PORT_ETC and PKGDB env-var overrides made available
# by the source-side overridability round (see commit history).

load 'test_helper'

setup() {
	# overlays uses tput sc/civis/el/el1/rc/cnorm for an in-place progress
	# indicator.  In a non-TTY bats environment this corrupts FDs and
	# causes spurious test failures; stub it BEFORE load_portconf since
	# the function definition captures the stub closure.
	load_portconf
	make_test_portage
	tput() { :; }

	# Sandbox PKGDB to an empty tree by default; individual tests populate
	# it before calling overlays.
	TEST_PKGDB="$(mktemp -d)"
	PKGDB="${TEST_PKGDB}"

	# Sandbox the dep-cache.  overlays() unconditionally runs fix_deps()
	# at the end, which rm -rf's any entry under DEP_PATH whose parent
	# repo isn't listed in the (test's) repos.conf.  Without this isolation
	# the test would attempt to delete real host cache files.
	TEST_DEP_PATH="$(mktemp -d)"
	DEP_PATH="${TEST_DEP_PATH}"

	# Sandbox repos.conf inside the test PORT_ETC.
	mkdir -p "${PORT_ETC}/repos.conf"
}

teardown() {
	teardown_test_portage
	[[ -n "${TEST_PKGDB:-}" ]] && rm -rf "${TEST_PKGDB}"
	[[ -n "${TEST_DEP_PATH:-}" ]] && rm -rf "${TEST_DEP_PATH}"
}

# Helper: install a stubbed package belonging to a given parent repo.
_install_pkg() {
	local atom=$1 repo=$2
	mkdir -p "${PKGDB}/${atom}"
	printf '%s\n' "${repo}" > "${PKGDB}/${atom}/repository"
}

# Helper: declare an overlay in ${PORT_ETC}/repos.conf/<name>.conf.
_declare_overlay() {
	local name=$1 location=$2
	cat > "${PORT_ETC}/repos.conf/${name}.conf" <<EOF
[${name}]
location = ${location}
EOF
}

# --- UNUSED detection ---

@test "overlays: declared overlay with no installed packages → UNUSED" {
	local fake_loc="${BATS_TEST_TMPDIR}/empty_overlay"
	mkdir -p "${fake_loc}"
	_declare_overlay "myoverlay" "${fake_loc}"
	_install_pkg "sys-apps/grep-1.0" "gentoo"
	# Pipe "No" to every prompt: dismiss bad-link prompt + unused-overlay
	# prompt + their "More?" follow-ups.  Six "No"s is overkill but safe.
	run overlays <<< $'No\nNo\nNo\nNo\nNo\nNo\n'
	[[ "${output}" == *'myoverlay'* ]]
}

@test "overlays: overlay actively used by an installed package → NOT in UNUSED" {
	local fake_loc="${BATS_TEST_TMPDIR}/active_overlay"
	mkdir -p "${fake_loc}"
	_declare_overlay "active" "${fake_loc}"
	_install_pkg "app-misc/from-active-1.0" "active"
	run overlays <<< $'No\nNo\nNo\nNo\n'
	# Output of "Unused repos:" section must NOT include "active" — it's
	# referenced by an installed package.
	[[ "${output}" != *$'Unused repos:\nactive'* ]]
}

@test "overlays: gentoo repo never reported as UNUSED" {
	local fake_gentoo="${BATS_TEST_TMPDIR}/gentoo_repo"
	mkdir -p "${fake_gentoo}"
	_declare_overlay "gentoo" "${fake_gentoo}"
	_install_pkg "sys-apps/portage-1.0" "gentoo"
	run overlays <<< $'No\nNo\nNo\nNo\n'
	# The "gentoo" name is filtered explicitly at line 1718; it must
	# never appear under "Unused repos:" even when it has no installed
	# packages parented to it (test installs to gentoo, but the guard
	# applies regardless).
	[[ "${output}" != *$'Unused repos:'*'gentoo'* ]] || \
		[[ "${output}" != *$'Unused repos:\ngentoo\n'* ]]
}

# --- empty state ---

@test "overlays: empty repos.conf + empty PKGDB → no 'Unused repos:' output" {
	# Nothing declared, nothing installed → no UNUSED entries to print.
	run overlays <<< $'No\nNo\n'
	[[ "${output}" != *'Unused repos:'* ]]
}

@test "overlays: prints 'Checking installed packages...' progress header" {
	# Sanity check: the function reached phase 2 (PKGDB scan).  If
	# something broke phase 1 (repos.conf parsing) before this point,
	# the header would be missing.
	run overlays <<< $'No\nNo\n'
	[[ "${output}" == *'Checking installed packages'* ]]
}

# --- DEFAULT section in repos.conf is filtered out ---

@test "overlays: DEFAULT section in repos.conf is not flagged as unused" {
	# repos.conf may have a [DEFAULT] section setting global options
	# (main-repo, auto-sync).  It's not a real repo; the awk in
	# overlays() must filter it out (line 1676).
	cat > "${PORT_ETC}/repos.conf/00-default.conf" <<EOF
[DEFAULT]
main-repo = gentoo
location = /var/db/repos
EOF
	run overlays <<< $'No\nNo\n'
	[[ "${output}" != *'Unused repos:'*'DEFAULT'* ]]
}

# --- removal call: eselect must be forced (-f) ---

@test "overlays: an unused overlay is removed with 'eselect repository remove -f'" {
	# eselect refuses `local`/`no-sync-uri` overlays without -f, so the
	# removal call must pass it.  Stub eselect to record its args instead of
	# touching the real host repos.
	local fake_loc="${BATS_TEST_TMPDIR}/local_overlay"
	mkdir -p "${fake_loc}"
	_declare_overlay "localov" "${fake_loc}"
	_install_pkg "sys-apps/grep-1.0" "gentoo"
	local calls="${BATS_TEST_TMPDIR}/eselect.calls"
	eselect() { printf '%s\n' "$*" >> "${calls}"; return 0; }
	# "No" to the save-prompt so localov stays UNUSED and reaches removal.
	run overlays <<< $'No\nNo\nNo\nNo\nNo\nNo\n'
	[ -f "${calls}" ]
	grep -qF 'repository remove -f localov' "${calls}"
}

@test "overlays: a failed removal suggests the -f command in its hint" {
	local fake_loc="${BATS_TEST_TMPDIR}/local_overlay2"
	mkdir -p "${fake_loc}"
	_declare_overlay "stubborn" "${fake_loc}"
	_install_pkg "sys-apps/grep-1.0" "gentoo"
	# Simulate eselect declining the removal (e.g. run as non-root).
	eselect() { return 1; }
	run overlays <<< $'No\nNo\nNo\nNo\nNo\nNo\n'
	[[ "${output}" == *'eselect repository remove -f stubborn'* ]]
}
