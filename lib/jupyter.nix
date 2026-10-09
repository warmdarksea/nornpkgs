# Sandboxed jupyter servers: a notebook env, a kernel set, and a rootless
# podman wrapper to run them in.
#
# Not a NixOS module, despite living in lib/ -- flake.nix wires the entry
# point into lib.mkJupyter, which takes the *caller's* pkgs so the flake
# output needs no per-system plumbing. Same shape as lib/models.nix.
#
#   mkJupyter { name = "py-hello"; kernels.python = { }; }
#     -> a package whose bin/jupyter-sandbox takes
#        start | stop | status | logs | shell | print-cmd
#
# The server always runs inside a container. A notebook cell is arbitrary
# code execution by design -- that is the whole point of a notebook -- so the
# thing evaluating them does not get the host. The project directory is the
# only writable bind mount, /nix/store is read-only, and everything mutable
# (jupyter's data/runtime/config, cargo's caches, $HOME) lands under the
# project's own state dir rather than anywhere real.
#
# Containerising also retires the pidfile: podman tracks the server by name,
# so `stop` is `podman stop` and there is no process state to guess at.
#
# Rootless, and the container runs as uid 0, which podman maps to the
# invoking user -- so notebooks written into the project are owned by you,
# not by root. The isolation boundary is the container, not the in-container
# uid; unlike lib/agent.nix there is no second identity to keep away from
# your files, because this server is working on your checkout on purpose.
#
# The wrapper carries its own podman, but rootless podman still needs the
# host set up for it: virtualisation.podman.enable, subuid/subgid ranges for
# the user, and /dev/net/tun for the default network mode. That means this
# runs from the host, not from inside another sandbox -- see the note on
# JUPYTER_SANDBOX_NETWORK below.
pkgs:

