.PHONY: netboot
netboot:
	nix build --extra-experimental-features nix-command --extra-experimental-features flakes --out-link ./netboot .#hydraJobs.netboot

.PHONY: toplevel
toplevel:
	nix copy --extra-experimental-features nix-command --extra-experimental-features flakes --no-check-sigs --to ssh-ng://nixstore .#hydraJobs.toplevel

.PHONY: nspawn
nspawn:
	nix build --extra-experimental-features nix-command --extra-experimental-features flakes --out-link ./nspawn .#hydraJobs.nspawn

.PHONY: run-srv
run-srv:
	systemd-run --unit=caat-ci-nbd-server --same-dir nix run --extra-experimental-features nix-command --extra-experimental-features flakes .#hydraJobs.nbd-server

.PHONY: restart-nbd
restart-nbd: netboot
	systemctl restart caat-ci-nbd-server
	journalctl -fu caat-ci-nbd-server
