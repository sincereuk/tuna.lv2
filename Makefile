#!/usr/bin/make -f
# these can be overridden using make variables. e.g.
#   make install DESTDIR=$(CURDIR)/debian/meters.lv2 PREFIX=/usr

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
MANDIR ?= $(PREFIX)/share/man/man1
# see http://lv2plug.in/pages/filesystem-hierarchy-standard.html, don't use libdir
LV2DIR ?= $(PREFIX)/lib/lv2

OPTIMIZATIONS ?= -msse -msse2 -mfpmath=sse -ffast-math -fomit-frame-pointer -O3 -fno-finite-math-only -DNDEBUG
CFLAGS ?= -g -Wall -Wno-unused-function
STRIP  ?= strip

BUILDOPENGL?=yes
BUILDJACKAPP?=yes

tuna_VERSION?=$(shell git describe --tags HEAD | sed 's/-g.*$$//;s/^v//' || echo "LV2")
RW ?= robtk/

###############################################################################
BUILDDIR = build/
APPBLD   = x42/

###############################################################################

LV2NAME=tuna
LV2GUI=tunaUI_gl
BUNDLE=tuna.lv2
targets=

LOADLIBES=-lm
LV2UIREQ=
GLUICFLAGS=-I.

ifneq ($(MOD),)
  INLINEDISPLAY=no
  BUILDOPENGL=no
  BUILDJACKAPP=no
endif



UNAME=$(shell uname)
ifeq ($(UNAME),Darwin)
  LV2LDFLAGS=-dynamiclib
  LIB_EXT=.dylib
  EXE_EXT=
  UI_TYPE=ui:CocoaUI
  PUGL_SRC=$(RW)pugl/pugl_osx.m
  PKG_GL_LIBS=
  GLUILIBS=-framework Cocoa -framework OpenGL -framework CoreFoundation
  STRIPFLAGS=-u -r -arch all -s $(RW)lv2syms
  EXTENDED_RE=-E
else
  LV2LDFLAGS=-Wl,-Bstatic -Wl,-Bdynamic -Wl,--as-needed
  LIB_EXT=.so
  EXE_EXT=
  UI_TYPE=ui:X11UI
  PUGL_SRC=$(RW)pugl/pugl_x11.c
  PKG_GL_LIBS=glu gl
  GLUILIBS=-lX11
  GLUICFLAGS+=`pkg-config --cflags glu`
  STRIPFLAGS= -s
  EXTENDED_RE=-r
endif

ifneq ($(XWIN),)
  CC=$(XWIN)-gcc
  CXX=$(XWIN)-g++
  STRIP=$(XWIN)-strip
  LV2LDFLAGS=-Wl,-Bstatic -Wl,-Bdynamic -Wl,--as-needed -lpthread
  LIB_EXT=.dll
  EXE_EXT=.exe
  PUGL_SRC=$(RW)pugl/pugl_win.cpp
  PKG_GL_LIBS=
  UI_TYPE=ui:WindowsUI
  GLUILIBS=-lws2_32 -lwinmm -lopengl32 -lglu32 -lgdi32 -lcomdlg32 -lpthread
  GLUICFLAGS=-I.
  override LDFLAGS += -static-libgcc -static-libstdc++
endif

ifeq ($(EXTERNALUI), yes)
  UI_TYPE=
endif

ifeq ($(UI_TYPE),)
  UI_TYPE=kx:Widget
  LV2UIREQ+=lv2:requiredFeature kx:Widget;
  override CXXFLAGS += -DXTERNAL_UI
endif

targets+=$(BUILDDIR)$(LV2NAME)$(LIB_EXT)

UITTL=
ifneq ($(BUILDOPENGL), no)
  targets+=$(BUILDDIR)$(LV2GUI)$(LIB_EXT)
  UITTL=ui:ui $(LV2NAME):ui_gl ;
endif

###############################################################################
# extract versions
LV2VERSION=$(tuna_VERSION)
include git2lv2.mk

###############################################################################
# check for build-dependencies
ifeq ($(shell pkg-config --exists lv2 || echo no), no)
  $(error "LV2 SDK was not found")
endif

ifeq ($(shell pkg-config --exists fftw3f || echo no), no)
  $(error "fftw3f library was not found")
endif

ifeq ($(shell pkg-config --atleast-version=1.6.0 lv2 || echo no), no)
  $(error "LV2 SDK needs to be version 1.6.0 or later")
endif

ifneq ($(BUILDOPENGL)$(BUILDJACKAPP), nono)
 ifeq ($(shell pkg-config --exists pango cairo $(PKG_GL_LIBS) || echo no), no)
  $(error "This plugin requires cairo pango $(PKG_GL_LIBS)")
 endif