let
  inherit (pkgs) lib;
  python = pkgs.python3;

  # ---- extensions --------------------------------------------------------

  # >>> THE DEFAULT EXTENSION LIST <<<  add and remove freely; this is the
  # only place the set is spelled out. Replace it per call with `extensions`,
  # or append to it without restating it with `extraExtensions`.
  #
  # These extend jupyterlab and jupyter-server, so they belong to the
  # notebook env rather than to a kernel env -- they are not what a cell
  # imports. ipywidgets is the exception and appears in both: the
  # labextension draws the widgets, the kernel constructs them.
  #
  # Everything here auto-enables. Each package ships an
  # etc/jupyter/jupyter_server_config.d/*.json which the env merges, so there
  # is no `jupyter server extension enable` step to remember.
  defaultExtensions =
    ps: with ps; [
      jupytext # notebooks paired with .py/.md on save
      jupyterlab-lsp # completion, diagnostics, jump-to-definition
      python-lsp-server # ...the language server it drives. jupyter-lsp finds
      # this through importlib, not $PATH, so being in the env is enough
      jupyterlab-git # git panel and notebook diffs (pulls in nbdime)
      jupyterlab-execute-time # per-cell timings in the gutter
      jupyterlab-code-formatter # format/lint on command, vendored below
      ruff # one of its formatters: located through
      # ruff.__main__.find_ruff_bin, so the *python* package is what matters
      # here, not pkgs.ruff
      black # ditto, found by import
      isort # ditto
      ipywidgets # interactive widgets (also in the python kernel env)
      jupyterlab-vim # modal editing
    ];

  # Not in nixpkgs. Vendored from the published wheel, which already carries
  # the built labextension, so this costs no npm and nothing but the one
  # fixed-output fetch. To bump: change version and url, set hash to
  # lib.fakeHash, build once, paste back what nix reports.
  #
  # jupyter-ai is deliberately *not* here. Its runtime closure needs fourteen
  # dists nixpkgs does not carry (jupyter-ai itself, five jupyter-ai-*, four
  # more jupyterlab-*, jupyter-live-content, jupyter-server-mcp, mcp-types,
  # nest-asyncio2). They all publish wheels, so it is tractable the same way
  # this one is, but it is fourteen pins against a pre-1.0 ecosystem rather
  # than one, and it wants doing deliberately rather than in passing.
  jupyterlab-code-formatter = python.pkgs.buildPythonPackage {
    pname = "jupyterlab_code_formatter";
    version = "3.1.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/a1/c0/b57940ad6f217be80bb66f9d942d33d9349ae75cd1b0fe1118bc40cdae25/jupyterlab_code_formatter-3.1.0-py3-none-any.whl";
      hash = "sha256-wdmo47MeE0kygWNsz8GNad69R2SHom079qA967gP37g=";
    };
    dependencies = with python.pkgs; [
      jupyter-server
      packaging
    ];
    doCheck = false;
    pythonImportsCheck = [ "jupyterlab_code_formatter" ];
    meta.description = "Code formatter for JupyterLab (black/isort/ruff)";
  };

  # The vendored package has to be reachable as `ps.jupyterlab-code-formatter`
  # from the list above and from any caller's override, so splice it into the
  # package set those lists are applied to.
  extensionScope = python.pkgs // { inherit jupyterlab-code-formatter; };

  # ---- kernels -----------------------------------------------------------

  # libnvrtc and libcudart come from nix; libcuda comes from the host driver,
  # which on NixOS lives in /run/opengl-driver/lib and is bind-mounted into
  # the sandbox whenever a kernel asks for cuda.
  cudaLdPath = "${
    lib.makeLibraryPath [
      pkgs.cudaPackages.cuda_nvrtc
      pkgs.cudaPackages.cuda_cudart
    ]
  }:/run/opengl-driver/lib";

  # buildPythonApplication leaves `pythonModule` unset, which is how nixpkgs
  # says "this is a program, not an importable library" -- and withPackages
  # drops anything that fails that check (hasPythonModule in
  # python-packages-base.nix), silently. But a template passing its own
  # package to a kernel means "let a cell import this", so promote
  # applications back to modules rather than quietly ignoring them.
  #
  # The failure this avoids is a nasty one: the kernel still starts, and the
  # import still appears to work for as long as the server's cwd happens to
  # be the project root, where the source tree shadows the missing install.
  asModule = p: if p ? pythonModule then p else python.pkgs.toPythonModule p;

  # Each preset takes the per-kernel options the caller passed and returns a
  # kernelspec for pkgs.jupyter-kernel.create.
  presets = {
    # debugpy is what makes `metadata.debugger` true: ipykernel does not
    # depend on it, and without it the kernel reports no debugger and
    # jupyterlab's breakpoints quietly do nothing. The flag is what puts the
    # bug button in the sidebar and lets it break inside a cell.
    python =
      { displayName, packages, ... }:
      let
        env = python.withPackages (
          ps:
          [
            ps.ipykernel
            ps.debugpy
            ps.ipywidgets
          ]
          ++ map asModule (packages ps)
        );
      in
      {
        inherit displayName;
        argv = [
          env.interpreter
          "-m"
          "ipykernel_launcher"
          "-f"
          "{connection_file}"
        ];
        language = "python";
        metadata.debugger = true;
        logo32 = "${env}/${env.sitePackages}/ipykernel/resources/logo-32x32.png";
        logo64 = "${env}/${env.sitePackages}/ipykernel/resources/logo-64x64.png";
      };

    # evcxr rebuilds a scratch crate for every cell, so this kernel carries
    # no project code and ignores `packages`: `:dep` is how a notebook pulls
    # a crate in, and that resolves through cargo against crates.io rather
    # than through the flake.
    #
    # LD_LIBRARY_PATH goes in the kernelspec rather than on the server:
    # cudarc dlopens libcuda and libnvrtc, so it is the kernel process that
    # needs them. Set here, it applies however the server was started.
    #
    # No metadata.debugger: evcxr speaks no DAP, and the flag would only put
    # a debug button in jupyterlab that cannot work.
    #
    # nixpkgs wraps evcxr_jupyter with cargo/rustc/gcc on PATH, which is what
    # it shells out to per cell. That wrapper is also why the kernel logs a
    # harmless "tried to update client, but failed: Read-only file system" at
    # startup: evcxr sees the kernel.json argv is the wrapper rather than the
    # binary it is running as and offers to rewrite it, which the store
    # rightly refuses.
    rust =
      { displayName, cuda, ... }:
      {
        inherit displayName;
        argv = [
          "${pkgs.evcxr}/bin/evcxr_jupyter"
          "--control_file"
          "{connection_file}"
        ];
        language = "rust";
        logo32 = null;
        logo64 = null;
      }
      // lib.optionalAttrs cuda { env.LD_LIBRARY_PATH = cudaLdPath; };

    bash =
      { displayName, ... }:
      let
        env = python.withPackages (ps: [ ps.bash-kernel ]);
      in
      {
        inherit displayName;
        argv = [
          env.interpreter
          "-m"
          "bash_kernel"
          "-f"
          "{connection_file}"
        ];
        language = "bash";
        logo32 = null;
        logo64 = null;
      };
  };

  defaultDisplayNames = {
    python = "Python 3";
    rust = "Rust (evcxr)";
    bash = "Bash";
  };

  # The name a preset's kernelspec is *registered* under, which is not always
  # the preset name. "python" in particular must not be used: jupyter_client's
  # KernelManager has a legacy alias that silently rewrites a kernel_name of
  # "python" to "python3" (manager.py, _kernel_name_changed), so a spec
  # registered as "python" is unreachable -- the server quietly starts
  # ipykernel's own bare-`python` kernel instead, which is a different
  # interpreter with none of the packages asked for here.
  #
  # Registering as "python3" also shadows that stray spec, since JUPYTER_PATH
  # takes precedence over the env's share/jupyter/kernels.
  specNames = {
    python = "python3";
    rust = "rust";
    bash = "bash";
  };
