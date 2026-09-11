# nornpkgs

nix flake for the systems of `*.gensokyo.internal` (and the littledevil
cloud infrastructure). formerly known as gensokyo-infra.

* `flake.nix` — one `nixosConfigurations.<host>` per machine, plus the
  littledevil image builds under `packages.<arch>`
* `hw/` — per-machine hardware modules (cpu/gpu/initrd/microcode)
* `sys/` — per-host system config; filesystems & bootloaders live here
* `lib/` — `base`, `desktop`, `server` role modules & the
  `gensokyo.disks` option
* `home/` — home-manager modules
* `template/` — flake templates (`nix flake init -t
  github:warmdarksea/nornpkgs#rust-hello`)
* `Makefile` — build/deploy driver (`Makefile.littledevil` for the
  cloud targets)

identifiers i consider private (disk uuids, vpn endpoints, host ids,
public keys) live in the
[gensokyo-private](https://github.com/warmdarksea/gensokyo-private)
flake input: the github branch is an empty stub that lets everything
here evaluate & build; the real values only exist on the private branch
on my machines. override the input to build with them:

    make build_sys_closure TARGET=hell \
      PRIVATE_FLAKE='git+file:///path/to/gensokyo-private?ref=private'
