{
  inputs = {
    # required for the proper operation of nbd-client and nixos/github-runner
    nixpkgs.url = "github:NickCao/nixpkgs/bladerunner";
  };
  outputs = { self, nixpkgs, ... }: {
    hydraJobs = rec {
      # nix build .#hydraJobs.netboot
      # creates a tftp root directory for ipxe boot
      # chain netboot.ipxe from ipxe
      inherit (self.nixosConfigurations.netboot.config.system.build) netboot rootblk;
      # nix run .#hydraJobs.nbd-server
      # exports a readonly nix store and a ephemeral scratch disk
      # FIXME: change listenaddr and port
      nbd-server = with self.nixosConfigurations.netboot.pkgs; writeShellScriptBin "nbd-server" ''
        ${nbd}/bin/nbd-server --nodaemon -C ${writeText "config" ''
          [generic]
          listenaddr = 0.0.0.0
          port = 10809
          max_threads = 12

          [rostore]
          exportname = ${rootblk}

          [scratch]
          exportname = /tmp/%s.img
          temporary = true
          filesize = 1073741824
        ''}
      '';
    };
    nixosConfigurations.netboot = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./bladerunner.nix
        { bladerunner.enable = true; }
      ];
    };
  };
}
