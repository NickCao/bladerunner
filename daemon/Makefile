NIX_VER ?= maintenance-2.19
NIX_URL ?= https://hydra.nixos.org/job/nix/$(NIX_VER)/buildStatic.x86_64-linux/latest/download-by-type/file/binary-dist

rootfs.tar.zst: rootfs/bin/daemon rootfs/bin/nix
	tar -c -a -f $@ -C rootfs .

rootfs/bin/daemon: go.mod go.sum daemon.go
	CGO_ENABLE=0 go build -o $@

rootfs/bin/nix:
	mkdir -p rootfs/bin
	wget $(NIX_URL) -O $@
	chmod +x $@
