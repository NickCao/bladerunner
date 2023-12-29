{ config, lib, pkgs, modulesPath, ... }:
let
  build = config.system.build;
  kernelTarget = pkgs.stdenv.hostPlatform.linux-kernel.target;
  rostore = "/mnt/nix";
  scratch = "/mnt/scratch";
  scratchDev = "nbd0";
  cfg = config.bladerunner;
in
{

  imports = [
    (modulesPath + "/profiles/minimal.nix")
    # FIXME: replace qemu quest profile with actual kernel modules required for initrd networking
    # boot.initrd.kernelModules = [ ];
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  options.bladerunner = {
    enable = lib.mkEnableOption (lib.mdDoc "stateless github action runner");
    addr = lib.mkOption {
      type = lib.types.str;
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 10809;
    };
  };

  config = lib.mkIf cfg.enable {

    boot.loader.grub.enable = false;

    boot.kernelPackages = pkgs.linuxPackages_latest;

    boot.kernelParams = [
      # FIXME: Use netconsole
    ];

    boot.initrd = {
      kernelModules = [ "nbd" "overlay" "r8169" "mt7921e" ];

      availableKernelModules = [ "nfsv4" ];

      network.enable = true;

      systemd = {
        enable = true;

        storePaths = [ pkgs.nbd pkgs.util-linux ];
        initrdBin = [
          (pkgs.runCommand "nfs-utils-sbin" { } ''
            mkdir -p "$out"
            ln -s ${pkgs.nfs-utils}/bin "$out/sbin"
          '')
        ];

        emergencyAccess = true;

        targets.network-online.requiredBy = [ "initrd.target" ];
        services.systemd-networkd-wait-online.requiredBy = [ "network-online.target" ];
        network.wait-online.extraArgs = [ "--ipv4" ];

        contents."/etc/nbdtab".text = ''
          ${scratchDev} ${cfg.addr} scratch port=${toString cfg.port}
        '';

        services."nbd@" = {
          before = [ "dev-%i.device" ];
          after = [ "network-online.target" ];
          requires = [ "network-online.target" ];
          conflicts = [ "shutdown.target" ];
          unitConfig = {
            IgnoreOnIsolate = true;
            DefaultDependencies = false;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${lib.getBin pkgs.nbd}/bin/nbd-client %i";
            ExecStop = "${lib.getBin pkgs.nbd}/nbd-client -d /dev/%i";
          };
        };

        services.wipefs-scratch = {
          wantedBy = [ "sysroot-mnt-scratch.mount" ];
          before = [ "systemd-makefs@dev-nbd0.service" ];
          requires = [ "dev-${scratchDev}.device" ];
          after = [ "dev-${scratchDev}.device" ];
          unitConfig = {
            DefaultDependencies = false;
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = [
              "${pkgs.util-linux}/bin/wipefs --all --force /dev/${scratchDev}"
            ];
          };
        };

        services.mkdir-rw-store = {
          wantedBy = [ "sysroot-nix.mount" ];
          before = [ "sysroot-nix.mount" ];
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
      };
    };

    hardware.enableRedistributableFirmware = true;

    services.getty.autologinUser = "root";

    networking.firewall.enable = false;

    networking.useNetworkd = true;

    fileSystems."/" = {
      fsType = "tmpfs";
      options = [ "defaults" "mode=755" ];
    };

    fileSystems."${scratch}" = {
      fsType = "ext4";
      device = "/dev/${scratchDev}";
      options = [ "_netdev" "x-systemd.requires=nbd@${scratchDev}.service" ];
      autoFormat = true;
      neededForBoot = true;
    };

    fileSystems."${rostore}" = {
      fsType = "nfs";
      device = "172.24.5.3:/var/storage/biyun/nixstore/nix";
      # options = [ ];
      neededForBoot = true;
    };

    fileSystems."/nix" = {
      fsType = "overlay";
      device = "overlay";
      options = [
        "lowerdir=/sysroot/${rostore}"
        "upperdir=/sysroot/${scratch}/upperdir"
        "workdir=/sysroot/${scratch}/workdir"
      ];
    };

    system.build.ukiconf = (pkgs.formats.ini { }).generate "uki.conf" {
      UKI = {
        Linux = "${build.kernel}/${kernelTarget}";
        Initrd = "${build.initialRamdisk}/initrd";
        Cmdline = "init=${build.toplevel}/init ${toString config.boot.kernelParams}";
        OSRelease = "@${config.environment.etc.os-release.source}";
        EFIArch = "x64";
        Stub = "${pkgs.systemd}/lib/systemd/boot/efi/linuxx64.efi.stub";
      };
    };

    system.build.netboot = pkgs.runCommand "netboot" { } ''
      mkdir -p "$out"
      ${pkgs.systemdMinimal.override { withUkify = true; withEfi = true; withBootloader = true; }}/lib/systemd/ukify \
        build --config ${build.ukiconf} --output "$out/ipxe.efi"
    '';

  };
}
