MyProductName = "SSHFS-Win"
MyCompanyName = "Navimatics LLC"
MyDescription = "SSHFS for Windows"
MyProductVersion = "2021.1 Beta2"
MyProductStage = "Beta"
MyVersion = 3.7.$(shell date '+%y%j')
ifeq ($(shell uname -m),x86_64)
	MyArch = x64
else
	MyArch = x86
endif

CertIssuer = "DigiCert"
CrossCert = "DigiCert High Assurance EV Root CA.crt"

PrjDir	= $(shell pwd)
BldDir	= .build/$(MyArch)
DistDir = $(BldDir)/dist
SrcDir	= $(BldDir)/src
RootDir	= $(BldDir)/root
WixDir	= $(BldDir)/wix
Status	= $(BldDir)/status
BinExtra= ssh #bash ls mount

FUSE3=$(shell realpath -m $(SrcDir)/cygfuse/source/v3/fuse3)

# this add fuse stuff
export CFLAGS+= -I$(FUSE3) -L$(FUSE3)
export CC=gcc

goal: $(Status) $(Status)/done

$(Status):
	mkdir -p $(Status)

$(Status)/done: $(Status)/dist
	touch $(Status)/done

$(Status)/dist: $(Status)/wix
	mkdir -p $(DistDir)
	cp $(shell cygpath -aw $(WixDir)/sshfs-win-$(MyVersion)-$(MyArch).exe) $(DistDir)
	tools/signtool sign \
		/ac tools/$(CrossCert) \
		/i $(CertIssuer) \
		/n $(MyCompanyName) \
		/d $(MyDescription) \
		/fd sha1 \
		/t http://timestamp.digicert.com \
		'$(shell cygpath -aw $(DistDir)/sshfs-win-$(MyVersion)-$(MyArch).exe)' || \
		echo "SIGNING FAILED! The product has been successfully built, but not signed." 1>&2
	touch $(Status)/dist

$(Status)/wix: $(Status)/sshfs-win sshfs-win.nsi
	mkdir -p $(WixDir)
	makensis\
		-dMyProductName=$(MyProductName)\
		-dMyCompanyName=$(MyCompanyName)\
		-dMyDescription=$(MyDescription)\
		-dMyProductVersion=$(MyProductVersion)\
		-dMyProductStage=$(MyProductStage)\
		-dMyVersion=$(MyVersion)\
		-dMyArch=$(MyArch)\
		-DMySrcDir=$(RootDir)\
		-DMyOutFile=$(shell cygpath -am $(WixDir)/sshfs-win-$(MyVersion)-$(MyArch).exe)\
    sshfs-win.nsi
	touch $(Status)/wix

$(Status)/sshfs-win: $(Status)/root sshfs-win.c
	gcc -o $(RootDir)/bin/sshfs-win -O2 $(CFLAGS) sshfs-win.c
	strip $(RootDir)/bin/sshfs-win
	touch $(Status)/sshfs-win

$(Status)/root: $(Status)/make
	mkdir -p $(RootDir)/{bin,dev/{mqueue,shm},etc}
	cp $(FUSE3)/*.dll $(RootDir)/bin
	(cygcheck $(SrcDir)/sshfs/build/sshfs; for f in $(BinExtra); do cygcheck /usr/bin/$$f; done) |\
		tr -d '\r' | tr '\\' / | xargs cygpath -au | grep '^/usr/bin/' | sort | uniq |\
		while read f; do cp $$f $(RootDir)/bin; done
	cp $(SrcDir)/sshfs/build/sshfs $(RootDir)/bin
	strip $(RootDir)/bin/sshfs
	for f in $(BinExtra); do cp /usr/bin/$$f $(RootDir)/bin; done
	cp -R $(PrjDir)/etc $(RootDir)
	touch $(Status)/root

$(Status)/make: $(Status)/config
	cd $(FUSE3) && make
	cd $(SrcDir)/sshfs/build && ninja
	touch $(Status)/make

$(Status)/config: $(Status)/patch
	mkdir -p $(SrcDir)/sshfs/build
	cd $(SrcDir)/sshfs/build && meson ..
	touch $(Status)/config

$(Status)/patch: $(Status)/clone
	cd $(SrcDir)/sshfs && for f in $(PrjDir)/patches/sshfs/*.patch; do patch --binary -p1 <$$f; done
	cd $(SrcDir)/cygfuse && for f in $(PrjDir)/patches/cygfuse/*.patch; do patch --binary -p1 <$$f; done
	touch $(Status)/patch

$(Status)/clone:
	mkdir -p $(SrcDir)
	git clone $(PrjDir)/sshfs $(SrcDir)/sshfs
	git clone $(PrjDir)/cygfuse $(SrcDir)/cygfuse
	touch $(Status)/clone

clean:
	git clean -dffx