in
{
  # name:       distinguishes this server's container and state from others
  # kernels:    attrset of preset name -> per-kernel options. The preset
  #             names are the keys of `presets` above (python, rust, bash),
  #             and the kernel is registered under that same name. Options,
  #             all optional:
  #               displayName  what the launcher shows
  #               packages     ps: [ ... ], extra python packages for the
  #                            kernel env -- put the project itself here so a
  #                            cell can import it (python preset only)
  #               cuda         bind the gpu into the sandbox, and for the
  #                            rust preset put the cuda libs on its path
  # extensions / extraExtensions: replace or extend the default list
  # port:       published on 127.0.0.1 only
  # stateDir:   where the mutable dirs go, relative to the project
  mkJupyter =
    {
      name,
      kernels,
      extensions ? defaultExtensions,
      extraExtensions ? (ps: [ ]),
      port ? 8888,
      stateDir ? "state",
    }:
    let
      unknown = lib.subtractLists (lib.attrNames presets) (lib.attrNames kernels);

      withDefaults = kernelName: opts: {
        displayName = opts.displayName or defaultDisplayNames.${kernelName};
        packages = opts.packages or (ps: [ ]);
        cuda = opts.cuda or false;
      };

      definitions = lib.mapAttrs' (
        kernelName: opts:
        lib.nameValuePair specNames.${kernelName} (presets.${kernelName} (withDefaults kernelName opts))
      ) kernels;

      # any kernel wanting cuda is enough to want the gpu in the sandbox
      anyCuda = lib.any (o: o.cuda or false) (lib.attrValues kernels);
      # the rust preset shells out to cargo, so give cargo somewhere to write
      anyRust = kernels ? rust;

      kernelsDir = pkgs.jupyter-kernel.create { inherit definitions; };

      # Two things, both reached through JUPYTER_CONFIG_PATH below.
      #
      # jupyter_server_config.py: the notebook env has ipykernel in its
      # closure (jupyterlab depends on it) and ipykernel ships a kernelspec
      # of its own under share/jupyter/kernels. JUPYTER_PATH wins for a
      # kernel of the same name, but anything else in there shows up as an
      # extra, undeclared "Python 3 (ipykernel)" entry whose argv is a bare
      # `python` and which advertises a debugger the env has no debugpy for.
      # So pin the server to the kernels actually declared here.
      #
      # port_retries = 0 because the port is published into the sandbox: if
      # jupyter walked forward to the next free port, the published mapping
      # would point at nothing, so a busy port should fail loudly instead.
      #
      # labconfig/default_setting_overrides.json: jupyterlab ships two
      # settings that otherwise open a dialog on first use -- the extension
      # manager's third-party disclaimer, and "fetch official Jupyter news",
      # which also wants to phone home. Answer both so a fresh checkout comes
      # up ready to use. Note the singular "setting": jupyterlab_server reads
      # `default_setting_overrides`, though the comment above the code that
      # does so says "default_settings_overrides".
      jupyterConfig = pkgs.symlinkJoin {
        name = "jupyter-config-${name}";
        paths = [
          (pkgs.writeTextDir "jupyter_server_config.py" ''
            c.KernelSpecManager.allowed_kernelspecs = ${builtins.toJSON (builtins.attrNames definitions)}
            c.ServerApp.port_retries = 0
          '')
          (pkgs.writeTextDir "labconfig/default_setting_overrides.json" (
            builtins.toJSON {
              "@jupyterlab/extensionmanager-extension:plugin".disclaimed = true;
              "@jupyterlab/apputils-extension:notification" = {
                fetchNews = "false";
                checkForUpdates = false;
              };
            }
          ))
        ];
      };

      # This is what pkgs.jupyter builds, with jupyterlab asked for by name
      # and the extensions added. notebook 7 is built on jupyterlab and so
      # drags it in either way, but pkgs.jupyter only requests notebook --
      # spelling it out makes /lab part of the contract rather than a detail
      # of notebook's dependency list that a future bump could drop. Built
      # directly rather than through pkgs.jupyter.override because that only
      # exposes `definitions`, not the env's package list.
      env =
        (python.buildEnv.override {
          extraLibs = [
            python.pkgs.notebook
            python.pkgs.jupyterlab
          ]
          ++ extensions extensionScope
          ++ extraExtensions extensionScope;
          makeWrapperArgs = [
            "--prefix JUPYTER_PATH : ${kernelsDir}"
            "--prefix JUPYTER_CONFIG_PATH : ${jupyterConfig}"
          ];
        }).overrideAttrs
          (_: {
            meta = python.pkgs.notebook.meta // {
              mainProgram = "jupyter-notebook";
            };
          });

      # A shell and the few tools a notebook terminal is useless without.
      # Deliberately small: the kernels bring their own closures, and this is
      # only what ends up on PATH inside the sandbox.
      sandboxEnv = pkgs.buildEnv {
        name = "jupyter-sandbox-env-${name}";
        paths = with pkgs; [
          bashInteractive
          coreutils
          findutils
          gnused
          gnugrep
          gitMinimal
        ];
      };

      # Real directories at the top level: podman populates /etc before
      # /nix/store is mounted, so nothing above the leaves may be a symlink
      # into the store. fakeNss is what makes uid 0 resolve to a name, which
      # ipython and git both want.
      rootfs = pkgs.runCommand "jupyter-sandbox-rootfs-${name}" { } ''
        mkdir -p $out/{etc,bin,usr/bin,tmp}
        cp -rL ${pkgs.dockerTools.fakeNss}/etc/. $out/etc/
        ln -s ${pkgs.dockerTools.binSh}/bin/sh $out/bin/sh
        ln -s ${pkgs.dockerTools.usrBinEnv}/usr/bin/env $out/usr/bin/env
      '';
    in
    assert lib.assertMsg (unknown == [ ]) (
      "mkJupyter: no such kernel preset: ${lib.concatStringsSep ", " unknown}"
      + " (have: ${lib.concatStringsSep ", " (lib.attrNames presets)})"
    );
    pkgs.writeShellApplication {
      name = "jupyter-sandbox";
      runtimeInputs = [ pkgs.podman ];
      meta.mainProgram = "jupyter-sandbox";
      passthru = {
        inherit
          env
          kernelsDir
          jupyterConfig
          sandboxEnv
          rootfs
          definitions
          ;
      };
      text = ''
        port=''${JUPYTER_PORT:-${toString port}}
        state=''${STATE_DIR:-${stateDir}}

        # One server per checkout: two clones of the same template would
        # otherwise fight over one container name. $PWD is what tells them
        # apart, so fold it into the name.
        tag=$(printf %s "$PWD" | sha256sum | cut -c1-8)
        unit=''${JUPYTER_SANDBOX_NAME:-jupyter-${name}-$tag}

        # Everything mutable lives under the project's state dir, inside the
        # one writable bind mount. $PWD is mounted at the same path inside
        # the sandbox, so these paths mean the same thing on both sides and
        # survive a restart.
        abs_state=$PWD/$state

        # The container root, which podman must be able to write into to
        # create mountpoints -- so it cannot be the store path directly, and
        # cannot be inside the bind mount either. Stable per unit, staged by
        # `start` and dropped by `stop`.
        root=''${XDG_RUNTIME_DIR:-/tmp}/$unit.rootfs

        # Normally the server gets its own network namespace and is reached
        # through a loopback publish. Rootless, that needs /dev/net/tun for
        # pasta; on a host without it, JUPYTER_SANDBOX_NETWORK=host shares
        # the caller's netns instead. Filesystem isolation is unaffected
        # either way; only the network boundary goes.
        #
        # This is not enough to run the sandbox from inside another one --
        # from a lib/agent.nix shell, nested rootless podman has no
        # /etc/subuid and cannot mount /proc, which no flag here fixes. Start
        # the server from the host.
        net=''${JUPYTER_SANDBOX_NETWORK:-}

        args=(
          --rm --init --detach
          --name "$unit"
          --rootfs "$root"
          # the project: the only writable mount, and the only part of the
          # host this server can see
          -v "$PWD:$PWD" -w "$PWD"
          -v /nix/store:/nix/store:ro
          --mount "type=tmpfs,destination=/tmp,tmpfs-mode=1777,tmpfs-size=2g"
          -e HOME="$abs_state/home"
          -e PATH=${env}/bin:${sandboxEnv}/bin
          -e JUPYTER_DATA_DIR="$abs_state/jupyter-data"
          -e JUPYTER_RUNTIME_DIR="$abs_state/jupyter-runtime"
          -e JUPYTER_CONFIG_DIR="$abs_state/jupyter-config"
          -e IPYTHONDIR="$abs_state/ipython"
          # jupyterlab-git over https, and cargo for the rust kernel's :dep
          -e SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
        )
        ${lib.optionalString anyRust ''
          args+=(
            -e CARGO_HOME="$abs_state/cargo"
            -e CARGO_TARGET_DIR="$abs_state/cargo-target"
            -e CARGO_HTTP_CAINFO=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            -e XDG_CACHE_HOME="$abs_state/cache"
          )
        ''}
        ${lib.optionalString anyCuda ''
          args+=(
            --device /dev/nvidiactl --device /dev/nvidia0
            --device /dev/nvidia-uvm --device /dev/nvidia-uvm-tools
            -v /run/opengl-driver:/run/opengl-driver:ro
            -e LD_LIBRARY_PATH=/run/opengl-driver/lib
          )
        ''}

        # In its own netns the server binds 0.0.0.0 -- reachable only through
        # the loopback publish, so still not exposed -- while sharing the
        # caller's netns means binding loopback directly, and publishing
        # would be meaningless (podman rejects -p with --network=host).
        if [ "$net" = host ]; then
          args+=(--network=host)
          bind_ip=127.0.0.1
        else
          args+=(-p "127.0.0.1:$port:$port")
          bind_ip=0.0.0.0
        fi

        # custom_display_url is so the url jupyter prints is one that can
        # actually be pasted, rather than the in-container bind address.
        server=(
          ${env}/bin/jupyter-notebook
          --no-browser
          --ServerApp.ip="$bind_ip"
          --ServerApp.port="$port"
          --ServerApp.custom_display_url="http://127.0.0.1:$port/"
        )

        running() { podman container exists "$unit"; }
        url_from_log() { podman logs "$unit" 2>&1 | grep -m1 -o 'http://127.0.0.1:[^ ]*'; }

        case "''${1:-start}" in
          start)
            if running; then
              echo "$unit is already up"
              url_from_log || true
              exit 0
            fi
            mkdir -p "$abs_state"/{jupyter-data,jupyter-runtime,jupyter-config,home}
            rm -rf "$root"
            mkdir -p "$root"
            cp -r ${rootfs}/. "$root/"
            chmod -R u+w "$root"
            chmod 755 "$root"
            podman run "''${args[@]}" -- "''${server[@]}" >/dev/null
            for _ in $(seq 1 60); do
              if url=$(url_from_log); then echo "$unit up: $url"; exit 0; fi
              running || {
                echo "$unit died:" >&2
                podman logs "$unit" 2>&1 | tail -20 >&2
                exit 1
              }
              sleep 1
            done
            echo "$unit is up but printed no url; try: $0 logs" >&2
            exit 1
            ;;
          stop)
            if running; then
              podman stop "$unit" >/dev/null
              echo "$unit stopped"
            else
              echo "$unit is not running"
            fi
            rm -rf "$root"
            ;;
          status)
            if running; then
              podman ps --filter "name=$unit" --format '{{.Names}} {{.Status}} {{.Ports}}'
              url_from_log || true
            else
              echo "$unit is not running"
            fi
            ;;
          logs) podman logs -f "$unit" ;;
          shell) podman exec -it "$unit" ${pkgs.bashInteractive}/bin/bash ;;
          # what `start` would run, without running it
          print-cmd)
            printf '%q ' podman run "''${args[@]}" -- "''${server[@]}"
            echo
            ;;
          *)
            echo "usage: $0 {start|stop|status|logs|shell|print-cmd}" >&2
            exit 2
            ;;
        esac
      '';
    };
}
