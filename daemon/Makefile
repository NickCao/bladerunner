NIX_VER ?= maintenance-2.19
NIX_URL ?= https://hydra.nixos.org/job/nix/$(NIX_VER)/buildStatic.x86_64-linux/latest/download-by-type/file/binary-dist

rootfs.tar.zst: rootfs/sbin/init rootfs/bin/nix rootfs/etc/os-release
	tar -c -a -f $@ -C rootfs .

rootfs/sbin/init: go.mod go.sum init.go
	CGO_ENABLE=0 go build -o $@

rootfs/bin/nix:
	mkdir -p rootfs/bin
	wget $(NIX_URL) -O $@
	chmod +x $@

rootfs/etc/os-release:
	mkdir -p rootfs/etc
	touch rootfs/etc/os-release
