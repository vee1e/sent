# tens version
VERSION = 1

# Customize below to fit your system

# paths
PREFIX = /usr/local
MANPREFIX = ${PREFIX}/share/man

# macOS Native (Cocoa) - no X11 required
INCS = -I.
LIBS = -framework Cocoa -framework CoreText -framework CoreGraphics -framework QuartzCore

# flags
# Note: Removed -D_XOPEN_SOURCE=600 as it conflicts with macOS SDK headers
CPPFLAGS = -DVERSION=\"${VERSION}\"
CFLAGS += -g -Wall ${INCS} ${CPPFLAGS}
LDFLAGS += -g ${LIBS}

# compiler and linker
CC ?= clang
