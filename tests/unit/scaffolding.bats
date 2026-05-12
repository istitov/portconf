#!/usr/bin/env bats
# Sanity check: source portconf.in, confirm a basic helper is callable
# and produces expected output.

load 'test_helper'

setup() {
	load_portconf
}

@test "scaffolding: sort_passed_uses is defined after load_portconf" {
	declare -F sort_passed_uses >/dev/null
}

@test "scaffolding: sort_passed_uses passes a single flag unchanged" {
	result="$(sort_passed_uses "foo")"
	assert_equal "$result" "foo"
}

@test "scaffolding: PORT_ETC is set" {
	[[ -n "${PORT_ETC}" ]]
}

@test "scaffolding: PACKAGE_VERSION is set (substituted at build time or shows placeholder)" {
	[[ -n "${PACKAGE_VERSION}" ]]
}
