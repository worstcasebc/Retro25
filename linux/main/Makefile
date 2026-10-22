# SPDX-License-Identifier: GPL-3.0-or-later
# Makefile für Main_MiSTer auf dem DE25-Nano (aarch64, Ubuntu 22.04).
#
# Abgeleitet vom Makefile in linux/vendor/main_mister. Unterschiede:
#   - nativer gcc statt arm-none-linux-gnueabihf (gebaut wird auf dem Board
#     oder in einem arm64-Container mit derselben Ubuntu-Version)
#   - Bibliotheken aus Ubuntu-Paketen statt der vorgebauten 32-bit-.so
#   - libco: lib/libco/libco.c wählt selbst (aarch64 → sjlj.c) statt arm.c
#
# Nicht direkt aufrufen: build.sh legt den Quellbaum an (vendor + Patches +
# Ersatzdateien aus de25/) und ruft dann  make -C <quellbaum> -f <dieses File>.

SHELL = /bin/bash -o pipefail
MAKEFLAGS += "-j $(shell nproc)"

CC      = gcc
LD      = ld
STRIP   = strip

ifeq ($(V),1)
	Q :=
else
	Q := @
endif

INCLUDE  = -I./
INCLUDE += -I./lib/libco
INCLUDE += -I./lib/miniz
INCLUDE += -I./lib/md5
INCLUDE += -I./lib/lzma
INCLUDE += -I./lib/zstd/lib
INCLUDE += -I./lib/libchdr/include
INCLUDE += -I./lib/bluetooth
INCLUDE += -I./lib/serial_server/library

BUILDDIR = bin

PRJ = MiSTer
C_SRC =   $(wildcard *.c) \
          $(wildcard ./lib/miniz/*.c) \
          $(wildcard ./lib/md5/*.c) \
          $(wildcard ./lib/lzma/*.c) \
          $(wildcard ./lib/zstd/lib/common/*.c) \
          $(wildcard ./lib/zstd/lib/decompress/*.c) \
          $(wildcard ./lib/libchdr/*.c) \
          lib/libco/libco.c

CPP_SRC = $(wildcard *.cpp) \
          $(wildcard ./lib/serial_server/library/*.cpp) \
          $(wildcard ./support/*/*.cpp)

IMG =     $(wildcard *.png)

LIBS    = -lImlib2 -lfreetype -lbz2 -lpng16 -lz -ldl -lbluetooth

OBJ	= $(C_SRC:%.c=$(BUILDDIR)/%.c.o) $(CPP_SRC:%.cpp=$(BUILDDIR)/%.cpp.o) $(IMG:%.png=$(BUILDDIR)/%.png.o)
DEP	= $(C_SRC:%.c=$(BUILDDIR)/%.c.d) $(CPP_SRC:%.cpp=$(BUILDDIR)/%.cpp.d)

DFLAGS	= $(INCLUDE) -D_7ZIP_ST -DPACKAGE_VERSION=\"1.3.3\" -DHAVE_LROUND -DHAVE_STDINT_H -DHAVE_STDLIB_H -DHAVE_SYS_PARAM_H -DENABLE_64_BIT_WORDS=0 -D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE -DVDATE=\"`date +"%y%m%d"`\" -DRETRO25_DE25
CFLAGS	= $(DFLAGS) -Wall -Wextra -Wno-strict-aliasing -Wno-stringop-overflow -Wno-stringop-truncation -Wno-format-truncation -Wno-psabi -Wno-restrict -c
LFLAGS	= -lc -lstdc++ -lm -lrt $(LIBS) -lpthread

OUTPUT_FILTER = sed -e 's/\(.[a-zA-Z]\+\):\([0-9]\+\):\([0-9]\+\):/\1(\2,\ \3):/g'

ifneq ($(DEBUG),1)
	CFLAGS += -O3
else
	CFLAGS += -O0 -g -fomit-frame-pointer
endif

ifeq ($(PROFILING),1)
	DFLAGS += -DPROFILING
endif

$(BUILDDIR)/$(PRJ): $(OBJ)
	$(Q)$(info $@)
	$(Q)$(CC) -o $@ $+ $(LFLAGS)
	$(Q)cp $@ $@.elf
ifneq ($(DEBUG),1)
	$(Q)$(STRIP) $@
endif

.PHONY: clean
clean:
	$(Q)rm -rf bin

# libco: sjlj.c benutzt thread_local, ohne settings.h einzubinden (arm.c tut
# es) — für C99 hier nachreichen. __thread = GCC-Erweiterung, gleiche Wirkung.
$(BUILDDIR)/lib/libco/libco.c.o: CFLAGS += -Dthread_local=__thread
# sjlj.c springt per siglongjmp zwischen den Stacks der Koroutinen. Ubuntus gcc
# setzt _FORTIFY_SOURCE; dann prüft glibc (__longjmp_chk), ob das Ziel auf dem
# aktuellen Stack liegt, und bricht ab ("longjmp causes uninitialized stack
# frame"). Für diese eine Datei abschalten.
$(BUILDDIR)/lib/libco/libco.c.o: CFLAGS += -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0

$(BUILDDIR)/%.c.o: %.c
	$(Q)$(info $<)
	$(Q)$(CC) $(CFLAGS) -std=gnu99 -o $@ -c $< 2>&1 | $(OUTPUT_FILTER)

$(BUILDDIR)/%.cpp.o: %.cpp
	$(Q)$(info $<)
	$(Q)$(CC) $(CFLAGS) -std=gnu++14 -Wno-class-memaccess -o $@ -c $< 2>&1 | $(OUTPUT_FILTER)

# Bilder als Objektdatei einbinden (ld -r -b binary, Symbole _binary_<name>_png_*)
$(BUILDDIR)/%.png.o: %.png
	$(Q)$(info $<)
	$(Q)$(LD) -r -b binary -o $@ $< 2>&1 | $(OUTPUT_FILTER)

ifneq ($(MAKECMDGOALS), clean)
-include $(DEP)
endif
$(BUILDDIR)/%.c.d: %.c
	@mkdir -p $(dir $(BUILDDIR)/$*)
	$(Q)$(info $< >> $@)
	$(Q)$(CC) $(DFLAGS) -MM $< -MT $@ -MT $*.c.o -MF $@ 2>&1 | $(OUTPUT_FILTER)

$(BUILDDIR)/%.cpp.d: %.cpp
	@mkdir -p $(dir $(BUILDDIR)/$*)
	$(Q)$(info $< >> $@)
	$(Q)$(CC) $(DFLAGS) -MM $< -MT $@ -MT $*.cpp.o -MF $@ 2>&1 | $(OUTPUT_FILTER)

# Ensure correct time stamp
$(BUILDDIR)/main.cpp.o: $(filter-out $(BUILDDIR)/main.cpp.o, $(OBJ))
