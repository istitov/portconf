#!/usr/bin/env bats
# Safety properties for the two destructive invariants that previously lived
# only as fixed integration examples:
#   * an exact removal never changes a non-target sibling;
#   * a rejected restore archive never changes the live tree.

load test_helper

setup() {
	command -v eix >/dev/null || skip "eix not on PATH (portconf needs it at startup)"
	test -x "${PORTCONF_BIN}" || skip "src/portconf not built (run ./configure && make)"
	prop_sandbox
}

teardown() {
	prop_cleanup
}

@test "property: exact removal never changes a non-target sibling" {
	load_portconf
	local target mode fixture expected
	local -a targets=(
		'cat-test/foo'
		'cat-test/foo:0'
		'>=cat-test/foo-1.2:0'
		'cat.test/foo+bar[qux]'
	)

	for target in "${targets[@]}";do
		for mode in literal field1;do
			fixture="${PROP_PORT_ETC}/remove-${mode}"
			expected="${PROP_PORT_ETC}/expected-${mode}"
			printf '%s\n' \
				'# sibling inventory' \
				"${target}" \
				"  ${target}  " \
				"${target} keep-flag" \
				"${target}-suffix" \
				"prefix-${target}" \
				> "${fixture}"
			if [[ "${mode}" == literal ]];then
				printf '%s\n' \
					'# sibling inventory' \
					"${target} keep-flag" \
					"${target}-suffix" \
					"prefix-${target}" \
					> "${expected}"
			else
				printf '%s\n' \
					'# sibling inventory' \
					"${target}-suffix" \
					"prefix-${target}" \
					> "${expected}"
			fi

			_drop_line "${fixture}" "${target}" "${mode}"
			cmp "${expected}" "${fixture}"
		done
	done
}

@test "property: trash resolves stale package.env references in one pass" {
	mkdir -p "${PROP_PORT_ETC}/env/cat-test"
	printf 'synthetic env\n' > "${PROP_PORT_ETC}/env/cat-test/gone.conf"
	printf 'sys-apps/grep cat-test/gone.conf\n' > "${PROP_PORT_ETC}/package.env"

	prop_apply -t
	[ "${status}" -eq 0 ]
	[ ! -e "${PROP_PORT_ETC}/env/cat-test/gone.conf" ]
	if [[ -e "${PROP_PORT_ETC}/package.env" ]];then
		run grep -F 'cat-test/gone.conf' "${PROP_PORT_ETC}/package.env"
		assert_failure
	fi
	assert_idempotent -t
}

_tree_fingerprint() {
	local root="$1"
	(
		cd "${root}"
		# Include ownership and modification time as well as topology, mode,
		# symlink target, and content.  ACL/xattr inventories join the digest
		# when their standard tools are installed.
		find . -printf '%P|%y|%m|%U|%G|%T@|%l\n' | sort
		find . -type f -print0 | sort -z | xargs -0 -r sha256sum
		if command -v getfacl >/dev/null;then getfacl -R -p . 2>/dev/null || true;fi
		if command -v getfattr >/dev/null;then getfattr -R -d -m- . 2>/dev/null || true;fi
	) | sha256sum | awk '{ print $1 }'
}

@test "property: rejected restore archives leave the live tree unchanged" {
	local archive="${PROP_BRDIR}/portage_26.08.03-12:00.tar.bz2"
	local fixtures="${PROP_PKGDB}/restore-fixtures"
	local before after variant
	mkdir -p "${PROP_PORT_ETC}/nested" "${fixtures}"
	printf 'KEEP root\n' > "${PROP_PORT_ETC}/package.use"
	printf 'KEEP nested\n' > "${PROP_PORT_ETC}/nested/state"
	chmod 0640 "${PROP_PORT_ETC}/nested/state"
	ln -s package.use "${PROP_PORT_ETC}/current-link"

	for variant in corrupt wrong-root traversal multiple-roots;do
		rm -rf "${fixtures:?}/"*
		case "${variant}" in
			corrupt)
				printf 'not a tar archive\n' > "${archive}"
				;;
			wrong-root)
				mkdir -p "${fixtures}/portage-sibling"
				printf 'ESCAPE\n' > "${fixtures}/portage-sibling/payload"
				tar -jcf "${archive}" -C "${fixtures}" portage-sibling
				;;
			traversal)
				mkdir -p "${fixtures}/portage"
				printf 'ESCAPE\n' > "${fixtures}/portage/payload"
				tar -jcf "${archive}" --transform='s|^portage|../escape|' \
					-C "${fixtures}" portage
				;;
			multiple-roots)
				mkdir -p "${fixtures}/portage" "${fixtures}/sibling"
				printf 'NEW\n' > "${fixtures}/portage/new"
				printf 'ESCAPE\n' > "${fixtures}/sibling/payload"
				tar -jcf "${archive}" -C "${fixtures}" portage sibling
				;;
		esac

		before="$(_tree_fingerprint "${PROP_PORT_ETC}")"
		prop_apply -r
		[ "${status}" -eq 1 ]
		after="$(_tree_fingerprint "${PROP_PORT_ETC}")"
		assert_equal "${after}" "${before}"
		[ ! -e "${PROP_PORT_ETC%/*}/escape" ]
	done
}
