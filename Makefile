# tens - plain text presentation tool
# See LICENSE file for copyright and license details.

include config.mk

SRC = tens.m drw.m util.c
OBJ = tens.o drw.o util.o

all: options tens

options:
	@echo tens build options:
	@echo "CFLAGS   = ${CFLAGS}"
	@echo "LDFLAGS  = ${LDFLAGS}"
	@echo "CC       = ${CC}"

config.h:
	cp config.def.h config.h

util.o: util.c util.h config.h config.mk
	${CC} -c ${CFLAGS} util.c -o util.o

drw.o: drw.m drw.h util.h config.h config.mk
	${CC} -c ${CFLAGS} -fobjc-arc drw.m -o drw.o

tens.o: tens.m drw.h util.h arg.h config.h config.mk
	${CC} -c ${CFLAGS} -fobjc-arc tens.m -o tens.o

tens: ${OBJ}
	${CC} -o $@ ${OBJ} ${LDFLAGS}

cscope: ${SRC} config.h
	cscope -R -b || echo cScope not installed

clean:
	rm -f tens ${OBJ} tens-${VERSION}.tar.gz

dist: clean
	mkdir -p tens-${VERSION}
	cp -R LICENSE Makefile config.mk config.def.h ${SRC} tens-${VERSION}
	tar -cf tens-${VERSION}.tar tens-${VERSION}
	gzip tens-${VERSION}.tar
	rm -rf tens-${VERSION}

install: all
	mkdir -p ${DESTDIR}${PREFIX}/bin
	cp -f tens ${DESTDIR}${PREFIX}/bin
	chmod 755 ${DESTDIR}${PREFIX}/bin/tens
	mkdir -p ${DESTDIR}${MANPREFIX}/man1
	cp tens.1 ${DESTDIR}${MANPREFIX}/man1/tens.1
	chmod 644 ${DESTDIR}${MANPREFIX}/man1/tens.1

uninstall:
	rm -f ${DESTDIR}${PREFIX}/bin/tens

.PHONY: all options clean dist install uninstall cscope
