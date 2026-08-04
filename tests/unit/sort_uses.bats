#!/usr/bin/env bats
# Tests for sort_uses (invoked via sort_use_file) — the USE-flag sorting and
# deduplication pass that normalises package.use entries.
#
# sort_use_file finds package.use (file or directory), sets the external
# `file` variable, then calls sort_uses which:
#   - collects all flags for each atom across duplicate lines
#   - resolves conflicts per atom by last-occurrence-wins per USE base
#   - groups each atom with the consecutive comment + blank lines above
#     it ("header block") so the block travels with the atom on sort
#   - preserves inline trailing comments on the atom line
#   - preserves trailing comments at end of file verbatim
#   - preserves atom entries that have no flags, including their header
#   - sorts output lines alphabetically by atom
#
# Tests use yes=1 (auto-apply) so diff_ask commits every change.

load 'test_helper'

setup() {
	load_portconf
	make_test_portage
}

teardown() {
	teardown_test_portage
}

# helper
write_use() { printf '%s\n' "$@" > "${TEST_PORT_ETC}/package.use"; }

# --- unchanged content ---

@test "sort_uses: single atom single flag — file unchanged" {
	write_use "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uses: single atom multiple flags — flags preserved" {
	write_use "app-misc/foo bar baz"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar baz"
}

@test "sort_uses: two distinct atoms — both lines preserved" {
	write_use "app-misc/foo bar" "dev-libs/baz qux"
	sort_use_file
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "2"
	run grep "app-misc/foo bar" "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
	run grep "dev-libs/baz qux" "${TEST_PORT_ETC}/package.use"
	assert_output "dev-libs/baz qux"
}

# --- deduplication ---

@test "sort_uses: duplicate identical lines — collapsed to one" {
	write_use "app-misc/foo bar" "app-misc/foo bar"
	sort_use_file
	run grep -c "." "${TEST_PORT_ETC}/package.use"
	assert_output "1"
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uses: conflicting flags — last occurrence wins (pos then neg)" {
	write_use "app-misc/foo bar" "app-misc/foo -bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo -bar"
}

@test "sort_uses: conflicting flags — last occurrence wins (neg then pos)" {
	write_use "app-misc/foo -bar" "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

@test "sort_uses: three duplicate lines — last state preserved" {
	write_use "app-misc/foo bar" "app-misc/foo -bar" "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar"
}

# --- comments ---

@test "sort_uses: comment block above atom — preserved with the atom" {
	# Header travels with the atom.
	write_use "# header comment" "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# header comment\napp-misc/foo bar')"
}

@test "sort_uses: multi-line header — all lines preserved with atom" {
	write_use "# line 1" "# line 2" "app-misc/foo bar"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# line 1\n# line 2\napp-misc/foo bar')"
}

@test "sort_uses: header blocks travel with their atom on sort" {
	write_use \
		"# header for zzz" "zzz-app/last flag" \
		"# header for aaa" "aaa-app/first flag"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# header for aaa\naaa-app/first flag\n# header for zzz\nzzz-app/last flag')"
}

@test "sort_uses: trailing comments (no atom after) — preserved at end" {
	write_use "app-misc/foo bar" "# trailing"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf 'app-misc/foo bar\n# trailing')"
}

@test "sort_uses: flagless atom and its header are preserved" {
	write_use "# this header annotates the flagless atom" "app-misc/foo"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# this header annotates the flagless atom\napp-misc/foo')"
}

@test "sort_uses: headers from every duplicate atom are preserved" {
	write_use \
		"# first reason" "app-misc/foo bar" \
		"# second reason" "app-misc/foo baz"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# first reason\n# second reason\napp-misc/foo bar baz')"
}

@test "sort_uses: inline comment preserved" {
	write_use "app-misc/foo bar # keep this"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo bar # keep this"
}

@test "sort_uses: inline annotations from every duplicate are preserved" {
	write_use \
		"app-misc/foo bar # first reason" \
		"app-misc/foo baz # second reason"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# first reason\n# second reason\napp-misc/foo bar baz')"
}

@test "sort_uses: header + atom + inline comment combine cleanly" {
	# All three pieces should survive: the leading header block, the
	# atom + flag, and the trailing inline comment.
	write_use "# why this atom needs bar" "app-misc/foo bar # do not disable"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "$(printf '# why this atom needs bar\napp-misc/foo bar # do not disable')"
}

@test "sort_uses: divider comment between two atoms — attaches to the later one" {
	# A bare comment between two atoms (no blank-line separator) is
	# the next atom's header.  After sort, it travels with that atom.
	write_use "aaa-app/first flag" "# divider" "zzz-app/last flag"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	# zzz-app/last sorts after aaa-app/first, so the divider stays
	# attached above zzz in the output.
	assert_output "$(printf 'aaa-app/first flag\n# divider\nzzz-app/last flag')"
}

@test "sort_uses: 'atom #notext' (no space before #) — round-trips as-is" {
	# Edge case: # adjacent to a USE-flag-like token with no separating
	# whitespace.  Inline-comment detection requires whitespace before
	# the #, so this token is parsed as a flag named '#notext' and
	# survives verbatim.  Not pretty but stable.
	write_use "app-misc/foo #notext"
	sort_use_file
	run cat "${TEST_PORT_ETC}/package.use"
	assert_output "app-misc/foo #notext"
}
