SUBDIRS = src man

sysconf_DATA = portconf.conf

EXTRA_DIST = \
	portconf.conf \
	tests/unit/test_helper.bash \
	tests/unit/scaffolding.bats \
	tests/unit/sort_passed_uses.bats \
	tests/unit/file_ops.bats

# 'make check' runs the bats unit-test suite.  Override BATS to point at
# a non-system bats binary if needed.
BATS = bats

check-local:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/unit/
