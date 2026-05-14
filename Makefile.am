SUBDIRS = src man completion packaging

sysconf_DATA = portconf.conf

EXTRA_DIST = \
	.editorconfig \
	COPYING \
	README.md \
	portconf.conf \
	tests/test_helper.bash \
	tests/unit/test_helper.bash \
	tests/unit/scaffolding.bats \
	tests/unit/sort_passed_uses.bats \
	tests/unit/sort_uses.bats \
	tests/unit/conversions.bats \
	tests/unit/diff_ask.bats \
	tests/unit/file_ops.bats \
	tests/unit/file_cleanup.bats \
	tests/unit/sort_uniq_files.bats \
	tests/unit/uniq_keywords.bats \
	tests/unit/sort_keywords.bats \
	tests/unit/sort_uniq_mask_use.bats \
	tests/unit/ver_helpers.bats \
	tests/unit/timestamp.bats \
	tests/unit/backup.bats \
	tests/unit/repo_fix.bats \
	tests/unit/use_makeconf.bats \
	tests/unit/check_use_masked.bats \
	tests/unit/world_backup.bats \
	tests/unit/portconf_conf.bats \
	tests/unit/error_paths.bats \
	tests/integration/test_helper.bash \
	tests/integration/invalid_uses_make.bats \
	tests/integration/not_found.bats \
	tests/integration/invalid_uses.bats \
	tests/integration/mask_trash.bats \
	tests/integration/stupid_unmask.bats \
	tests/integration/overlays.bats \
	tests/integration/backup_path.bats \
	tests/integration/restore.bats \
	tests/integration/regen_world.bats \
	tests/integration/package_env.bats \
	tests/smoke/test_helper.bash \
	tests/smoke/help.bats \
	tests/smoke/profile.bats \
	tests/smoke/mutating_flags.bats \
	tests/smoke/no_color.bats

# Override BATS to point at a non-system bats binary if needed.
BATS = bats

# 'make check' runs the unit suite only — no external tool deps beyond bats.
check-local:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/unit/

# 'make check-integration' runs the integration suite.
# Requires: bats, eix (app-portage/eix), qatom (app-portage/portage-utils),
#           agrep (dev-libs/tre).
check-integration:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	@for tool in eix qatom agrep; do \
	  command -v $$tool >/dev/null || { \
	    echo "error: $$tool not on PATH (see INSTALL for integration test deps)" >&2; \
	    exit 1; \
	  }; \
	done
	$(BATS) $(srcdir)/tests/integration/

# 'make check-smoke' runs the built src/portconf binary against the real
# Portage tree.  Requires the binary to be built (autoreconf -i && configure
# && make) and a Gentoo host with eselect/eix and a resolvable profile.
# Only exercises read-only flags — no /etc/portage or /var/lib/portconf
# touch.  See tests/smoke/test_helper.bash for scope rationale.
check-smoke:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	@test -x src/portconf || { \
	  echo "error: src/portconf not built; run ./configure && make first" >&2; \
	  exit 1; \
	}
	@for tool in eselect eix; do \
	  command -v $$tool >/dev/null || { \
	    echo "error: $$tool not on PATH (smoke needs a real Gentoo host)" >&2; \
	    exit 1; \
	  }; \
	done
	$(BATS) $(srcdir)/tests/smoke/

# 'make ebuild OVERLAY_DIR=...' delegates to packaging/Makefile.am, which
# drops a versioned ebuild + metadata.xml into the given overlay path
# and runs `ebuild ... manifest` to fetch the dist tarball and write
# Manifest.  See packaging/Makefile.am for the exact recipe.
ebuild:
	$(MAKE) -C packaging ebuild OVERLAY_DIR=$(OVERLAY_DIR)

.PHONY: check-integration check-smoke ebuild
