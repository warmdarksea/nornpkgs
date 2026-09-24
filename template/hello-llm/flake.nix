{
  description = "llama-server on a gguf read straight out of the nix store";

  # Resolves through the system nix registry pin.
  inputs.nixpkgs.url = "nixpkgs";

  # The model fetchers. When hacking on them locally:
  #   make build NORNPKGS=path:/home/clownpiece/src/nornpkgs
  inputs.nornpkgs.url = "github:warmdarksea/nornpkgs";
  inputs.nornpkgs.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { self, nixpkgs, nornpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # 135M, ~270 MB as f16: builds in a minute and serves fine on a cpu.
      # `files` are gitignore-style globs and lfs honours them, so an upstream
      # README edit can neither move the hash nor cross the wire.
      model = nornpkgs.lib.fetchHuggingFace {
        inherit pkgs;
        src = "hf:HuggingFaceTB/SmolLM2-135M";
        files = [ "model.safetensors" "*.json" "merges.txt" ];
        hash = "sha256-6SdTEqhygLUI8LrLp+ClmkT1TkUZTbMmGGcPgX9svs8=";
      };
      llamaCpp = pkgs.llama-cpp;

      # something worth the electricity, if you have ~16 GB of vram. pin the
      # rev -- "HEAD" is not reproducible, and a moved upstream then shows up
      # as a bare hash mismatch instead of anything legible:
      #
      #   model = nornpkgs.lib.fetchHuggingFace {
      #     inherit pkgs;
      #     src = "hf:Qwen/Qwen2.5-7B@d149729398750b98c0af14eb82c78cfe92750796";
      #     files = [ "*.safetensors" "*.json" "merges.txt" ];
      #     hash = pkgs.lib.fakeHash;  # tofu: build once, paste what nix reports
      #   };                           # 15.2 GB checkout, and the f16 is another 15.2
      #
      #   llamaCpp = (import nixpkgs {
      #     inherit system;
      #     config = {
      #       allowUnfree = true;
      #       cudaSupport = true;
      #       cudaCapabilities = [ "8.6" "8.9" ];  # rtx 3090, rtx 4070
      #       cudaForwardCompat = false;           # skip ptx for future archs
      #     };
      #   }).llama-cpp;
      #
      # note that only llama.cpp comes from the cuda package set. conversion
      # and quantization are torch-on-cpu jobs that never touch a gpu, and
      # building *those* under cudaSupport throws away every cache hit.

      gguf = model.gguf; # f16, unquantized; .gguf.quant.q4_k_m etc. also exist
      alias = model.modelName;

      hello-llm = pkgs.writeShellApplication {
        name = "hello-llm";
        # deliberately not pkgs.systemd: the systemd that supervises this is
        # the one already running the caller's session, and a second copy in
        # the closure is pure `nix copy` weight. writeShellApplication only
        # prepends to PATH, so the host's systemctl/journalctl stay reachable.
        runtimeInputs = [ pkgs.curl pkgs.jq ];
        text = ''
          unit=hello-llm
          host=''${HELLO_LLM_HOST:-127.0.0.1}
          port=''${HELLO_LLM_PORT:-8080}
          ctx=''${HELLO_LLM_CTX:-4096}
          # layers on the gpu. 999 = all of them; lower it when vram is tight
          # (an f16 7B is ~15 GB, so an 8 GB card wants something like NGL=12).
          # ignored by a llama.cpp built without gpu support.
          ngl=''${HELLO_LLM_NGL:-999}
          api="http://$host:$port"

          # store paths, interpolated: this is what puts the weights in the
          # script's runtime closure, and what keeps the model path valid on
          # the far side of a `nix copy`.
          server=(
            ${llamaCpp}/bin/llama-server
            --model ${gguf}
            --alias ${alias}
            --host "$host" --port "$port"
            --ctx-size "$ctx"
            --n-gpu-layers "$ngl"
          )

          # --collect is the point of the exercise: the unit is transient, so
          # it is gone the moment it stops -- including when it fails. no unit
          # file is written anywhere, and nothing accumulates in your systemd.
          run=(
            systemd-run --user
            --unit="$unit"
            --collect
            --service-type=exec
            --description="llama-server: ${alias}"
          )

          need_systemd() {
            if ! command -v systemd-run >/dev/null 2>&1 \
               || ! systemctl --user show --property=Version >/dev/null 2>&1; then
              echo "$unit: no user systemd here (no --user manager, or no dbus)." >&2
              echo "  headless box?  loginctl enable-linger \"\$USER\"" >&2
              echo "  or skip systemd entirely:  $0 foreground" >&2
              exit 1
            fi
          }

          wait_ready() {
            for _ in $(seq 1 "''${HELLO_LLM_TIMEOUT:-600}"); do
              curl -fsS "$api/health" >/dev/null 2>&1 && return 0
              sleep 1
            done
            echo "$unit: nothing on $api/health after ''${HELLO_LLM_TIMEOUT:-600}s" >&2
            return 1
          }

          # /completion, not /v1/chat/completions: smollm2-135m is a base model
          # with no chat template. swap in an -Instruct model and add --jinja
          # to the server argv if you want the chat endpoint.
          ask() {
            curl -fsS "$api/completion" -H 'content-type: application/json' \
              --data "$(jq -n --arg p "$1" --argjson n "''${HELLO_LLM_N:-64}" \
                          '{prompt: $p, n_predict: $n, temperature: 0.2}')" \
              | jq -r '.content'
          }

          case "''${1:-start}" in
            start)
              need_systemd
              if systemctl --user is-active --quiet "$unit"; then
                echo "$unit is already up at $api"; exit 0
              fi
              "''${run[@]}" -- "''${server[@]}"
              wait_ready || { journalctl --user -u "$unit" -n 40 --no-pager >&2; exit 1; }
              echo "$unit ready at $api  (web ui: $api/)"
              echo "  $0 ask 'the capital of france is' | $0 logs | $0 status | $0 stop"
              ;;
            stop)
              need_systemd
              systemctl --user stop "$unit"
              # a transient unit that *failed* lingers until it is reset
              systemctl --user reset-failed "$unit" 2>/dev/null || true
              ;;
            logs)   need_systemd; journalctl --user -u "$unit" -n 100 -f ;;
            status) need_systemd; systemctl --user status --no-pager "$unit" ;;
            ask)    shift; ask "$*" ;;
            # the same argv, without systemd. this is what works in a
            # container, a build sandbox, or over a bare ssh connection.
            foreground) exec "''${server[@]}" ;;
            # what `start` would run, without running it.
            print-cmd) printf '%q ' "''${run[@]}" -- "''${server[@]}"; echo ;;
            # serve (no systemd), wait for /health, ask one thing, shut down.
            selftest)
              shift
              log="''${TMPDIR:-/tmp}/$unit.log"
              "''${server[@]}" >"$log" 2>&1 &
              pid=$!
              trap 'kill "$pid" 2>/dev/null || true' EXIT
              wait_ready || { tail -40 "$log" >&2; exit 1; }
              ask "''${1:-The capital of France is}"
              ;;
            *)
              echo "usage: $0 {start|stop|logs|status|ask TEXT|foreground|print-cmd|selftest}" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      packages.${system} = {
        default = hello-llm;
        inherit hello-llm;
        gguf = gguf;      # nix build .#gguf -> the bare model store path
        checkout = model; # the hf tree, for gc-model-sources
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${hello-llm}/bin/hello-llm";
        };
        # gated repo, or a sandbox with no hf credentials: run this outside
        # the sandbox and the build becomes a no-op. also the cheapest way to
        # learn the hash while `hash` is still lib.fakeHash.
        prefetch = {
          type = "app";
          program = "${model.prefetch}/bin/${model.prefetch.name}";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ llamaCpp pkgs.curl pkgs.jq ];
      };
    };
}
