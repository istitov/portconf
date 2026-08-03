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

@test "overlays: later repository failure rolls back config, trees, and broken links" {
	local repo_a="${BATS_TEST_TMPDIR}/repo-a"
	local repo_b="${BATS_TEST_TMPDIR}/repo-b"
	local active="${BATS_TEST_TMPDIR}/active-repo"
	mkdir -p "${repo_a}" "${repo_b}" "${active}"
	_declare_overlay "repo-a" "${repo_a}"
	_declare_overlay "repo-b" "${repo_b}"
	_declare_overlay "active" "${active}"
	_install_pkg "app-misc/from-active-1.0" "active"
	ln -s "missing-target" "${active}/broken-link"
	local calls=0
	eselect() {
		calls=$(( calls + 1 ))
		if (( calls == 1 ));then
			rm -f "${PORT_ETC}/repos.conf/$4.conf"
			return 0
		fi
		return 1
	}
	run overlays
	[ "$status" -ne 0 ]
	[ -d "${repo_a}" ]
	[ -d "${repo_b}" ]
	[ -f "${PORT_ETC}/repos.conf/repo-a.conf" ]
	[ -f "${PORT_ETC}/repos.conf/repo-b.conf" ]
	[ -L "${active}/broken-link" ]
	[[ "${output}" == *'rolled back'* ]]
}

# --- dep-cache cleanup: stale entries are actually removed (regression) ---

@test "overlays: stale dep-cache entries are removed and the loop terminates" {
	# fix_deps() flags every DEP_PATH entry whose corresponding repo path is
	# gone, and the final `while [[ -z "${stop}" ]]` loop rm's the batch.
	# Plant two stale entries: a path stripped of the DEP_PATH prefix lands at
	# filesystem root, which never exists -> both are trash.  Two of them makes
	# the multi-path word-split explicit (the historical bug quoted the whole
	# space-separated list into ONE literal arg, so rm -f no-oped, fix_deps
	# re-found the identical trash, and the loop spun forever -- with NO host
	# coverage because the suite sandboxes DEP_PATH to an empty dir).
	local dep_a="${DEP_PATH}/gone-repo-a-$$"
	local dep_b="${DEP_PATH}/gone-repo-b-$$"
	mkdir -p "${dep_a}" "${dep_b}"
	[ -d "${dep_a}" ] && [ -d "${dep_b}" ]

	# Drive the REAL overlays() in a fresh, time-boxed shell.  `timeout`
	# yields a clean exit code (124 on a hang) -- unlike backgrounding the
	# already-sourced function, where `kill -0` on the unreaped zombie can't
	# tell "finished" from "still spinning".  Re-source picks up DEP_PATH et al.
	# from the passed-through env; overlays needs no stdin here (empty PKGDB /
	# repos.conf -> no prompt is read before the dep-cache loop).
	run timeout 20 env \
		PORT_ETC="${PORT_ETC}" PKGDB="${PKGDB}" DEP_PATH="${DEP_PATH}" \
		bash -c 'PORTCONF_NO_MAIN=1 source "$1"; overlays </dev/null' \
		_ "${BATS_TEST_DIRNAME}/../../src/portconf.in"

	# 124 == timeout killed it == the loop never terminated == bug present.
	[ "$status" -ne 124 ]
	# And the stale entries must actually be gone (the no-op rm left them).
	[ ! -d "${dep_a}" ]
	[ ! -d "${dep_b}" ]
}
