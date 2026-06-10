SUBDIRS = src man completion packaging

sysconf_DATA = portconf.conf

EXTRA_DIST = \
	.editorconfig \
	.shellcheckrc \
	CONTRIBUTING.md \
	COPYING \
	README.md \
	SECURITY.md \
	portconf.conf \
	tests/test_helper.bash \
	tests/unit/test_helper.bash \
	tests/unit/scaffolding.bats \
	tests/unit/sort_passed_uses.bats \
	tests/unit/sort_uses.bats \
	tests/unit/conversions.bats \
	tests/unit/diff_ask.bats \
	tests/unit/status_pc.bats \
	tests/unit/drop_line.bats \
	tests/unit/prune_var_flags.bats \
	tests/unit/mktemp_cleanup.bats \
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
	tests/unit/profile.bats \
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
	tests/smoke/no_color.bats \
	tests/property/test_helper.bash \
	tests/property/use_sort.bats \
	tests/property/keywords.bats \
	tests/property/comments.bats \
	tests/property/status_line.bats \
	tests/property/make_conf_use.bats \
	tests/property/invalid_uses.bats

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

# 'make check-properties' drives the built src/portconf binary over SYNTHETIC
# fixtures and asserts transform invariants — idempotence, no-duplicate-flag,
# inventory-preservation — rather than golden output.  These are the
# oracle-free checks that catch the corruption class behind the 2.0.4 fixes
# (non-idempotent / duplicate-flag-producing rewrites, silent atom loss).
# Requires the built binary and a Gentoo host with eix (portconf reads it at
# startup); the invalid_uses property additionally needs qatom and self-skips
# without it.  All fixtures are made-up atoms/flags — never the host's real
# config (use the local-only scripts/verify-local.sh for that).
check-properties:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	@test -x src/portconf || { \
	  echo "error: src/portconf not built; run ./configure && make first" >&2; \
	  exit 1; \
	}
	@command -v eix >/dev/null || { \
	  echo "error: eix not on PATH (portconf reads it at startup)" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/property/

# 'make installcheck' runs after 'make install' to verify the installed
# binary actually works.  Read-only — does not require root.  Honors
# DESTDIR so staging installs (DESTDIR=/tmp/staging make install) check
# the staged binary rather than the system one.
installcheck-local:
	@prog="$(DESTDIR)$(bindir)/portconf"; \
	test -x "$$prog" || { \
	  echo "error: $$prog is not installed or not executable" >&2; \
	  exit 1; \
	}; \
	out=$$("$$prog" --version 2>&1) || { \
	  echo "error: $$prog --version failed" >&2; \
	  exit 1; \
	}; \
	case "$$out" in \
	  *"$(PACKAGE_VERSION)"*) \
	    echo "ok: $$prog --version reports $(PACKAGE_VERSION)" ;; \
	  *) \
	    echo "error: $$prog --version says: $$out" >&2; \
	    echo "       expected to contain: $(PACKAGE_VERSION)" >&2; \
	    exit 1 ;; \
	esac; \
	"$$prog" --help >/dev/null 2>&1 || { \
	  echo "error: $$prog --help failed" >&2; \
	  exit 1; \
	}; \
	echo "ok: $$prog --help"

# 'make ebuild OVERLAY_DIR=...' delegates to packaging/Makefile.am, which
# drops the live (-9999) ebuild + metadata.xml into the given overlay
# path.  Release ebuilds are hand-crafted in the overlay at tag-cut
# time — see packaging/Makefile.am for the exact recipe.
ebuild:
	$(MAKE) -C packaging ebuild OVERLAY_DIR=$(OVERLAY_DIR)

# 'make toc' prints the topical section index from src/portconf.in.  Each
# section is a five-line banner whose name line starts with `# === `; the
# preceding line is the `# ==========...` fence used to disambiguate from
# inline `# === Source-time side effect:` notes inside a banner.  See the
# section banners themselves for what each section covers.
toc:
	@awk '/^# =====/ {f=1; next} \
	      f && /^# === [A-Za-z]/ {printf "  %4d  %s\n", NR, substr($$0, 7); f=0; next} \
	      {f=0}' $(srcdir)/src/portconf.in

.PHONY: check-integration check-smoke check-properties installcheck-local ebuild toc
