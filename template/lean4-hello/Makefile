# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

# every artifact lands under here: nix is pointed at an --out-link inside
# $(BUILD_DIR) rather than dropping a ./result symlink into the source tree.
BUILD_DIR ?= build
RESULT := $(BUILD_DIR)/result

SRCS := flake.nix flake.lock lakefile.lean lake-manifest.json Main.lean

.PHONY: build run test clean

build: $(RESULT)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/:
	mkdir -p $@

# the out-link points into the store, where every mtime is epoch 1, so this
# recipe re-runs whenever it is reached; nix is the actual incremental step.
$(RESULT): $(SRCS) | $(BUILD_DIR)/
	$(NIXCMD) build --out-link $@

run: build
	$(RESULT)/bin/lean4-hello

# lean: the build IS the typecheck
test: build
	@echo "lean4-hello: type-checked ✓"

clean:
	rm -rf $(BUILD_DIR) .lake
