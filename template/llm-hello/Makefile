# everything is built by nix; this Makefile is just ergonomics.
# `make test` needs neither a gpu nor systemd; `make run` needs systemd.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'

# point at a local nornpkgs checkout when hacking on the fetchers:
#   make build NORNPKGS=path:/home/clownpiece/src/nornpkgs
NORNPKGS ?=
OVERRIDE := $(if $(NORNPKGS),--override-input nornpkgs '$(NORNPKGS)' --no-write-lock-file)

# every artifact lands under here: nix is pointed at --out-links inside
# $(BUILD_DIR) rather than dropping a ./result symlink into the source tree.
BUILD_DIR ?= build

# the flake output this template is named after, built to $(BUILD_DIR)/$(NAME)
NAME := llm-hello
BIN  := $(BUILD_DIR)/$(NAME)
GGUF := $(BUILD_DIR)/gguf

SRCS := flake.nix $(wildcard flake.lock)

PROMPT ?= The capital of France is
HOST ?= nonexistant
SSH_FLAGS ?=

.PHONY: build gguf run ask logs status stop test copy remote clean

build: $(BIN)

# just the model, no server
gguf: $(GGUF)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/:
	mkdir -p $@

# the out-links point into the store, where every mtime is epoch 1, so these
# recipes re-run whenever they are reached; nix is the actual incremental step.
$(BIN): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build $(OVERRIDE) .#$(NAME) --out-link $@

$(GGUF): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build $(OVERRIDE) .#gguf --out-link $@ --print-out-paths

run: build
	$(BIN)/bin/$(NAME) start

ask: build
	$(BIN)/bin/$(NAME) ask "$(PROMPT)"

logs status stop: build
	$(BIN)/bin/$(NAME) $@

# serve, ask one question, shut down. no systemd, no gpu.
test: build
	$(BIN)/bin/$(NAME) selftest "$(PROMPT)"

# the gguf is in the closure, so this is the whole deployment
copy: build
	$(NIX) $(NIX_FLAGS) copy --to ssh://$(HOST) $(BIN)

# copy the closure to $(HOST), then run the oneshot there:
#   make remote HOST=hell PROMPT='the capital of france is'
# nothing is installed and no profile is touched. the closure lands in the
# remote store and the entry point is invoked by its absolute store path, so
# the far side needs a nix store and sshd and nothing else -- `nix copy` wants
# nix on the remote, the script itself does not. selftest is the oneshot:
# serve, wait for /health, ask once, shut the server down again, so no systemd
# and no gpu are required over there either.
remote: copy
	ssh $(SSH_FLAGS) "$(HOST)" "$$(readlink -f $(BIN))/bin/$(NAME) selftest '$(PROMPT)'"

clean:
	rm -rf $(BUILD_DIR)
