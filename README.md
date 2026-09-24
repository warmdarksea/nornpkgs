# nornpkgs

repository for managing my digital life. mostly nix, some terraform/cloudflare stuff, orchestrated with gmake. partially written by claude because that's the only way to make working with nix bearable

* `flake.nix` — self-explanatory
  littledevil image builds under `packages.<arch>`
* `hw/` — per-machine hardware modules
* `sys/` — per-host system config
* `lib/` — `base`, `desktop`, `server` role modules, the
  `gensokyo.disks` option, and `models.nix` behind
  `lib.fetchModel` / `lib.fetchHuggingFace`
* `home/` — home-manager modules
* `template/` — flake templates (`nix flake init -t
  github:warmdarksea/nornpkgs#rust-hello`)
* `Makefile` — build/deploy driver (`Makefile.littledevil` for the
  cloud targets)

## models

huggingface repos as fixed-output sparse lfs checkouts, with gguf
conversion and quantization hanging off them. bring your own pkgs:

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

start with `hash = pkgs.lib.fakeHash` and paste what nix reports.
`files` are gitignore-style globs (omit for the whole repo); lfs
honours them, so excluded weights are never transferred. pin a
revision with `hf:org/repo@<rev>`; `lib.fetchModel` is the same thing
against an arbitrary git url. a built `.gguf` has no reference to its
checkout, so `nix run .#gc-model-sources -- --dry-run <installable>`
finds the multi-gb sources nothing needs any more.

serving one — a gguf read straight out of the store, under a transient
`systemd --user` unit (`--collect`, so no unit outlives it). no unit
file, no nixos module, and `nix copy` of the closure is the whole
deployment because the weights are in it:

```sh
nix flake init -t github:warmdarksea/nornpkgs#hello-llm
make test   # serve, ask one thing, shut down. no gpu, no systemd
make run    # systemd-run --user --unit=hello-llm --collect -- llama-server
make ask PROMPT='the capital of france is'
make logs ; make stop
make copy HOST=hell
```

ships smollm2-135m so it builds in a minute; the flake carries a
commented swap to qwen2.5-7b f16 on a cuda llama.cpp.
