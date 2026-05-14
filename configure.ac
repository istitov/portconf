AC_INIT([portconf],[2.0.0_rc1],[https://github.com/istitov/portconf/issues],[portconf])
AM_INIT_AUTOMAKE([dist-xz no-dist-gzip foreign])
AC_PROG_SED

AC_ARG_ENABLE([bash-completion],
    AS_HELP_STRING([--disable-bash-completion],
                   [don't install bash completion]),
    [], [enable_bash_completion=yes])
AM_CONDITIONAL([BASH_COMPLETION], [test x$enable_bash_completion = xyes])

AC_ARG_ENABLE([zsh-completion],
    AS_HELP_STRING([--disable-zsh-completion],
                   [don't install zsh completion]),
    [], [enable_zsh_completion=yes])
AM_CONDITIONAL([ZSH_COMPLETION], [test x$enable_zsh_completion = xyes])

AC_CONFIG_FILES([
    Makefile
    src/Makefile
    man/Makefile
    completion/Makefile
])
AC_OUTPUT
