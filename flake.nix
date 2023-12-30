{
  inputs = {
    # required for the proper operation of nbd-client and nixos/github-runner
    nixpkgs.url = "github:Avimitin/nixpkgs/bladerunner";

    # ssh keys, for debugging usage. Run nix flake update to update them
    sequencer = {
      url = "https://github.com/sequencer.keys";
      flake = false;
    };
    avimitin = {
      url = "https://github.com/Avimitin.keys";
      flake = false;
    };
    nickcao = {
      url = "https://github.com/NickCao.keys";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, sequencer, avimitin, nickcao, ... }: {
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
    nixosConfigurations.netboot =
      let
        pkgs = self.nixosConfigurations.netboot.pkgs;
      in
      nixpkgs.lib.nixosSystem {
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
              tokenFile = "/nix/gh-runner.token";
              name = "sequencer";
              replace = true;
              ephemeral = true;
              extraPackages = with pkgs; [
                python3
                jq
                findutils
                git
                gnutar
              ];
            };
            systemd.services."restore-nix-nfs-db@" =
              let
                script = pkgs.writeScript "restore-nix-nfs-db" ''
                  set -ex
                  export PATH="/run/current-system/sw/bin:$PATH"
                  db_file=$(mktemp)
                  nix-store --dump-db --store ssh-ng://simisear > $db_file
                  nix-store --load-db < $db_file
                  rm $db_file
                '';
              in
              {
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = [ "/run/current-system/sw/bin/bash ${script}" ];
                  Restart = "on-failure";
                  RestartSec = "10s";
                  StandardOutput = "socket";
                  StandardError = "socket";
                };
              };
            systemd.sockets.restore-nix-nfs-db = {
              before = [ "github-runner-sequencer.service" ];
              socketConfig = {
                ListenStream = "11451";
                Accept = true;
              };
              wantedBy = [ "sockets.target" ];
            };

            services.openssh.enable = true;
            # FIXME: replace this into remote cache
            programs.ssh.extraConfig = ''
              StrictHostKeyChecking accept-new
              Host example
                  Hostname example.com
                  Port 22
            '';

            users.users.root.openssh.authorizedKeys.keys = with pkgs.lib; let
              splitKey = f: splitString "\n" (readFile f);
            in
            splitKey sequencer ++ splitKey avimitin ++ splitKey nickcao ++ [ ];

            nix.settings = {
              experimental-features = [ "nix-command" "flakes" ];
              post-build-hook = with pkgs; writeShellApplication {
                name = "upload-to-cache";
                runtimeInputs = [ ];
                text = ''
                  set -eu
                  set -f # disable globbing

                  echo "Post-build hook invoked at $USER ($(whoami))" | tee -a /tmp/nix-post-build-hook.log

                  echo "Uploading paths" "$OUT_PATHS" | tee -a /tmp/nix-post-build-hook.log
                  IFS=' ' read -r -a outPathArray <<< "$OUT_PATHS"
                  # FIXME: replace ssh host
                  nix copy --to "ssh-ng://example-nix-cache" "''${outPathArray[*]}" 2>&1 | tee -a /tmp/nix-post-build-hook.log
                '';
              };
            };

            system.stateVersion = "23.11";
          }
        ];
      };
  };
}
