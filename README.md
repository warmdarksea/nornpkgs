# nornpkgs

repository for managing my digital life. mostly nix, some terraform/cloudflare stuff, orchestrated with gmake. partially written by claude because that's the only way to make working with nix bearable

* `flake.nix` — self-explanatory
  littledevil image builds under `packages.<arch>`
* `hw/` — per-machine hardware modules (kernel modules, firmware, gpu)
* `sys/<host>/` — the generic system: roles, services, users, and the
  arch when it is not x86_64 (`nixpkgs.hostPlatform`); no disks,
  bootloader or hostname. `nixosModules.gensokyo.systems.<host>`, and
  what boots in the VM tests
* `inst/<host>.gensokyo.internal/` — the instance: hostname, hostId,
  filesystems, LUKS, bootloader, pool-specific paths. together with the
  hardware and the private module it is `nixosConfigurations.<host>`,
  the thing that gets deployed
* `lib/` — `base`, `desktop`, `server` role modules, the
  `gensokyo.disks` option, `models.nix` behind
  `lib.fetchModel` / `lib.fetchHuggingFace`, and `jupyter.nix`
  behind `lib.mkJupyter`
* `home/` — home-manager modules
* `template/` — flake templates (`nix flake init -t
  github:warmdarksea/nornpkgs#rust-hello`)
* `Makefile` — build/deploy driver (`Makefile.littledevil` for the
  cloud targets)

## sandboxed jupyter

`lib.mkJupyter` builds a notebook env, its kernels and a rootless podman
wrapper to run them in. A notebook cell is arbitrary code execution by
design, so the server does not get the host: the project directory is the
only writable mount, `/nix/store` is read-only, and jupyter's state lives
under the project's own `state/`.

```nix
inputs.nornpkgs.url = "github:warmdarksea/nornpkgs";

jupyter = nornpkgs.lib.mkJupyter {
  inherit pkgs;
  name = "py-hellotorch";
  kernels.python = {
    displayName = "Python 3 (torch)";
    packages = ps: [ ps.torch-bin py-hellotorch ];  # importable in a cell
    cuda = true;                                    # gpu into the sandbox
  };
  port = 8889;
};
```

Presets are `python` (ipykernel, with the jupyterlab debugger wired up),
`rust` (evcxr) and `bash`. The default jupyterlab extension list — jupytext,
lsp, git, execute-time, code-formatter, vim, widgets — is at the top of
`lib/jupyter.nix`; `extensions` replaces it and `extraExtensions` appends.

```sh
make start_jupyter          # or: jupyter-sandbox start
make stop_jupyter
jupyter-sandbox status | logs | shell | print-cmd
```

Needs rootless podman on the host (`virtualisation.podman.enable`, subuid
ranges, `/dev/net/tun`), so it runs from the host rather than from inside
another sandbox.

## declarative models

huggingface/git lfs repos as fixed-output sparse lfs checkouts, with gguf
conversion and quantization as attributes:

```nix
inputs.nornpkgs.url = "github:warmdarksea/nornpkgs";

outputs = { self, nixpkgs, nornpkgs }: let
  pkgs = nixpkgs.legacyPackages.x86_64-linux;
  smol = nornpkgs.lib.fetchHuggingFace {
    inherit pkgs;
    src   = "hf:HuggingFaceTB/SmolLM2-135M";
    files = [ "model.safetensors" "*.json" "merges.txt" ];
    hash  = "sha256-6SdTEqhygLUI8LrLp+ClmkT1TkUZTbMmGGcPgX9svs8=";
  };
in {
  packages.x86_64-linux.default = smol.gguf;              # f16
  packages.x86_64-linux.small   = smol.gguf.quant.q4_k_m;
  packages.x86_64-linux.hf      = smol.safetensors;
}
```

test:

```sh
nix flake init -t github:warmdarksea/nornpkgs#llm-hello
make test   # serve, ask one thing, shut down. no gpu, no systemd
make run    # systemd-run --user --unit=llm-hello --collect -- llama-server
make ask PROMPT='the capital of france is'
make logs ; make stop
make copy HOST=hell   # just the closure
make remote HOST=hell # the closure, then the oneshot over ssh
```

## testing

```sh
make test               # all of the below
make test_nix_lint      # parse every .nix file
make test_tf            # tofu validate, no credentials
make test_nix_check     # every flake output to a .drv (nix flake check --no-build)
make test_vm            # boot every generic system in a VM; VM_TARGETS="base hell" for some
make test_templates     # copy, build, run and test the templates; TEMPLATES= for the heavy ones
make run_vm TARGET=hell # the same VM, interactively
make plan_oci_live      # tofu plan against the real state (authenticated, not a test)
make ci_<target>        # any of them against the public inputs + gensokyo-private's ci branch
```

The VM tests are `checks.<system>.boot-<host>`: the generic system
plus the NixOS test framework's qemu machinery, waited for until its
default target, failed units logged. A check under `checks.<system>` runs
on a host of that system, littledevil (aarch64) on an arm64 runner. They
need kvm. `.github/workflows/test.yml`
runs the cheap subset on every push (x86_64 and an arm64 runner) and boots
any one system on dispatch. eientei is i686 and has no VM test.
