# nornpkgs, for Claude

NixOS configuration for a handful of hosts plus some terraform, driven by
GNU make. README.md has the layout. Each host is three layers:
`hw/<machine>.nix` (the box: kernel modules, firmware, gpu),
`sys/<host>/default.nix` (the generic system: roles, services, users; no
disks, bootloader or hostname) and `inst/<host>.gensokyo.internal/default.nix`
(the instance: hostname, hostId, filesystems, LUKS, bootloader, pool-specific
paths). `lib/` holds the role modules (`base`, `desktop`, `server`) and
helpers, `home/` home-manager modules, `pkgs/` local packages, `template/`
flake templates. `flake.nix` wires it together: `nixosModules.gensokyo.systems.<host>`
is the generic system, `nixosConfigurations.<host>` the instance built on it,
`checks.<system>.boot-<host>` the generic system booted as a test VM on a host
of that system (a system's own arch, when not x86_64, is
`nixpkgs.hostPlatform` in its `sys/`).

## verifying a change

Everything is evaluated through the flake. The `gensokyo-private` input is
a private repository you cannot fetch; CI substitutes its public `ci`
branch, which turns on `gensokyo.ci` (no CUDA, no large packages, no dev
docs). Two Makefile targets do that for you, and they are the only way that
works in your sandbox: it masks `.git/config`, which makes nix's libgit2
unable to open the checkout, so `nix build .#...` fails with "could not find
repository" no matter what. The targets build from a git-free copy instead.

```sh
make ci_check TARGET=base      # build the toplevel
make ci_eval  TARGET=<host>    # evaluate only
make ci_test_nix_check         # evaluate every flake output (nix flake check --no-build)
make ci_test_vm VM_TARGETS=<host>   # boot the generic system in a VM
make test_nix_lint             # parse every .nix file, no nix evaluation
```

* `base` is small and almost entirely cache hits: `ci_check` it for any
  change under `lib/base.nix`, `lib/ci.nix`, or the flake itself.
* For a change to one host, `ci_eval` that host. Desktop closures are tens
  of gigabytes; `ci_check` them only if the issue is about a build failure.
* For a package under `pkgs/`, `nix build "path:$PWD/build/ci-tree#<name>"`
  after `make ci_tree`, if it is exported; otherwise evaluate the module
  that uses it.
* `nix flake show "path:$PWD/build/ci-tree"` before guessing attribute names.
* `make ci_<target>` runs any Makefile target against that copy; the test
  targets are listed at the top of the Makefile's testing section. The VM
  tests need kvm (`/dev/kvm` is available in this sandbox).

`.github/workflows/test.yml` runs `make test`'s targets, a step each, on a runner of each arch on
every push (syntax, terraform, evaluation, then the VMs and templates of the
Makefile's NIX_HOSTS_<arch> and NIX_TEMPLATES_<arch>), so a pushed branch
gets real CI results; read them with the CI tools before claiming a fix
works. Any Makefile target runs against the ci copy on dispatch:
`gh workflow run test.yml -f make='check TARGET=hell'` (`-f arch=aarch64` for
the arm64 runner).

## rules

* Commit messages: lowercase, `area: what changed`, as in `git log`.
  One change per commit.
* Do not edit `flake.lock` unless the task is to bump an input. Do not touch
  `secret/`, `Makefile.private`, or the filesystem, LUKS and bootloader
  settings under `inst/*/default.nix` (they describe real disks).
* Do not add binary caches, trusted keys, or CI secrets. Do not loosen
  `permissions:` in any workflow.
* Hosts are deployed by the owner with `make deploy_*`; nothing in CI deploys.
* Prefer the existing conventions over introducing new helpers: look at a
  sibling host or module first.

## committing

Two contexts, two sets of rules. Tell them apart by `CLAUDE_CODE_ACTION`,
which the GitHub action sets to `1` in your environment.

### interactive session with the owner

Author and commit as `Claude <claude@anthropic.com>`, please. Thank you.

### GitHub Actions run (an @claude mention)

* Push the branch with the action's push wrapper after every commit, not
  once at the end.
* Do not end your turn while your checklist still has items you can do.
  There is nobody to tell you to continue; the run ends with your last
  message. Run 41239936199 stopped in the middle of stage 2 with three
  commits unpushed and the comment still saying "in progress".
* If you do have to stop early, commit whatever is consistent, push it, and
  update the comment with exactly what is left; a later mention can
  continue from the branch.
* On an issue every run starts a new branch from `master` and cannot reach
  an earlier run's branch. On a pull request you are checked out on the
  PR's branch with its history: continue from it, do not redo it.
* You cannot change anything under `.github/workflows` from a run: the
  action's app token is not allowed to push workflow changes. Say so and
  leave that part to the owner instead of attempting it.
* Evaluate all hosts in one shell loop that writes results to a file, not
  one command per host; each command is a turn.
* The Bash tool kills a command at ten minutes unless the call asks for
  longer, with `timeout` in milliseconds, up to an hour. Building a host's
  toplevel (`make ci_check`) needs that; evaluating a desktop host can
  take several minutes, so give those room too.
* When the `NIX_GHA_CACHE` repository variable is on, nix in the run reads
  and writes the GitHub Actions cache, so a rebuild of something an earlier
  run built is cheap. The variable is off when the cache step is missing
  from the job log.
