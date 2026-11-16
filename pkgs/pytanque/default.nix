# pytanque: the Python client of petanque, coq-lsp's machine-to-machine
# protocol (`pet`). rocq-mcp's one dependency that nixpkgs does not have.
# It only talks to the `pet` it finds on PATH (stdio), or to a pet-server
# whose host and port its caller names; nothing else of the network.
#
#   pkgs.python3Packages.callPackage ./pkgs/pytanque { }
{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  requests,
  typing-extensions,
}:

buildPythonPackage (finalAttrs: {
  pname = "pytanque";
  version = "0.2.2";
  pyproject = true;

  # the tag rocq-mcp's pyproject.toml asks for, by its commit
  src = fetchFromGitHub {
    owner = "LLM4Rocq";
    repo = "pytanque";
    rev = "4092b1238b56468fdc1b3d100e078791c9690fd4"; # v0.2.2
    hash = "sha256-1Hae21BuMdE6MjRdiBO7fcsuS4HzahOdLLhynAUox3I=";
  };

  build-system = [ setuptools ];

  dependencies = [
    requests
    typing-extensions
  ];

  # the tests want a running pet
  doCheck = false;

  pythonImportsCheck = [ "pytanque" ];

  meta = {
    description = "Python client for petanque, the Rocq prover's coq-lsp interaction protocol";
    homepage = "https://github.com/LLM4Rocq/pytanque";
    license = lib.licenses.asl20;
  };
})
