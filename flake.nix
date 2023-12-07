{
  inputs = {
    nixpkgs.url = "github:NickCao/nixpkgs";
  };
  outputs = { self, nixpkgs, ... }: {
    hydraJobs = rec {
      inherit (self.nixosConfigurations.netboot.config.system.build) netboot rootblk;
      nbd-server = with self.nixosConfigurations.netboot.pkgs; writeShellScriptBin "nbd-server" ''
        ${nbd}/bin/nbd-server --nodaemon -C ${writeText "config" ''
          [generic]
          listenaddr = 127.0.0.1
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
      modules = [ ./bladerunner.nix ];
    };
  };
}
