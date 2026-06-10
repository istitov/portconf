#!/usr/bin/env bats
# End-to-end: pruning an invalid USE flag from make.conf (invalid_uses_make,
# via -ui) must not abort and must not bleed into a comment or a sibling
# variable.  The old grep-the-flag / sed-the-line removal did both: a flag
# matching more than one line fed a newline into the sed pattern (abort under
# set -e), and the whole-file substitution clipped the flag word out of other
# vars and comments.  Drives the BUILT binary over a synthetic make.conf with a
# deliberately-unknown flag (never in any IUSE).

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH (portconf needs it at startup)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
}

teardown() {
	prop_cleanup
}

@test "make.conf: -ui drops an invalid USE flag without touching comments or sibling vars" {
	cat > "${PROP_PORT_ETC}/make.conf" <<'EOF'
# remember not_a_real_use_flag_xyz here
USE="not_a_real_use_flag_xyz nls"
VIDEO_CARDS="not_a_real_use_flag_xyz nouveau"
EOF
	prop_apply -ui
	# 1. No abort (the multi-line-grep -> unterminated-sed bug exited non-zero).
	[ "${status}" -eq 0 ]
	# 2. Invalid flag removed from USE -- even though it is the FIRST token.
	run grep -E '^USE=' "${PROP_PORT_ETC}/make.conf"
	[[ "${output}" != *not_a_real_use_flag_xyz* ]]
	# 3. No collateral: the comment + the (unreferenced) sibling var still have
	#    it -- exactly two surviving mentions.
	run grep -c 'not_a_real_use_flag_xyz' "${PROP_PORT_ETC}/make.conf"
	assert_output '2'
}

@test "make.conf: -ui is idempotent (a second run changes nothing)" {
	printf '%s\n' 'USE="not_a_real_use_flag_xyz nls"' > "${PROP_PORT_ETC}/make.conf"
	prop_apply -ui
	[ "${status}" -eq 0 ]
	local after; after="$(cat "${PROP_PORT_ETC}/make.conf")"
	prop_apply -ui
	[ "${status}" -eq 0 ]
	run cat "${PROP_PORT_ETC}/make.conf"
	assert_output "${after}"
}
