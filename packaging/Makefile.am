EXTRA_DIST = portconf-9999.ebuild.in metadata.xml

# Drop the live (-9999) ebuild + metadata.xml into a local overlay.
# Release ebuilds are hand-crafted in the overlay at tag-cut time —
# the structural delta between live and release (KEYWORDS, SRC_URI,
# git-r3 inherit, eautoreconf) is too large for a single template.
# Set OVERLAY_DIR to your overlay's app-portage/portconf directory, e.g.
#   make ebuild OVERLAY_DIR=/var/db/repos/<your-overlay>/app-portage/portconf
ebuild:
	@test -n "$(OVERLAY_DIR)" || { \
	  echo 'error: set OVERLAY_DIR=/path/to/<overlay>/app-portage/portconf' >&2; \
	  exit 1; \
	}
	mkdir -p $(OVERLAY_DIR)
	cp $(srcdir)/portconf-9999.ebuild.in $(OVERLAY_DIR)/portconf-9999.ebuild
	cp $(srcdir)/metadata.xml $(OVERLAY_DIR)/metadata.xml

.PHONY: ebuild
