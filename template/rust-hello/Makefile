# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'

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
NAME := rust-hello
BIN  := $(BUILD_DIR)/$(NAME)
JUPYTER := $(BUILD_DIR)/jupyter

SRCS := flake.nix flake.lock Cargo.toml Cargo.lock $(shell find src -type f)

.PHONY: build run test start_jupyter stop_jupyter status_jupyter clean

build: $(BIN)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/:
	mkdir -p $@

# the out-link points into the store, where every mtime is epoch 1, so this
# recipe re-runs whenever it is reached; nix is the actual incremental step.
$(BIN): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build $(OVERRIDE) .#$(NAME) --out-link $@

$(JUPYTER): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build $(OVERRIDE) .#jupyter --out-link $@

run: build
	$(BIN)/bin/$(NAME)

test:
	$(NIX) $(NIX_FLAGS) develop $(OVERRIDE) --command cargo test

# ---- jupyter -------------------------------------------------------------
#
# The kernel is evcxr, which rebuilds a scratch crate for every cell and
# fetches `:dep` crates from crates.io -- the cargo dirs it churns through
# land in $(STATE_DIR), inside the sandbox.
# podman tracks the server by container name, so there is no pidfile here and
# nothing to go stale. `jupyter-sandbox` also takes status, logs, shell and
# print-cmd; the port comes from the flake, and JUPYTER_PORT overrides it.

start_jupyter stop_jupyter status_jupyter: %_jupyter: $(JUPYTER)
	STATE_DIR=$(STATE_DIR) $(JUPYTER)/bin/jupyter-sandbox $*

# `make stop_jupyter` first if the server is up: this drops the state dir
# out from under it. The container is named, not pid-tracked, so a stop
# still works afterwards either way.
clean:
	rm -rf $(BUILD_DIR) $(STATE_DIR) target
