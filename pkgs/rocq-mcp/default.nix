# rocq-mcp: an MCP server for Rocq (Coq) proof development: compile, verify,
# query, and step through proofs with `pet` (coq-lsp).
#
# The server looks for `rocq` and `pet` on PATH and for libraries on
# ROCQPATH, and pet and every library are built by one Rocq: so the package
# brings its toolchain (passthru.toolchain) and the server always runs with
# that one. Another Rocq, or more libraries than the standard one (what they
# need comes along):
#
#   rocq-mcp.override { rocqLibs = with rocqPackages; [ stdlib mathcomp ]; }
#   rocq-mcp.override {
#     rocqPackages = coqPackages;
#     rocq = coqPackages.coq;
#     rocqLibs = with coqPackages; [ VST compcert.lib ];
#   }
#
# Put `rocq-mcp.toolchain` among an agent closure's packages for the agent's
# own shell to have the same rocq (coqc, coqdep), with the same libraries.
# nornpkgs.lib.mkRocqMcp does both.
#
# Nothing here goes to the network: fastmcp's look at PyPI for a newer
# fastmcp, when it prints its banner, is turned off with the banner.
#
#   pkgs.callPackage ./pkgs/rocq-mcp { }
{
  lib,
  python3,
  fetchFromGitHub,
  makeBinaryWrapper,
  symlinkJoin,
  rocqPackages,
  rocq ? rocqPackages.rocq-core,
  rocqLibs ? [ rocqPackages.stdlib ],
}:

let
  # fastmcp 3 is for mcp 1 (nixpkgs marks it broken with its mcp, once that
  # is 2): a package set where mcp is mcp_1, for this server alone
  python = python3.override {
    self = python;
    packageOverrides = final: prev: { mcp = prev.mcp_1 or prev.mcp; };
  };
  python3Packages = python.pkgs;

  pytanque = python3Packages.callPackage ../pytanque { };

  # rocq, pet and coq-lsp, each finding rocqLibs
  toolchain = symlinkJoin {
    name = "${rocq.pname or "rocq"}-${rocq.version}-toolchain";
    paths = [
      rocq
      rocqPackages.coq-lsp
    ];
    # the setup hook of rocq says where each library is, and where those it
    # needs (propagated) are
    nativeBuildInputs = [
      makeBinaryWrapper
      rocq
    ];
    buildInputs = rocqLibs;
    postBuild = ''
      path=''${ROCQPATH-}
      if [ -n "''${COQPATH-}" ]; then path=''${path:+$path:}$COQPATH; fi
      for bin in rocq rocqchk coqc coqtop coqdep coqchk pet pet-server coq-lsp; do
        if [ -e $out/bin/$bin ]; then
          wrapProgram $out/bin/$bin --prefix ROCQPATH : "$path"
        fi
      done
    '';
  };
in
python3Packages.buildPythonApplication (finalAttrs: {
  pname = "rocq-mcp";
  version = "0.3.1-unstable-2026-10-19";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "LLM4Rocq";
    repo = "rocq-mcp";
    rev = "5251f5c91f89640439c43e491417fd76c420ab5b";
    hash = "sha256-s3u6ZUJuYMnaYlVH0B8+ZWPfJ3gqXRFjoeqXWH90v9I=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = [
    python3Packages.fastmcp
    python3Packages.psutil
    pytanque
  ];

  # the tests that say anything want rocq and pet, and write in the workspace
  doCheck = false;

  pythonImportsCheck = [ "rocq_mcp.server" ];

  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    "${toolchain}/bin"
    "--set-default"
    "FASTMCP_CHECK_FOR_UPDATES"
    "off"
    "--set-default"
    "FASTMCP_SHOW_SERVER_BANNER"
    "false"
  ];

  passthru = { inherit toolchain pytanque; };

  meta = {
    description = "MCP server for Rocq/Coq proof development";
    homepage = "https://github.com/LLM4Rocq/rocq-mcp";
    license = lib.licenses.asl20;
    mainProgram = "rocq-mcp";
  };
})
