# nornpkgs, for Claude

NixOS configuration for a handful of hosts plus some terraform, driven by
GNU make. README.md has the layout. Each host is three layers:
`hw/<machine>.nix` (the box), `sys/<host>/default.nix` (the generic
system: roles, services, users) and `inst/<host>.gensokyo.internal/default.nix`
(the instance: hostname, disks, bootloader). `lib/` holds the role modules
and helpers, `home/` home-manager modules, `pkgs/` local packages,
`template/` flake templates. `flake.nix` wires it together:
`nixosModules.gensokyo.systems.<host>` is the generic system,
`nixosConfigurations.<host>` the instance built on it,
`checks.<system>.boot-<host>` the generic system booted as a test VM.

## verifying a change

The `gensokyo-private` input is a private repository you cannot fetch; CI
substitutes its public `ci` branch, which turns on `gensokyo.ci` (no CUDA,
no large packages). The `ci_*` Makefile targets do that for you, from a
git-free copy of the tree, and they are the only way that works in your
sandbox (`nix build .#...` fails with "could not find repository").

```sh
make ci_check TARGET=base      # build the toplevel (small, cached)
make ci_eval  TARGET=<host>    # evaluate only
make ci_test_nix_check         # nix flake check --no-build, every output
make ci_test_vm VM_TARGETS=<host>   # boot the generic system in a VM (kvm)
make test_nix_lint             # parse every .nix file
make ci_<target>               # any Makefile target against the copy
```

`ci_eval` the host you changed; `ci_check` only base, desktop closures are
tens of gigabytes. `nix flake show "path:$PWD/build/ci-tree"` after
`make ci_tree` before guessing attribute names. `.github/workflows/test.yml`
runs `make test` on a runner of each arch on every push; read the results
with the CI tools before claiming a fix works.

## rules

* Commit messages: lowercase, `area: what changed`, as in `git log`. One
  change per commit.
* `flake.lock` changes only by `make bump`.
* Do not add binary caches, trusted keys or CI secrets, do not loosen
  `permissions:` in any workflow, do not touch `secret/`.
* Nothing in CI deploys; the owner deploys with `make deploy_*`.

## committing

Interactive session with the owner: author and commit as
`Claude <claude@anthropic.com>`.

GitHub Actions run (`CLAUDE_CODE_ACTION=1`): push with the action's push
wrapper after every commit, not once at the end. The run ends with your
last message, so do not stop while your checklist has items you can do;
if you must stop early, push what is consistent and say what is left. On
a pull request you are on its branch with its history: continue, do not
redo. The action's token cannot push `.github/workflows` changes; leave
those to the owner. Evaluate all hosts in one shell loop writing to a
file, not a command per host. The Bash tool's default limit is ten
minutes; ask for longer (`timeout`, up to an hour) for builds and desktop
evaluations.
