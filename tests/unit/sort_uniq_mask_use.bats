#!/usr/bin/env bats
# Tests for sort_uniq_mask_use — the deduplicator for profile/use.mask and
# profile/use.stable.mask under PORT_ETC.
#
# Unlike the package.* processors, these files list one USE flag per line
# (no atom prefix).  sort_uniq_mask_use:
#   - skips comment lines (grep -v "^#")
#   - feeds all remaining lines to sort_passed_uses for last-wins dedup
#   - writes output one flag per line (via tr "[:space:]" $'\n')
#   - calls diff_ask to apply the result
#
# The function is a no-op when PORT_ETC/profile does not exist.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# helper: create the profile dir and write use.mask
write_use_mask() {
	mkdir -p "${TEST_PORT_ETC}/profile"
	printf '%s\n' "$@" > "${TEST_PORT_ETC}/profile/use.mask"
}

# --- no profile directory ---

@test "sort_uniq_mask_use: no profile dir — returns without error" {
	# PORT_ETC has no profile/ subdirectory
	run sort_uniq_mask_use
	assert_success
}

# --- unchanged content ---

@test "sort_uniq_mask_use: single flag — preserved" {
	write_use_mask "foo"
	sort_uniq_mask_use
	run cat "${TEST_PORT_ETC}/profile/use.mask"
	assert_output "foo"
}

@test "sort_uniq_mask_use: two distinct flags — both preserved, one per line" {
	write_use_mask "foo" "bar"
	sort_uniq_mask_use
	run grep "^foo$" "${TEST_PORT_ETC}/profile/use.mask"
	assert_output "foo"
	run grep "^bar$" "${TEST_PORT_ETC}/profile/use.mask"
	assert_output "bar"
}

# --- deduplication ---

@test "sort_uniq_mask_use: duplicate flag — collapsed to one" {
	write_use_mask "foo" "foo"
	sort_uniq_mask_use
	run grep -c "^foo$" "${TEST_PORT_ETC}/profile/use.mask"
	assert_output "1"
}

@test "sort_uniq_mask_use: conflicting flags — last occurrence wins (flag then -flag)" {
	write_use_mask "foo" "bar" "-foo"
	sort_uniq_mask_use
	# foo was negated last → -foo survives, plain foo gone
	run grep "^-foo$" "${TEST_PORT_ETC}/profile/use.mask"
	assert_output "-foo"
	run bash -c "grep -c '^foo$' '${TEST_PORT_ETC}/profile/use.mask' || true"
	assert_output "0"
}

@test "sort_uniq_mask_use: conflicting flags — last occurrence wins (-flag then flag)" {
	write_use_mask "-foo" "bar" "foo"
	sort_uniq_mask_use
	# foo was asserted last → foo survives, -foo gone
	run grep "^foo$" "${TEST_PORT_ETC}/profile/use.mask"
	assert_output "foo"
	run bash -c "grep -c '^-foo$' '${TEST_PORT_ETC}/profile/use.mask' || true"
	assert_output "0"
}

# --- comment handling ---

@test "sort_uniq_mask_use: comment lines stripped" {
	write_use_mask "foo" "# keep foo masked" "bar"
	sort_uniq_mask_use
	run bash -c "grep -c '^#' '${TEST_PORT_ETC}/profile/use.mask' || true"
	assert_output "0"
	run grep "^foo$" "${TEST_PORT_ETC}/profile/use.mask"
	assert_output "foo"
}

# --- use.stable.mask ---

@test "sort_uniq_mask_use: processes use.stable.mask too" {
	mkdir -p "${TEST_PORT_ETC}/profile"
	printf '%s\n' "foo" "foo" > "${TEST_PORT_ETC}/profile/use.stable.mask"
	sort_uniq_mask_use
	run grep -c "^foo$" "${TEST_PORT_ETC}/profile/use.stable.mask"
	assert_output "1"
}
