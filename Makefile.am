SUBDIRS = src man

sysconf_DATA = portconf.conf

EXTRA_DIST = \
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
	tests/integration/test_helper.bash \
	tests/integration/invalid_uses_make.bats \
	tests/integration/not_found.bats \
	tests/integration/invalid_uses.bats

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

.PHONY: check-integration
