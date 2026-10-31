# nornpkgs, for Claude

NixOS configuration for a handful of hosts plus some terraform, driven by
GNU make. README.md has the layout: `sys/<host>` per-host config, `hw/`
hardware modules, `lib/` role modules (`base`, `desktop`, `server`) and
helpers, `home/` home-manager modules, `pkgs/` local packages, `template/`
flake templates. `flake.nix` wires it together; the `nixosConfigurations`
and `nixosModules` attribute sets near the bottom are the map.

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
```

* `base` is small and almost entirely cache hits: `ci_check` it for any
  change under `lib/base.nix`, `lib/ci.nix`, or the flake itself.
* For a change to one host, `ci_eval` that host. Desktop closures are tens
  of gigabytes; `ci_check` them only if the issue is about a build failure.
* For a package under `pkgs/`, `nix build "path:$PWD/build/ci-tree#<name>"`
  after `make ci_tree`, if it is exported; otherwise evaluate the module
  that uses it.
* `nix flake show "path:$PWD/build/ci-tree"` before guessing attribute names.

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

## committing

Two contexts, two sets of rules. Tell them apart by `CLAUDE_CODE_ACTION`,
which the GitHub action sets to `1` in your environment.

### interactive session with the owner

Commit to `master` directly, authored and committed as
`Claude <claude@anthropic.com>`:

```sh
git -c user.name=Claude -c user.email=claude@anthropic.com commit ...
```

Do not push; the owner fetches, reviews, and pushes. This checkout's
`master` is usually ahead of `github/master`, and the GitHub mirror has
merge commits of its own, so do not try to fast-forward or rebase it
yourself.

### GitHub Actions run (an @claude mention)

The owner is not watching, and the runner is destroyed the moment the run
ends, so only pushed commits survive. Two runs on issue #16 lost all their
work this way.

* Push the branch with the action's push wrapper after every commit, not
  once at the end.
* Never end a run with uncommitted or unpushed work. If you have to stop
  early, commit whatever is consistent, push it, and say in your comment
  exactly what is left; a later mention can continue from the branch.
* You cannot change anything under `.github/workflows` from a run: the
  action's app token is not allowed to push workflow changes. Say so and
  leave that part to the owner instead of attempting it.
* If the tool allowlist denies a command, say so in your comment rather
  than trying variants; the owner can widen `--allowedTools`.
* Evaluate all hosts in one shell loop that writes results to a file, not
  one command per host; each command is a turn. A single evaluation of a
  desktop host can exceed the Bash tool's default two-minute timeout, so
  pass a longer `timeout` for those.
* `cheese` and `dusk` fail to evaluate on `master` as of 2026-10-31
  (conflicting `console.font` definitions). Do not spend turns on them
  unless the task is to fix that.
