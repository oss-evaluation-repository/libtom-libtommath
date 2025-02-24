#
# Include makefile for libtommath
#

#version of library
VERSION=1.3.0-develop
VERSION_PC=1.3.0
VERSION_SO=4:0:3

PLATFORM := $(shell uname | sed -e 's/_.*//')

# default make target
default: ${LIBNAME}

# Compiler and Linker Names
ifndef CROSS_COMPILE
  CROSS_COMPILE=
endif

# We only need to go through this dance of determining the right compiler if we're using
# cross compilation, otherwise $(CC) is fine as-is.
ifneq (,$(CROSS_COMPILE))
ifeq ($(origin CC),default)
CSTR := "\#ifdef __clang__\nCLANG\n\#endif\n"
ifeq ($(PLATFORM),FreeBSD)
  # XXX: FreeBSD needs extra escaping for some reason
  CSTR := $$$(CSTR)
endif
ifneq (,$(shell printf $(CSTR) | $(CC) -E - | grep CLANG))
  CC := $(CROSS_COMPILE)clang
else
  CC := $(CROSS_COMPILE)gcc
endif # Clang
endif # cc is Make's default
endif # CROSS_COMPILE non-empty

LD=$(CROSS_COMPILE)ld
AR=$(CROSS_COMPILE)ar

ifndef MAKE
# BSDs refer to GNU Make as gmake
ifneq (,$(findstring $(PLATFORM),FreeBSD OpenBSD DragonFly NetBSD))
  MAKE=gmake
else
  MAKE=make
endif
endif

LTM_CFLAGS += -I./ -Wall -Wsign-compare -Wextra -Wshadow

ifneq (,$(SANITIZER))
LTM_CFLAGS += -fsanitize=undefined -fno-sanitize-recover=all -fno-sanitize=float-divide-by-zero
endif

ifndef NO_ADDTL_WARNINGS
# additional warnings
LTM_CFLAGS += -Wdeclaration-after-statement -Wbad-function-cast -Wcast-align
LTM_CFLAGS += -Wstrict-prototypes -Wpointer-arith
endif

ifdef CONV_WARNINGS
LTM_CFLAGS += -std=c89 -Wconversion -Wsign-conversion
ifeq ($(CONV_WARNINGS), strict)
LTM_CFLAGS += -Wc++-compat
endif
else
LTM_CFLAGS += -Wsystem-headers
endif

ifdef COMPILE_DEBUG
#debug
LTM_CFLAGS += -g3
endif

ifdef COMPILE_SIZE
#for size
LTM_CFLAGS += -Os
else

ifndef IGNORE_SPEED
#for speed
LTM_CFLAGS += -O3 -funroll-loops

#x86 optimizations [should be valid for any GCC install though]
LTM_CFLAGS  += -fomit-frame-pointer
endif

ifdef COMPILE_LTO
ifeq ($(findstring clang,$(CC)),)
LTO_ARG = "=auto"
endif
LTM_CFLAGS += -flto$(LTO_ARG)
LTM_LDFLAGS += -flto$(LTO_ARG)
AR = $(subst clang,llvm-ar,$(subst gcc,gcc-ar,$(CC)))
endif

endif # COMPILE_SIZE

ifneq ($(findstring clang,$(CC)),)
LTM_CFLAGS += -Wno-unknown-warning-option -Wno-typedef-redefinition -Wno-tautological-compare -Wno-builtin-requires-header -Wno-incomplete-setjmp-declaration
ifdef IGNORE_SPEED
#for dead code eliminiation
LTM_CFLAGS += -O1
endif
endif
ifneq ($(findstring mingw,$(CC)),)
LTM_CFLAGS += -Wno-shadow
endif
ifeq ($(PLATFORM), Darwin)
LTM_CFLAGS += -Wno-nullability-completeness
endif
ifneq ($(findstring $(PLATFORM),CYGWIN MINGW32 MINGW64 MSYS),)
LIBTOOLFLAGS += -no-undefined
endif

# add in the standard FLAGS
LTM_CFLAGS += $(CFLAGS)
LTM_LFLAGS += $(LFLAGS)
LTM_LDFLAGS += $(LDFLAGS)
LTM_LIBTOOLFLAGS += $(LIBTOOLFLAGS)


ifeq ($(PLATFORM),FreeBSD)
  _ARCH := $(shell sysctl -b hw.machine_arch)
else
  _ARCH := $(shell uname -m)
endif

# adjust coverage set
ifneq ($(filter $(_ARCH), i386 i686 x86_64 amd64 ia64),)
   COVERAGE = test timing
   COVERAGE_APP = ./test && ./timing
else
   COVERAGE = test
   COVERAGE_APP = ./test
endif

HEADERS_PUB=tommath.h
HEADERS=tommath_private.h tommath_class.h tommath_superclass.h tommath_cutoffs.h $(HEADERS_PUB)

#LIBPATH  The directory for libtommath to be installed to.
#INCPATH  The directory to install the header files for libtommath.
#DATAPATH The directory to install the pdf docs.
#MANPATH The directory to install the manfile.
DESTDIR  ?=
PREFIX   ?= /usr/local
LIBPATH  ?= $(PREFIX)/lib
INCPATH  ?= $(PREFIX)/include
DATAPATH ?= $(PREFIX)/share/doc/libtommath/pdf
MANPATH ?= $(PREFIX)/share/man

.install_common:
	install -d $(DESTDIR)$(LIBPATH)
	install -d $(DESTDIR)$(INCPATH)

install_docs: manual
	install -d $(DESTDIR)$(DATAPATH)
	install -p -m 644 doc/bn.pdf $(DESTDIR)$(DATAPATH)
	install -d $(DESTDIR)$(MANPATH)
	install -p -m 644 doc/tommath.3 $(DESTDIR)$(MANPATH)/man3


docs manual:
	$(MAKE) -C doc/ $@ V=$(V)

# build & run test-suite
check: test
	./test

#make the code coverage of the library
#
coverage: LTM_CFLAGS += -fprofile-arcs -ftest-coverage -DTIMING_NO_LOGS
coverage: LTM_LFLAGS += -lgcov
coverage: LTM_LDFLAGS += -lgcov

coverage: $(COVERAGE)
	$(COVERAGE_APP)

lcov: coverage
	rm -f coverage.info
	lcov --capture --no-external --no-recursion $(LCOV_ARGS) --output-file coverage.info -q
	genhtml coverage.info --output-directory coverage -q

# target that removes all coverage output
cleancov-clean:
	rm -f `find . -type f -name "*.info" | xargs`
	rm -rf coverage/

# cleans everything - coverage output and standard 'clean'
cleancov: cleancov-clean clean

clean:
	rm -f *.gcda *.gcno *.gcov *.bat *.o *.a *.obj *.lib *.exe *.dll etclib/*.o \
				demo/*.o test timing mtest_opponent mtest/mtest mtest/mtest.exe tuning_list \
				*.s tommath_amalgam.c pre_gen/tommath_amalgam.c *.da *.dyn *.dpi tommath.tex \
				`find . -type f | grep [~] | xargs` *.lo *.la
	rm -rf .libs/ demo/.libs
	${MAKE} -C etc/ clean MAKE=${MAKE}
	${MAKE} -C doc/ clean MAKE=${MAKE}
