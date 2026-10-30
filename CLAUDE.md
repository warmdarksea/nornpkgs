# nornpkgs, for Claude

NixOS configuration for a handful of hosts plus some terraform, driven by
GNU make. README.md has the layout: `sys/<host>` per-host config, `hw/`
hardware modules, `lib/` role modules (`base`, `desktop`, `server`) and
helpers, `home/` home-manager modules, `pkgs/` local packages, `template/`
flake templates. `flake.nix` wires it together; the `nixosConfigurations`
and `nixosModules` attribute sets near the bottom are the map.

## verifying a change

Everything is evaluated through the flake. The `gensokyo-private` input is
a private repository you cannot fetch; CI and you substitute its public
`ci` branch, which turns on `gensokyo.ci` (no CUDA, no large packages, no
dev docs). Always pass these flags:

```sh
nix build -L --no-link --impure --no-write-lock-file \
  --override-input gensokyo-private github:warmdarksea/gensokyo-private/ci \
  '.#nixosConfigurations.base.config.system.build.toplevel'
```

* `base` is small and almost entirely cache hits: build it for any change
  under `lib/base.nix`, `lib/ci.nix`, or the flake itself.
* For a change to one host, evaluate that host instead of building it:
  `nix eval --impure ... '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'`
  with the same override flags. Desktop closures are tens of gigabytes;
  build them only if the issue is about a build failure.
* For a package under `pkgs/`, `nix build .#<name>` if it is exported, or
  evaluate the module that uses it.
* Run `nix flake show` or `nix eval` before guessing attribute names.

`.github/workflows/build.yml` runs the `base` build on every push, so a
pushed branch gets a real CI result; read it with the CI tools before
claiming a fix works.

## rules

* Commit messages: lowercase, `area: what changed`, as in `git log`.
  One change per commit.
* Do not edit `flake.lock` unless the task is to bump an input. Do not touch
  `secret/`, `Makefile.private`, or anything under `sys/*/hardware-configuration.nix`.
* Do not add binary caches, trusted keys, or CI secrets. Do not loosen
  `permissions:` in any workflow.
* Hosts are deployed by the owner with `make deploy_*`; nothing in CI deploys.
* Prefer the existing conventions over introducing new helpers: look at a
  sibling host or module first.
