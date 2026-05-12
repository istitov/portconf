bin_SCRIPTS = portconf

EXTRA_DIST = portconf.in
CLEANFILES = portconf

portconf: portconf.in Makefile
	$(SED) 's|@PACKAGE_VERSION[@]|$(PACKAGE_VERSION)|g' $(srcdir)/portconf.in > $@
	chmod +x $@
