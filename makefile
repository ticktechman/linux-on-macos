all: linux glinux

linux: main.swift main.entitlements
	swiftc main.swift -o $@ -framework Virtualization
	codesign --entitlements main.entitlements -s - $@

glinux: glinux.swift main.entitlements
	swiftc glinux.swift -o $@ -framework Virtualization -framework Cocoa
	codesign --entitlements main.entitlements -s - $@
	./pack.sh

clean:
	rm -rf linux glinux guilinux.app
