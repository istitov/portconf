#!/usr/bin/env bats
# Tests for sort_uniq_files — the general-purpose package.* deduplicator.
#
# sort_uniq_files finds every package.* file (excluding ~/*.bak backups)
# under PORT_ETC and, for each:
#   - groups each atom with its header block (the consecutive comment +
#     blank lines immediately above it)
#   - collects all flag/keyword tokens for each atom across duplicate
#     lines (no conflict resolution — unlike sort_uses, both sides of
#     a +flag/-flag pair are kept) and dedupes the merged list
#   - sorts atoms alphabetically; header blocks travel with their atom
#   - preserves trailing comments (after the last atom in the file)
#     verbatim at the end of the output
#   - calls diff_ask to apply or discard the result
#
# Note: this is distinct from sort_use_file/sort_uses which does resolve
# +flag/-flag conflicts via sort_passed_uses.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# --- unchanged content ---

@test "sort_uniq_files: single atom single flag — unchanged" {
	printf '%s\n' "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uniq_files: two distinct atoms — both preserved" {
	printf '%s\n' "app-misc/foo bar" "dev-libs/baz qux" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "2"
	run grep "app-misc/foo bar" "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
	run grep "dev-libs/baz qux" "${TEST_PORT_ETC}/package.use"
	assert_output "dev-libs/baz qux"
}

@test "sort_uniq_files: flag-less atom (package.mask style) — preserved" {
	printf '%s\n' "app-misc/foo" > "${TEST_PORT_ETC}/package.mask"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.mask"
	assert_output "app-misc/foo"
}

@test "sort_uniq_files: processes package.accept_keywords" {
	printf '%s\n' "app-misc/foo ~amd64" > "${TEST_PORT_ETC}/package.accept_keywords"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.accept_keywords"
	assert_output "app-misc/foo ~amd64"
}

# --- deduplication ---

@test "sort_uniq_files: duplicate identical lines — collapsed to one" {
	printf '%s\n' "app-misc/foo bar" "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "1"
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uniq_files: same atom different flags — merged onto one line" {
	printf '%s\n' "app-misc/foo bar" "app-misc/foo baz" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar baz"
}

@test "sort_uniq_files: conflicting flags — both retained (no conflict resolution)" {
	printf '%s\n' "app-misc/foo bar" "app-misc/foo -bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar -bar"
}

# --- comment handling ---

@test "sort_uniq_files: comment block above an atom — preserved with the atom" {
	# Header block is the comment line(s) immediately above an atom.
	# It travels with the atom through sorting.
	printf '%s\n' "# leading comment" "app-misc/foo bar" > "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# leading comment\napp-misc/foo bar')"
}

@test "sort_uniq_files: multi-line header block — all lines preserved" {
	printf '%s\n' "# line 1" "# line 2" "# line 3" "app-misc/foo bar" \
		> "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# line 1\n# line 2\n# line 3\napp-misc/foo bar')"
}

@test "sort_uniq_files: header blocks travel with their atom when sorted" {
	# zzz/atom sorts after aaa/atom — its header must end up below.
	printf '%s\n' \
		"# header for zzz" "zzz-app/last flag" \
		"# header for aaa" "aaa-app/first flag" \
		> "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# header for aaa\naaa-app/first flag\n# header for zzz\nzzz-app/last flag')"
}

@test "sort_uniq_files: blank line inside header block — preserved" {
	# Blank separators inside a header block are part of the block.
	printf '%s\n' "# section header" "" "# atom comment" "app-misc/foo bar" \
		> "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# section header\n\n# atom comment\napp-misc/foo bar')"
}

@test "sort_uniq_files: trailing comments (no atom after) — kept at end" {
	printf '%s\n' "app-misc/foo bar" "# trailing comment" \
		> "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf 'app-misc/foo bar\n# trailing comment')"
}

@test "sort_uniq_files: atom with header + duplicate atom without — header from first occurrence" {
	# Duplicate atoms merge their opts; the header attaches to the FIRST
	# occurrence (most recent in file order is dropped).
	printf '%s\n' "# original header" "app-misc/foo bar" "app-misc/foo baz" \
		> "${TEST_PORT_ETC}/package.use"
	sort_uniq_files
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# original header\napp-misc/foo bar baz')"
}
