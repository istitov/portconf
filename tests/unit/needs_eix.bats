#!/usr/bin/env bats
# Tests for _needs_eix -- the DISPATCH gate that decides whether to bootstrap
# the eix PACKAGE cache (eix_check under -rc, else eix_method) before running
# the requested flags.  It must fire for exactly the flags whose handlers query
# that cache, and skip every other flag.
#
# Regressions guarded here (all from the old multiline-`grep "${eix_dep_keys}"`
# membership test this replaced):
#   * substring match -- bare `-f` matched inside `-fr` (fix-repos) and `-f2d`
#     (files-to-dirs), bootstrapping eix for flags that never read it;
#   * `-um` was listed though use_makeconf reads no eix at all;
#   * `-sm`/`-sum` were OMITTED though mask_trash / remove_trash both query the
#     cache -- so `-rc -sm` dropped the fresh cache and removed masks against
#     the stale host cache.
#
# Pure logic: _needs_eix is defined before the PORTCONF_NO_MAIN guard, so
# load_portconf alone makes it callable -- no eix / make_test_portage needed.

load 'test_helper'

setup() {
	load_portconf
}

# Negative assertions use the `if … then false; fi` form on purpose: `set -e`
# (active in bats bodies) ignores a failure whose status is inverted with `!`,
# so `! _needs_eix x` would pass even on a wrong match.  An explicit `false`
# inside the then-branch is not inverted and does abort the test.

@test "_needs_eix: true for every cache-querying short flag" {
	local f
	for f in -ui -uf -t -ft -sm -sum -f; do
		_needs_eix "${f}" || { echo "expected ${f} to need eix" >&2; false; }
	done
}

@test "_needs_eix: true for every cache-querying long flag" {
	local f
	for f in --use-invalid --use-full --trash --force-trash \
		 --stupid-mask --stupid-unmask --full; do
		_needs_eix "${f}" || { echo "expected ${f} to need eix" >&2; false; }
	done
}

@test "_needs_eix: false for non-cache flags (incl. -um, -fr/-f2d the old grep mis-fired on)" {
	local f
	for f in -um --use-make -s -us -sup -ku -ko -c -ac \
		 -f2d -d2f -fr -wb -wr -wg -apu -pu -cpu -b -r -V; do
		if _needs_eix "${f}"; then echo "expected ${f} to NOT need eix" >&2; false; fi
	done
}

@test "_needs_eix: true when a cache flag sits among non-cache tokens" {
	_needs_eix -s -ku -sm -c
}

@test "_needs_eix: false for an all-clear set, a lone -rc, and the empty string" {
	if _needs_eix -s -us -ku -fr;   then echo "all-clear set wrongly matched" >&2; false; fi
	if _needs_eix "-rc";            then echo "-rc alone wrongly matched"      >&2; false; fi
	if _needs_eix;                  then echo "empty wrongly matched"          >&2; false; fi
}

@test "_validate_dispatch_opts: accepts every dispatch option" {
	local -a options=(
		-rc --regen-cache -b --backup -r --restore -s --sort
		-us --use-sort -ui --use-invalid -um --use-make
		-sup --stupid-use-profile -uf --use-full -ko --keyword-one
		-ku --keyword-uniq -t --trash -sm --stupid-mask
		-sum --stupid-unmask -ft --force-trash -c --rm-comments
		-ac --rm-all-comments -f --full -f2d --files-2-dirs
		-d2f --dirs-2-files -apu --all-profiles-use -pu --profiles-use
		-cpu --current-profile-use -wb --world-backup -wr --world-restore
		-wg --world-regen -fr --fix-repos -V --version -h --help '-?' h
	)
	_validate_dispatch_opts "${options[@]}"
}

@test "_validate_dispatch_opts: rejects an unknown option with usage status" {
	run _validate_dispatch_opts --sort --not-a-portconf-option --backup
	[ "${status}" -eq 2 ]
	[[ "${output}" == *'Unknown option: --not-a-portconf-option'* ]]
}
