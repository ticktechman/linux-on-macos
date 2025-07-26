all: linux

linux: main.swift main.entitlements
	swiftc main.swift -o $@ -framework Virtualization
	codesign --entitlements main.entitlements -s - $@

clean:
	rm -f linux
