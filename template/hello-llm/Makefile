# everything is built by nix; this Makefile is just ergonomics.
# `make test` needs neither a gpu nor systemd; `make run` needs systemd.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

# point at a local nornpkgs checkout when hacking on the fetchers:
#   make build NORNPKGS=path:/home/clownpiece/src/nornpkgs
NORNPKGS ?=
OVERRIDE := $(if $(NORNPKGS),--override-input nornpkgs '$(NORNPKGS)' --no-write-lock-file)

# every artifact lands under here: nix is pointed at --out-links inside
# $(BUILD_DIR) rather than dropping a ./result symlink into the source tree.
BUILD_DIR ?= build
RESULT := $(BUILD_DIR)/result
GGUF   := $(BUILD_DIR)/gguf

SRCS := flake.nix $(wildcard flake.lock)

PROMPT ?= The capital of France is
HOST ?= nonexistant

.PHONY: build gguf run ask logs status stop test copy clean

build: $(RESULT)

# just the model, no server
gguf: $(GGUF)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/:
	mkdir -p $@

# the out-links point into the store, where every mtime is epoch 1, so these
# recipes re-run whenever they are reached; nix is the actual incremental step.
$(RESULT): $(SRCS) | $(BUILD_DIR)/
	$(NIXCMD) build $(OVERRIDE) --out-link $@

$(GGUF): $(SRCS) | $(BUILD_DIR)/
	$(NIXCMD) build $(OVERRIDE) .#gguf --out-link $@ --print-out-paths

run: build
	$(RESULT)/bin/hello-llm start

ask: build
	$(RESULT)/bin/hello-llm ask "$(PROMPT)"

logs status stop: build
	$(RESULT)/bin/hello-llm $@

# serve, ask one question, shut down. no systemd, no gpu.
test: build
	$(RESULT)/bin/hello-llm selftest "$(PROMPT)"

# the gguf is in the closure, so this is the whole deployment
copy: build
	$(NIXCMD) copy --to ssh://$(HOST) $(RESULT)

clean:
	rm -rf $(BUILD_DIR)
