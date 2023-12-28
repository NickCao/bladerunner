{
  inputs = {
    # required for the proper operation of nbd-client and nixos/github-runner
    nixpkgs.url = "github:Avimitin/nixpkgs/bladerunner";
  };
  outputs = { self, nixpkgs, ... }: {
    hydraJobs = rec {
      # nix build .#hydraJobs.netboot
      # creates a tftp root directory for pxe boot
      # chain ipxe.efi from pxe
      inherit (self.nixosConfigurations.netboot.config.system.build) netboot toplevel;
      # nix run .#hydraJobs.nbd-server
      # exports a ephemeral scratch disk
      # FIXME: change listenaddr and port
      nbd-server = with self.nixosConfigurations.netboot.pkgs; writeShellScriptBin "nbd-server" ''
        ${nbd}/bin/nbd-server --nodaemon -C ${writeText "config" ''
          [generic]
          listenaddr = 0.0.0.0
          port = 10809
          max_threads = 12

          [scratch]
          exportname = /tmp/%s.img
          temporary = true
          filesize = 1073741824
        ''}
      '';
      daemon = with self.nixosConfigurations.netboot.pkgs; buildGoModule {
        pname = "daemon";
        version = self.sourceInfo.lastModifiedDate;
        src = "${self}/daemon";
        vendorHash = "sha256-Z4Cu+TaeH245rRJSafSR6ST/SNrXu9FKwSnw2fFuGEg=";
        CGO_ENABLED = 0;
      };
      nspawn = with self.nixosConfigurations.netboot.pkgs; runCommand "nspawn" { } ''
        install -D ${daemon}/bin/daemon                "$out/sbin/init"
        install -D ${pkgsStatic.nix}/bin/nix           "$out/bin/nix"
        install -D /dev/null                           "$out/etc/os-release"
      '';
    };
    nixosConfigurations.netboot = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./bladerunner.nix
        {

          bladerunner = {
            enable = true;
            addr = "172.24.5.1";
            port = 10809;
          };

          services.github-runners.sequencer = {
            enable = true;
            # FIXME: use actual repo url and github token
            url = "https://github.com/NickCao/bladerunner";
            tokenFile = "/gh-runner.token";
            name = "sequencer";
            ephemeral = true;
          };

          services.openssh.enable = true;

          users.users.root.openssh.authorizedKeys.keys = [
          ];

          system.stateVersion = "23.11";
        }
      ];
    };
  };
}
