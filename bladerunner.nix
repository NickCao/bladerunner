{ config, lib, pkgs, modulesPath, ... }:
let
  build = config.system.build;
  kernelTarget = pkgs.stdenv.hostPlatform.linux-kernel.target;
  rostore = "/mnt/store";
  scratch = "/mnt/scratch";
  scratchDev = "nbd1";
  cfg = config.bladerunner;
in
{

  imports = [
    (modulesPath + "/profiles/minimal.nix")
    # FIXME: replace qemu quest profile with actual kernel modules required for initrd networking
    # boot.initrd.availableKernelModules = [ ];
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
    store = {
      type = lib.mkOption { type = lib.types.str; };
      device = lib.mkOption { type = lib.types.str; };
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

      network.enable = true;

      systemd = {
        enable = true;
        storePaths = [ pkgs.nbd pkgs.libtirpc ];
        emergencyAccess = true;

        initrdBin = [
          (pkgs.runCommand "nfs-utils-sbin" { } ''
            mkdir -p "$out"
            ln -s ${pkgs.nfs-utils}/bin "$out/sbin"
          '')
          pkgs.strace
        ];

        contents = {
          "/etc/protocols".source = "${pkgs.iana-etc}/etc/protocols";
          "/etc/services".source = "${pkgs.iana-etc}/etc/services";
          "/etc/rpc".source = "${pkgs.glibc}/etc/rpc";
          "/etc/nsswitch.conf".source = config.environment.etc."nsswitch.conf".source;
        };

        targets.network-online.requiredBy = [ "initrd.target" ];
        services.systemd-networkd-wait-online.requiredBy = [ "network-online.target" ];

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

        services.mkdir-rw-store = {
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
      };
    };

    hardware.enableRedistributableFirmware = true;

    services.getty.autologinUser = "root";

    networking.firewall.enable = false;

    networking.useNetworkd = true;

    system.build.rootblk = pkgs.callPackage (modulesPath + "/../lib/make-squashfs.nix") {
      # FIXME: before prod, drop this line to use the default compression algo xz
      comp = "zstd -Xcompression-level 6";
      storeContents = [ build.toplevel ];
    };

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
      fsType = cfg.store.type;
      device = cfg.store.device;
      options = [ "_netdev" "nolock" ];
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
      neededForBoot = true;
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
