# HuggingFace (and any git) model repos as fixed-output checkouts in the store,
# with gguf conversion and quantization hung off the result as passthru
# attributes.
#
# Not a NixOS module, despite living in lib/ -- flake.nix wires the two entry
# points into lib.fetchModel / lib.fetchHuggingFace, which take the *caller's*
# pkgs so the flake output needs no per-system plumbing.
#
#   fetchHuggingFace { src = "hf:org/repo[@rev]"; hash = "sha256-..."; }
#     .                    the checkout itself
#     .gguf                f16 conversion     .gguf.convert  { outtype }
#     .gguf.quant.<type>   quantizations      .gguf.quantize { type, from, imatrix }
#     .safetensors         weights + config + tokenizer subset
#     .prefetch            out-of-sandbox fetcher, for gated repos
#     .modelName           the derived name
pkgs:

let
  inherit (pkgs) lib;

  llamaCpp = pkgs.llama-cpp;

  # nixpkgs ships convert_hf_to_gguf.py in llama-cpp's bin/, but raw:
  # `#!/usr/bin/env python3`, no interpreter and no dependencies, so it cannot
  # be run as installed. Wrap it against the gguf-py vendored in the *same*
  # source tree, so script and library never drift apart.
  convert-hf-to-gguf = pkgs.writeShellApplication {
    name = "convert-hf-to-gguf";
    runtimeInputs = [
      (pkgs.python3.withPackages (ps: [
        ps.numpy
        ps.sentencepiece
        # llama.cpp pins transformers==4.57.6 and nixpkgs is on 5.x, but
        # nixpkgs' transformers_4 is meta.broken (it needs huggingface-hub
        # <1.0 and nixpkgs ships 1.x). 5.x works here because the converter
        # only imports AutoConfig eagerly -- AutoTokenizer is pulled in lazily
        # by the handful of architectures that need a slow-tokenizer fallback.
        # If a model ever trips over that, the traceback says so plainly.
        ps.transformers
        ps.protobuf
        ps.safetensors
        ps.torchWithoutCuda # cpu-only on purpose: conversion never uses a gpu
        ps.tqdm
      ]))
    ];
    text = ''
      export PYTHONPATH=${llamaCpp.src}/gguf-py''${PYTHONPATH:+:$PYTHONPATH}
      exec python3 ${llamaCpp.src}/convert_hf_to_gguf.py "$@"
    '';
  };

  # ----------------------------------------------------------------------
  # fetchModel: git checkout (LFS, optionally sparse) + format passthrus
  # ----------------------------------------------------------------------
  fetchModel =
    { src
    , name
    , hash
    , files ? null       # gitignore-style patterns; null = whole repo
    , rev ? "HEAD"
    , prefetchUrl ? src  # url printed for out-of-sandbox fetching
    }:
    let
      srcName = "${name}-source";
      # enumerated as .gguf.quant.<lowercased>
      ggufTypes = [
        "Q2_K" "Q3_K_S" "Q3_K_M" "Q3_K_L"
        "Q4_0" "Q4_1" "Q4_K_S" "Q4_K_M"
        "Q5_0" "Q5_1" "Q5_K_S" "Q5_K_M"
        "Q6_K" "Q8_0" "F16" "BF16"
      ];
      sparse = if files == null then [ ] else map (f: "/${f}") files;

      prefetchCmd = ''
        nix-prefetch-git --builder \
          --url ${lib.escapeShellArg prefetchUrl} \
          --rev ${lib.escapeShellArg rev} \
          --fetch-lfs \
          ${lib.optionalString (files != null)
            "--sparse-checkout ${lib.escapeShellArg (lib.concatStringsSep "\n" sparse)} --non-cone-mode"} \
          --out ./${srcName}
        nix store add --mode nar --name ${srcName} ./${srcName}
      '';

      prefetch = pkgs.writeShellApplication {
        name = "prefetch-${name}";
        # NB: deliberately not pkgs.nix -- `nix store add` needs nix >= 2.26 and
        # the pin is not guaranteed to be that new. Use the caller's nix.
        runtimeInputs = [ pkgs.nix-prefetch-git pkgs.git-lfs ];
        text = ''
          set -x
          ${prefetchCmd}
          { set +x; } 2>/dev/null
          # For a gated repo the prefetch is the only way to learn the hash, so
          # print the real one -- `hash` itself is often still a placeholder at
          # this point.
          echo >&2 "declared hash: ${hash}"
          echo >&2 "actual hash:   $(nix hash path --mode nar ./${srcName})"
        '';
      };

      checkout =
        (pkgs.fetchgit {
          name = srcName;
          url = src;
          inherit rev hash;
          fetchLFS = true;
          sparseCheckout = sparse;
          # `files` are gitignore-style globs; cone mode cannot express those
          # (and always keeps every root-level file, which for a flat HF repo
          # means the whole thing).
          nonConeMode = files != null;
        }).overrideAttrs {
          modelSource = "1"; # marker for gc-model-sources

          # stdenv traps EXIT and runs this on any non-zero status. Doing it
          # here rather than by wrapping fetchgit's `builder` is not a style
          # choice: fetchgit is __structuredAttrs and nixpkgs *sources* a
          # custom builder into the stdenv shell (stdenv/generic/source-stdenv.sh),
          # so re-running the original in a child bash loses $stdenv/setup and
          # every fetch dies on builder.sh's `runHook preFetch` instead.
          #
          # Quoted heredoc delimiter: an unquoted one eats the backslash-
          # newlines out of prefetchCmd and would expand any $ in it. $out is
          # printed separately, afterwards.
          failureHook = ''
            cat >&2 <<'EOF'

            ${src} did not fetch (gated repo? no credentials in the sandbox?).
            Fetch it outside the sandbox with:

            ${prefetchCmd}
            The store path below is only what prefetch produces once the
            declared hash matches the real content; if it is still a
            placeholder, paste the "actual hash" prefetch prints.
            EOF
            echo >&2 "and rebuild. The store path will match: $out"
          '';
        };

      # ---- gguf ----------------------------------------------------------
      toGguf = { outtype ? "f16" }:
        pkgs.stdenvNoCC.mkDerivation {
          name = "${name}-${outtype}.gguf";
          src = checkout;
          nativeBuildInputs = [ convert-hf-to-gguf ];
          # don't cp -r gigabytes into the build dir; read $src in place
          dontUnpack = true;
          buildPhase = ''
            # convert-hf-to-gguf derives general.name/general.finetune from the
            # model directory's basename. Pointed straight at $src that bakes
            # the store hash into the gguf metadata, which makes the gguf
            # *reference* the checkout -- pinning it forever and defeating
            # gc-model-sources. Hand it a cleanly named symlink.
            ln -s "$src" "${name}"
            convert-hf-to-gguf \
              --model-name ${lib.escapeShellArg name} \
              --outtype ${outtype} --outfile "$out" "${name}"
          '';
          dontInstall = true;
          dontFixup = true; # no strip/patchelf pass over a multi-GB blob
        };

      ggufF16 = toGguf { };

      quantizeGguf = { type, from ? ggufF16, imatrix ? null }:
        pkgs.stdenvNoCC.mkDerivation {
          name = "${name}-${type}.gguf";
          # llama-quantize comes from the caller's pkgs: hand this a stock one,
          # or a cudaSupport=true pkgs rebuilds llama.cpp under nvcc for a job
          # that never touches the gpu.
          nativeBuildInputs = [ llamaCpp ];
          dontUnpack = true;
          buildPhase = ''
            llama-quantize \
              ${lib.optionalString (imatrix != null) "--imatrix ${imatrix}"} \
              ${from} "$out" ${type}
          '';
          dontInstall = true;
          dontFixup = true;
        };

      # ---- safetensors ---------------------------------------------------
      # The HF-loadable subset of the checkout. Nothing here is quantizable --
      # that is what gguf is for.
      toSafetensors =
        { patterns ? [ "*.safetensors" "*.json" "tokenizer*" "*.model" ] }:
        pkgs.runCommand "${name}.safetensors" { } ''
          mkdir -p "$out"
          for f in ${checkout}/*; do
            case "$(basename "$f")" in
              ${lib.concatStringsSep "|" patterns}) ln -s "$f" "$out"/ ;;
            esac
          done
        '';
    in
    lib.extendDerivation true {
      modelName = name;
      # a flake holding a gated model can surface this itself:
      #   apps.x86_64-linux.prefetch = {
      #     type = "app"; program = "${m.prefetch}/bin/${m.prefetch.name}"; };
      inherit prefetch;

      gguf = lib.extendDerivation true {
        convert = toGguf;
        quantize = quantizeGguf;
        quant = lib.listToAttrs (map
          (t: lib.nameValuePair (lib.toLower t) (quantizeGguf { type = t; }))
          ggufTypes);
      } ggufF16;

      safetensors = lib.extendDerivation true {
        convert = toSafetensors;
        quantize = { type ? null, ... }:
          throw ("${name}: safetensors is not a quantizable format; convert to "
            + "gguf first, e.g. .gguf.quant."
            + (if type == null then "q8_0" else lib.toLower type));
        quant = { };
      } (toSafetensors { });
    } checkout;

  # ----------------------------------------------------------------------
  # fetchHuggingFace: "hf:org/repo[@rev]" sugar over fetchModel
  # ----------------------------------------------------------------------
  fetchHuggingFace = { src, hash, files ? null, name ? null }:
    let
      m = builtins.match "hf:([^@]+)(@(.+))?" src;
      repo =
        if m == null then throw "fetchHuggingFace: expected \"hf:org/repo[@rev]\", got \"${src}\""
        else builtins.elemAt m 0;
      rev = let r = builtins.elemAt m 2; in if r == null then "HEAD" else r;
    in
    fetchModel {
      name = if name != null then name
             else lib.toLower (builtins.replaceStrings [ "/" ] [ "-" ] repo);
      src = "https://huggingface.co/${repo}";
      prefetchUrl = "git@hf.co:${repo}";
      inherit rev hash files;
    };

  # ----------------------------------------------------------------------
  # gc-model-sources [--dry-run] INSTALLABLE...
  #
  # A converted gguf has no reference to the checkout it came from, so the
  # multi-GB source is dead weight the moment you have the format you wanted.
  # ----------------------------------------------------------------------
  gc-model-sources = pkgs.writeShellApplication {
    name = "gc-model-sources";
    runtimeInputs = [ pkgs.jq pkgs.nix ];
    text = ''
      dry=
      if [ "''${1:-}" = --dry-run ]; then dry=1; shift; fi

      for target in "$@"; do
        nix derivation show -r "$target" \
          | jq -r '(.derivations // .) | to_entries[]
                   # structuredAttrs (nixpkgs-unstable) moves the marker out of
                   # env; plain stdenv keeps it there.
                   | select((.value.env.modelSource
                             // .value.structuredAttrs.modelSource) == "1")
                   # nix < 2.30 puts the path in outputs.out.path; newer nix
                   # omits it for fixed-output drvs.
                   | (.value.outputs.out.path // .value.env.out)'
      done | sort -u | while read -r p; do
        [ -e "$p" ] || continue
        size=$(nix path-info -S "$p" | awk '{print $2}')
        echo "$p ($size bytes)"
        [ -n "$dry" ] && continue
        if ! nix store delete "$p"; then
          echo "  still rooted by:" >&2
          nix-store --query --roots "$p" >&2
        fi
      done
    '';
  };
in
{
  inherit fetchModel fetchHuggingFace gc-model-sources;
}