endif

ifneq ($(BUILDJACKAPP), no)
 ifeq ($(shell pkg-config --exists jack || echo no), no)
  $(warning *** libjack from http://jackaudio.org is required)
  $(error   Please install libjack-dev or libjack-jackd2-dev)
 endif
 JACKAPP=$(APPBLD)x42-tuna-collection$(EXE_EXT)
endif

# check for lv2_atom_forge_object  new in 1.8.1 deprecates lv2_atom_forge_blank
ifeq ($(shell pkg-config --atleast-version=1.8.1 lv2 && echo yes), yes)
  override CFLAGS += -DHAVE_LV2_1_8
endif

ifneq ($(BUILDOPENGL)$(BUILDJACKAPP), nono)
 ifneq ($(MAKECMDGOALS), submodules)
  ifeq ($(wildcard $(RW)robtk.mk),)
    $(warning "**********************************************************")
    $(warning This plugin needs https://github.com/x42/robtk)
    $(warning "**********************************************************")
    $(info )
    $(info set the RW environment variale to the location of the robtk headers)
    ifeq ($(wildcard .git),.git)
      $(info or run 'make submodules' to initialize robtk as git submodule)
    endif
    $(info )
    $(warning "**********************************************************")
    $(error robtk not found)
  endif
 endif
endif

# LV2 idle >= lv2-1.6.0
GLUICFLAGS+=-DHAVE_IDLE_IFACE
LV2UIREQ+=lv2:requiredFeature ui:idleInterface; lv2:extensionData ui:idleInterface;

# add library dependent flags and libs
override CFLAGS +=-g $(OPTIMIZATIONS) -DVERSION="\"$(tuna_VERSION)\""
override CFLAGS += `pkg-config --cflags lv2 fftw3f`
override LOADLIBES += `pkg-config --libs lv2 fftw3f`
ifeq ($(XWIN),)
override CFLAGS += -fPIC -fvisibility=hidden
else
override CFLAGS += -DPTW32_STATIC_LIB
endif


GLUICFLAGS+=`pkg-config --cflags cairo pango`
GLUILIBS+=`pkg-config $(PKG_UI_FLAGS) --libs cairo pango pangocairo $(PKG_GL_LIBS)`

ifneq ($(XWIN),)
GLUILIBS+=-lpthread -lusp10
endif

GLUICFLAGS+=$(LIC_CFLAGS)
GLUILIBS+=$(LIC_LOADLIBES)

ifeq ($(GLTHREADSYNC), yes)
  GLUICFLAGS+=-DUSE_GUI_THREAD
  GLUICFLAGS+=-DTHREADSYNC
endif

ifneq ($(LIC_CFLAGS),)
  SIGNATURE=, <http:\\/\\/harrisonconsoles.com\\/lv2\\/license\#interface>
endif

ROBGL+= Makefile

JACKCFLAGS=-I. $(CXXFLAGS) $(LIC_CFLAGS)
JACKCFLAGS+=`pkg-config --cflags jack lv2 pango pangocairo fftw3 $(PKG_GL_LIBS)`
JACKLIBS=-lm $(GLUILIBS) $(LIC_LOADLIBES)

###############################################################################
# build target definitions
default: all

submodule_pull:
	-test -d .git -a .gitmodules -a -f Makefile.git && $(MAKE) -f Makefile.git submodule_pull

submodule_update:
	-test -d .git -a .gitmodules -a -f Makefile.git && $(MAKE) -f Makefile.git submodule_update

submodule_check:
	-test -d .git -a .gitmodules -a -f Makefile.git && $(MAKE) -f Makefile.git submodule_check

submodules:
	-test -d .git -a .gitmodules -a -f Makefile.git && $(MAKE) -f Makefile.git submodules

all: submodule_check $(BUILDDIR)manifest.ttl $(BUILDDIR)$(LV2NAME).ttl $(targets) $(JACKAPP)

$(BUILDDIR)manifest.ttl: lv2ttl/manifest.gl.ttl.in lv2ttl/manifest.lv2.ttl.in lv2ttl/manifest.ttl.in Makefile
	@mkdir -p $(BUILDDIR)
	sed "s/@LV2NAME@/$(LV2NAME)/g;s/@LIB_EXT@/$(LIB_EXT)/g" \
	    lv2ttl/manifest.ttl.in > $(BUILDDIR)manifest.ttl
	sed "s/@INSTANCE@/one/g;s/@LV2NAME@/$(LV2NAME)/g;s/@LIB_EXT@/$(LIB_EXT)/g;s/@URI_SUFFIX@//g" \
	    lv2ttl/manifest.lv2.ttl.in >> $(BUILDDIR)manifest.ttl
	sed "s/@INSTANCE@/two/g;s/@LV2NAME@/$(LV2NAME)/g;s/@LIB_EXT@/$(LIB_EXT)/g;s/@URI_SUFFIX@//g" \
	    lv2ttl/manifest.lv2.ttl.in >> $(BUILDDIR)manifest.ttl
ifneq ($(BUILDOPENGL), no)
	sed "s/@LV2NAME@/$(LV2NAME)/g;s/@LIB_EXT@/$(LIB_EXT)/g;s/@UI_TYPE@/$(UI_TYPE)/;s/@LV2GUI@/$(LV2GUI)/g" \
	    lv2ttl/manifest.gl.ttl.in >> $(BUILDDIR)manifest.ttl
endif

$(BUILDDIR)$(LV2NAME).ttl: lv2ttl/$(LV2NAME).ttl.in lv2ttl/$(LV2NAME).lv2.ttl.in lv2ttl/$(LV2NAME).gui.ttl.in Makefile
	@mkdir -p $(BUILDDIR)
	sed "s/@LV2NAME@/$(LV2NAME)/g" \
	    lv2ttl/$(LV2NAME).ttl.in > $(BUILDDIR)$(LV2NAME).ttl
ifneq ($(BUILDOPENGL), no)
	sed "s/@LV2NAME@/$(LV2NAME)/g;s/@UI_URI_SUFFIX@/_gl/;s/@UI_TYPE@/$(UI_TYPE)/;s/@UI_REQ@/$(LV2UIREQ)/;s/@URI_SUFFIX@//g" \
	    lv2ttl/$(LV2NAME).gui.ttl.in >> $(BUILDDIR)$(LV2NAME).ttl
endif
	sed "s/@INSTANCE@/one/g;s/@LV2NAME@/$(LV2NAME)/g;s/@URI_SUFFIX@//g;s/@NAME_SUFFIX@//g;s/@UITTL@/$(UITTL)/g;s/@SIGNATURE@/$(SIGNATURE)/;s/@VERSION@/lv2:microVersion $(LV2MIC) ;lv2:minorVersion $(LV2MIN) ;/g" \
	  lv2ttl/$(LV2NAME).lv2.ttl.in >> $(BUILDDIR)$(LV2NAME).ttl
	sed "s/@INSTANCE@/two/g;s/@LV2NAME@/$(LV2NAME)/g;s/@URI_SUFFIX@//g;s/@NAME_SUFFIX@/[Spectrum]/g;s/@UITTL@/$(UITTL)/g;s/@SIGNATURE@/$(SIGNATURE)/;s/@VERSION@/lv2:microVersion $(LV2MIC) ;lv2:minorVersion $(LV2MIN) ;/g" \
	  lv2ttl/$(LV2NAME).lv2.ttl.in >> $(BUILDDIR)$(LV2NAME).ttl

DSP_SRC = src/tuna.c
DSP_DEPS = $(DSP_SRC) src/spectr.c src/fft.c src/tuna.h
GUI_DEPS =

$(BUILDDIR)$(LV2NAME)$(LIB_EXT): $(DSP_DEPS) Makefile
	@mkdir -p $(BUILDDIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LV2CFLAGS) -std=c99 $(LIC_CFLAGS) \
	  -o $(BUILDDIR)$(LV2NAME)$(LIB_EXT) $(DSP_SRC) \
	  -shared $(LV2LDFLAGS) $(LDFLAGS) $(LOADLIBES) $(LIC_LOADLIBES)
	$(STRIP) $(STRIPFLAGS) $(BUILDDIR)$(LV2NAME)$(LIB_EXT)

jackapps: \
	$(APPBLD)x42-tuna$(EXE_EXT) \
	$(APPBLD)x42-tuna-collection$(EXE_EXT) \
	$(APPBLD)x42-tuna-fft$(EXE_EXT)

JACKCFLAGS=-I. $(CFLAGS) $(CXXFLAGS) $(LIC_CFLAGS)
JACKCFLAGS+=`pkg-config --cflags jack lv2 pango pangocairo $(PKG_GL_LIBS)`
JACKLIBS=-lm $(LOADLIBES) $(GLUILIBS) $(LIC_LOADLIBES)

$(eval x42_tuna_JACKSRC = src/tuna.c)
x42_tuna_JACKGUI = gui/tuna.c
x42_tuna_LV2HTTL = lv2ttl/tuna1.h
x42_tuna_JACKDESC = lv2ui_descriptor
$(APPBLD)x42-tuna$(EXE_EXT): $(DSP_DEPS) $(GUI_DEPS) \
	        $(x42_tuna_JACKGUI) $(x42_tuna_LV2HTTL)

$(eval x42_tuna_fft_JACKSRC = src/tuna.c)
x42_tuna_fft_JACKGUI = gui/tuna.c
x42_tuna_fft_LV2HTTL = lv2ttl/tuna2.h
x42_tuna_fft_JACKDESC = lv2ui_descriptor
$(APPBLD)x42-tuna-fft$(EXE_EXT): $(DSP_DEPS) $(GUI_DEPS) \
	        $(x42_tuna_JACKGUI) $(x42_tuna_LV2HTTL)

$(eval x42_tuna_collection_JACKSRC = -DX42_MULTIPLUGIN src/tuna.c $(APPBLD)x42-tuna.o)
x42_tuna_collection_LV2HTTL = lv2ttl/plugins.h
$(APPBLD)x42-tuna-collection$(EXE_EXT): $(DSP_DEPS) $(GUI_DEPS) \
	$(APPBLD)x42-tuna.o lv2ttl/tuna1.h lv2ttl/tuna2.h lv2ttl/plugins.h


ifneq ($(BUILDOPENGL)$(BUILDJACKAPP), nono)
 -include $(RW)robtk.mk
endif

$(BUILDDIR)$(LV2GUI)$(LIB_EXT): gui/tuna.c src/tuna.h

###############################################################################
# install/uninstall/clean target definitions

install: install-bin install-man

uninstall: uninstall-bin uninstall-man

install-bin: all
	install -d $(DESTDIR)$(LV2DIR)/$(BUNDLE)
	install -m644 $(BUILDDIR)manifest.ttl $(BUILDDIR)$(LV2NAME).ttl $(DESTDIR)$(LV2DIR)/$(BUNDLE)
	install -m755 $(BUILDDIR)$(LV2NAME)$(LIB_EXT) $(DESTDIR)$(LV2DIR)/$(BUNDLE)
ifneq ($(BUILDOPENGL), no)
	install -m755 $(BUILDDIR)$(LV2GUI)$(LIB_EXT) $(DESTDIR)$(LV2DIR)/$(BUNDLE)
endif
ifneq ($(BUILDJACKAPP), no)
	install -d $(DESTDIR)$(BINDIR)
	install -T -m755 $(APPBLD)x42-tuna-collection$(EXE_EXT) $(DESTDIR)$(BINDIR)/x42-tuna$(EXE_EXT)
endif

uninstall-bin:
	rm -f $(DESTDIR)$(LV2DIR)/$(BUNDLE)/manifest.ttl
	rm -f $(DESTDIR)$(LV2DIR)/$(BUNDLE)/$(LV2NAME).ttl
	rm -f $(DESTDIR)$(LV2DIR)/$(BUNDLE)/$(LV2NAME)$(LIB_EXT)
	rm -f $(DESTDIR)$(LV2DIR)/$(BUNDLE)/$(LV2GUI)$(LIB_EXT)
	rm -f $(DESTDIR)$(BINDIR)/x42-tuna$(EXE_EXT)
	-rmdir $(DESTDIR)$(LV2DIR)/$(BUNDLE)
	-rmdir $(DESTDIR)$(BINDIR)

install-man:
ifneq ($(BUILDJACKAPP), no)
	install -d $(DESTDIR)$(MANDIR)
	install -m644 x42-tuna.1 $(DESTDIR)$(MANDIR)
endif

uninstall-man:
	rm -f $(DESTDIR)$(MANDIR)/x42-tuna.1
	-rmdir $(DESTDIR)$(MANDIR)

man: $(APPBLD)x42-tuna-collection
	help2man -N -n 'JACK Music Instrument Tuner' -o x42-tuna.1 $(APPBLD)x42-tuna-collection


clean:
	rm -f $(BUILDDIR)manifest.ttl $(BUILDDIR)$(LV2NAME).ttl \
	  $(BUILDDIR)$(LV2NAME)$(LIB_EXT) \
	  $(BUILDDIR)$(LV2GUI)$(LIB_EXT)
	rm -rf $(BUILDDIR)*.dSYM
	rm -rf $(APPBLD)x42-*
	-test -d $(APPBLD) && rmdir $(APPBLD) || true
	-test -d $(BUILDDIR) && rmdir $(BUILDDIR) || true

distclean: clean
	rm -f cscope.out cscope.files tags

.PHONY: clean all install uninstall distclean jackapps man \
        install-bin uninstall-bin install-man uninstall-man \
        submodule_check submodules submodule_update submodule_pull
