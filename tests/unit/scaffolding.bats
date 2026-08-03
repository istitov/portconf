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

@test "scaffolding: version metadata is present and consistent" {
	local root="${BATS_TEST_DIRNAME}/../.."
	local configured_version man_version
	[[ -n "${PACKAGE_VERSION}" ]]
	configured_version="$(sed -n 's/^AC_INIT(\[portconf\],\[\([^]]*\)\].*/\1/p' "${root}/configure.ac")"
	man_version="$(awk 'NR == 1 { print $6 }' "${root}/man/portconf.1" | tr -d '"\\')"
	[[ -n "${configured_version}" ]]
	assert_equal "${man_version}" "${configured_version}"
}

@test "scaffolding: README test inventory matches the test tree" {
	local root="${BATS_TEST_DIRNAME}/../.."
	local unit integration smoke property total
	unit="$(awk '/^@test / { count++ } END { print count + 0 }' "${root}"/tests/unit/*.bats)"
	integration="$(awk '/^@test / { count++ } END { print count + 0 }' "${root}"/tests/integration/*.bats)"
	smoke="$(awk '/^@test / { count++ } END { print count + 0 }' "${root}"/tests/smoke/*.bats)"
	property="$(awk '/^@test / { count++ } END { print count + 0 }' "${root}"/tests/property/*.bats)"
	total=$(( unit + integration + smoke + property ))
	grep -Fq "${total}-test suite across four tiers" "${root}/README.md"
	grep -Fq "${unit} unit / ${integration}" "${root}/README.md"
	grep -Fq "integration / ${smoke} smoke / ${property} property" "${root}/README.md"
}
