EXTRA_DIST = portconf.ebuild.in portconf-9999.ebuild metadata.xml

# Drop a freshly-versioned ebuild + the live (-9999) ebuild + metadata.xml
# into a local overlay and run `ebuild ... manifest` for the release ebuild
# (which fetches the dist tarball and writes Manifest).  The 9999 ebuild
# is copied verbatim — no manifest needed for git-r3 live ebuilds.
# Set OVERLAY_DIR to your overlay's app-portage/portconf directory, e.g.
#   make ebuild OVERLAY_DIR=/var/db/repos/<your-overlay>/app-portage/portconf
ebuild:
	@test -n "$(OVERLAY_DIR)" || { \
	  echo 'error: set OVERLAY_DIR=/path/to/<overlay>/app-portage/portconf' >&2; \
	  exit 1; \
	}
	mkdir -p $(OVERLAY_DIR)
	cp $(srcdir)/portconf.ebuild.in $(OVERLAY_DIR)/portconf-$(VERSION).ebuild
	cp $(srcdir)/portconf-9999.ebuild $(OVERLAY_DIR)/portconf-9999.ebuild
	cp $(srcdir)/metadata.xml $(OVERLAY_DIR)/metadata.xml
	ebuild $(OVERLAY_DIR)/portconf-$(VERSION).ebuild manifest

.PHONY: ebuild
