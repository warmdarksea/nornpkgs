# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'

# the artifacts below are nix out-links: symlinks into the store, where every
# mtime is epoch 1. without -L make stats *through* the symlink, sees 1970,
# concludes the artifact is older than every source, and re-runs `nix build` --
# a full flake re-evaluation -- on every `make run`. -L (--check-symlink-times)
# makes make take the newer of the link's own mtime and its target's, i.e. the
# moment nix created the out-link, so an artifact that is already there counts
# as up to date and `make run` just runs it.
MAKEFLAGS += -L

# point at a local nornpkgs checkout when hacking on lib/jupyter.nix:
#   make start_jupyter NORNPKGS=path:/home/clownpiece/src/nornpkgs
NORNPKGS ?=
OVERRIDE := $(if $(NORNPKGS),--override-input nornpkgs '$(NORNPKGS)' --no-write-lock-file)

# every artifact lands under here: nix is pointed at an --out-link inside
# $(BUILD_DIR) rather than dropping a ./result symlink into the source tree.
BUILD_DIR ?= build
# everything the sandboxed server keeps between runs: jupyter's data,
# runtime and config dirs, its $HOME, and the kernels' caches. Inside the
# project, because the project is the sandbox's only writable mount.
STATE_DIR ?= state

# the flake output this template is named after, built to $(BUILD_DIR)/$(NAME)
NAME := py-hello
BIN  := $(BUILD_DIR)/$(NAME)
JUPYTER := $(BUILD_DIR)/jupyter

# only the files the flake's fileset actually feeds to the build: a __pycache__
# or .pytest_cache swept up by a bare `find` would make every test run look
# like a source change.
SRCS := flake.nix flake.lock pyproject.toml conftest.py \
        $(shell find py_hello tests -name '*.py')

.PHONY: build run test start_jupyter stop_jupyter status_jupyter clean

build: $(BIN)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/:
	mkdir -p $@

$(BIN): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build $(OVERRIDE) .#$(NAME) --out-link $@

$(JUPYTER): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build $(OVERRIDE) .#jupyter --out-link $@

# depends on the artifact rather than on the phony `build`, so an out-link that
# is already in place is run as-is, without nix being consulted at all.
run: $(BIN)
	$(BIN)/bin/$(NAME)

# the devshell, not the artifact: pytest runs against the working tree, so this
# one does have to evaluate the flake.
test:
	$(NIX) $(NIX_FLAGS) develop $(OVERRIDE) --command pytest -q tests

# ---- jupyter -------------------------------------------------------------
#
# The kernel brings its own python -- and this project -- from the store.
# podman tracks the server by container name, so there is no pidfile here and
# nothing to go stale. `jupyter-sandbox` also takes status, logs, shell and
# print-cmd; the port comes from the flake, and JUPYTER_PORT overrides it.

start_jupyter stop_jupyter status_jupyter: %_jupyter: $(JUPYTER)
	STATE_DIR=$(STATE_DIR) $(JUPYTER)/bin/jupyter-sandbox $*

# `make stop_jupyter` first if the server is up: this drops the state dir
# out from under it. The container is named, not pid-tracked, so a stop
# still works afterwards either way.
clean:
	rm -rf $(BUILD_DIR) $(STATE_DIR)
