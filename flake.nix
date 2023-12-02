{
  inputs = {
    nixpkgs.url = "github:NickCao/nixpkgs";
  };
  outputs = { self, nixpkgs, ... }: {
    hydraJobs = rec {
      inherit (self.nixosConfigurations.netboot.config.system.build) netboot rootblk;
      quickstart = with self.nixosConfigurations.netboot.pkgs; writeShellScriptBin "quickstart" ''
        ${nbd}/bin/nbd-server 127.0.0.1:9999 ${rootblk} --read-only --nodaemon
      '';
    };
    nixosConfigurations.netboot = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ config, pkgs, lib, modulesPath, ... }:
          let
            build = config.system.build;
            kernelTarget = pkgs.stdenv.hostPlatform.linux-kernel.target;
            scratch = "/mnt/scratch";
            rostore = "/mnt/store";
          in
          {
            imports = [
              (modulesPath + "/profiles/minimal.nix")
              (modulesPath + "/profiles/qemu-guest.nix")
            ];

            boot.loader.grub.enable = false;

            boot.kernelPackages = pkgs.linuxPackages_latest;

            boot.kernelParams = [
              "console=ttyS0"
            ];

            boot.initrd.systemd.enable = true;
            boot.initrd.network.enable = true;
            boot.initrd.kernelModules = [ "nbd" "overlay" ];

            boot.initrd.systemd.storePaths = [ pkgs.nbd ];
            boot.initrd.systemd.emergencyAccess = true;

            boot.initrd.systemd.targets.network-online.requiredBy = [ "initrd.target" ];
            boot.initrd.systemd.services.systemd-networkd-wait-online.requiredBy = [ "network-online.target" ];

            boot.initrd.systemd.services.nbd-client = {
              requires = [ "network-online.target" ];
              after = [ "network-online.target" ];
              wantedBy = [ "sysroot-mnt-store.mount" ];
              before = [ "sysroot-mnt-store.mount" ];
              unitConfig = {
                IgnoreOnIsolate = true;
                DefaultDependencies = false;
              };
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.nbd}/bin/nbd-client 10.0.2.2 9999 /dev/nbd0";
              };
            };

            boot.initrd.systemd.services.mkdir-rw-store = {
              wantedBy = [ "sysroot-nix-store.mount" ];
              before = [ "sysroot-nix-store.mount" ];
              unitConfig = {
                IgnoreOnIsolate = true;
                DefaultDependencies = false;
                RequiresMountsFor = [
                  "/sysroot/${scratch}"
                  "/sysroot/${rostore}"
                ];
              };
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = [
                  "${pkgs.coreutils}/bin/mkdir -p /sysroot/${scratch}/upperdir"
                  "${pkgs.coreutils}/bin/mkdir -p /sysroot/${scratch}/workdir"
                ];
              };
            };

            services.getty.autologinUser = "root";

            networking.firewall.enable = false;
            networking.useNetworkd = true;

            system.build.rootblk = pkgs.callPackage (modulesPath + "/../lib/make-squashfs.nix") {
              comp = "zstd -Xcompression-level 6";
              storeContents = [ build.toplevel ];
            };

            fileSystems."/" = {
              fsType = "tmpfs";
              options = [ "defaults" "mode=755" ];
            };

            fileSystems."${scratch}" = {
              fsType = "tmpfs";
              options = [ "defaults" "mode=755" ];
              neededForBoot = true;
            };

            fileSystems."${rostore}" = {
              fsType = "squashfs";
              device = "/dev/nbd0";
              options = [ "_netdev" ];
              neededForBoot = true;
            };

            fileSystems."/nix/store" = {
              fsType = "overlay";
              device = "overlay";
              options = [
                "lowerdir=/sysroot/${rostore}"
                "upperdir=/sysroot/${scratch}/upperdir"
                "workdir=/sysroot/${scratch}/workdir"
              ];
            };

            boot.postBootCommands = ''
              ${config.nix.package}/bin/nix-store --load-db < /nix/store/nix-path-registration
            '';

            system.build.netboot = pkgs.symlinkJoin {
              name = "netboot";
              paths = [
                build.kernel
                build.initialRamdisk
                (pkgs.writeTextDir "netboot.ipxe" ''
                  #!ipxe
                  kernel ${kernelTarget} init=${build.toplevel}/init initrd=initrd ${toString config.boot.kernelParams}
                  initrd initrd
                  boot
                '')
              ];
            };

            services.github-runners.default = {
              enable = true;
              url = "https://github.com/NickCao/bladerunner";
              tokenFile = builtins.toFile "token" "github_pat_something";
              name = "test";
              ephemeral = true;
            };

            system.stateVersion = "23.11";

          })
      ];
    };
  };
}
