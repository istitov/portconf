#!/usr/bin/env bats
# Tests for /etc/portconf.conf integration — the init-time conditional
# sourcing at line 52 of portconf.in, plus the IGNORE_CATEGORY / IGNORE_PN
# regex expansion (lines 56-61) and COUNT defaulting (line 53).
#
# Logic under test (init time, before any function is called):
#
#   1. If /etc/portconf.conf exists, source it.  Variables it may set:
#        IGNORE_CATEGORY="cat1 cat2"   (space-separated category names)
#        IGNORE_PN="pn1 pn2"           (space-separated package names)
#        COUNT=N                        (backup retention limit)
#
#   2. COUNT defaults to 10 if unset.
#
#   3. IGNORE_CATEGORY: each whitespace-separated word is rewritten to
#        "<word>/.*" — a regex matching any package in that category.
#      IGNORE_PN: each word is rewritten to ".*/<word>" — matching any
#        category prefix for that package name.
#
#   4. IGNORE = newline-joined IGNORE_CATEGORY + IGNORE_PN, with empty
#      lines stripped.  If both are empty, falls back to a sentinel
#      string ("'Hello, LOR! :3'") so downstream grep patterns never
#      match anything by accident.
#
# Verifies the transformation contract.  The conditional-source itself
# is hardcoded to /etc/portconf.conf and not parameterisable; we test
# the downstream regex pipeline by pre-setting the env vars and
# observing what load_portconf produces.
#
# The transformation is exposed as _compute_ignore() in portconf.in (factored
# out of the inline init block specifically for testability — see commit
# history for the original 4-line inline form).  Tests set IGNORE_CATEGORY
# and IGNORE_PN explicitly, then call _compute_ignore to re-run the pipeline.

load 'test_helper'

setup() {
	load_portconf
}

# --- COUNT defaulting (resolved at portconf.in source time) ---

@test "portconf.conf: COUNT defaults to 10 when not set" {
	# load_portconf already ran; verify the default has been applied.
	# /etc/portconf.conf is not present on the test host, so the
	# conditional source is a no-op and ${COUNT:-10} kicks in.
	[[ "${COUNT}" == "10" ]]
}

# --- PORTCONF_CONF env-var override of the source path ---

@test "portconf.conf: PORTCONF_CONF override loads from custom path" {
	# Make a scratch config that sets a non-default COUNT.
	local conf
	conf="$(mktemp)"
	printf 'COUNT=42\n' > "${conf}"
	export PORTCONF_CONF="${conf}"
	load_portconf
	[[ "${COUNT}" == "42" ]]
	rm -f "${conf}"
}

@test "portconf.conf: PORTCONF_CONF override loads IGNORE_CATEGORY" {
	local conf
	conf="$(mktemp)"
	printf 'IGNORE_CATEGORY="dev-lang"\n' > "${conf}"
	export PORTCONF_CONF="${conf}"
	load_portconf
	# After init, IGNORE_CATEGORY has been transformed by _compute_ignore.
	[[ "${IGNORE_CATEGORY}" == 'dev-lang/.*' ]]
	rm -f "${conf}"
}

@test "portconf.conf: missing PORTCONF_CONF — defaults apply, no crash" {
	export PORTCONF_CONF="/nonexistent/portconf.conf.does.not.exist"
	load_portconf
	[[ "${COUNT}" == "10" ]]
}

# --- IGNORE_CATEGORY regex expansion ---

@test "_compute_ignore: IGNORE_CATEGORY single word becomes 'word/.*'" {
	IGNORE_CATEGORY="dev-lang"; IGNORE_PN=""
	_compute_ignore
	[[ "${IGNORE_CATEGORY}" == 'dev-lang/.*' ]]
}

@test "_compute_ignore: IGNORE_CATEGORY multiple words each get '/.*' suffix" {
	IGNORE_CATEGORY="dev-lang sys-apps"; IGNORE_PN=""
	_compute_ignore
	# Both transformed entries must be present, newline-separated.
	[[ "${IGNORE_CATEGORY}" == *'dev-lang/.*'* ]]
	[[ "${IGNORE_CATEGORY}" == *'sys-apps/.*'* ]]
}

@test "_compute_ignore: IGNORE_CATEGORY empty stays empty" {
	IGNORE_CATEGORY=""; IGNORE_PN=""
	_compute_ignore
	[[ -z "${IGNORE_CATEGORY}" ]]
}

# --- IGNORE_PN regex expansion ---

@test "_compute_ignore: IGNORE_PN single word becomes '.*/word'" {
	IGNORE_CATEGORY=""; IGNORE_PN="gcc"
	_compute_ignore
	[[ "${IGNORE_PN}" == '.*/gcc' ]]
}

@test "_compute_ignore: IGNORE_PN multiple words each get '.*/' prefix" {
	IGNORE_CATEGORY=""; IGNORE_PN="gcc python"
	_compute_ignore
	[[ "${IGNORE_PN}" == *'.*/gcc'* ]]
	[[ "${IGNORE_PN}" == *'.*/python'* ]]
}

@test "_compute_ignore: IGNORE_PN empty stays empty" {
	IGNORE_CATEGORY=""; IGNORE_PN=""
	_compute_ignore
	[[ -z "${IGNORE_PN}" ]]
}

# --- combined IGNORE assembly ---

@test "_compute_ignore: IGNORE merges IGNORE_CATEGORY and IGNORE_PN" {
	IGNORE_CATEGORY="dev-lang"; IGNORE_PN="gcc"
	_compute_ignore
	[[ "${IGNORE}" == *'dev-lang/.*'* ]]
	[[ "${IGNORE}" == *'.*/gcc'* ]]
}

@test "_compute_ignore: IGNORE strips empty lines between sections" {
	# When only IGNORE_PN is set (IGNORE_CATEGORY empty), the joined IGNORE
	# must not start with a blank line — downstream grep -v "${IGNORE}"
	# treats blank patterns as "match everything", which would silently
	# drop ALL output.
	IGNORE_CATEGORY=""; IGNORE_PN="gcc"
	_compute_ignore
	[[ "${IGNORE}" != $'\n'* ]]
	[[ "${IGNORE}" != *$'\n\n'* ]]
}

@test "_compute_ignore: IGNORE falls back to sentinel when both inputs empty" {
	IGNORE_CATEGORY=""; IGNORE_PN=""
	_compute_ignore
	# The literal fallback is "'Hello, LOR! :3'" — a string that no real
	# category or package name can ever equal.
	[[ "${IGNORE}" == *"'Hello, LOR! :3'"* ]]
}

@test "_compute_ignore: tab-separated input treated same as space-separated" {
	# tr "[:space:]" $'\n' must handle tabs too — important because the
	# user's /etc/portconf.conf could be edited with tabs.
	IGNORE_CATEGORY=$'dev-lang\tsys-apps'; IGNORE_PN=""
	_compute_ignore
	[[ "${IGNORE_CATEGORY}" == *'dev-lang/.*'* ]]
	[[ "${IGNORE_CATEGORY}" == *'sys-apps/.*'* ]]
}
