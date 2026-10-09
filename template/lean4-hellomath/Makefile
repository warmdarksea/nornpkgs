# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'

# every artifact lands under here: nix is pointed at an --out-link inside
# $(BUILD_DIR) rather than dropping a ./result symlink into the source tree.
BUILD_DIR ?= build

# the flake output this template is named after, built to $(BUILD_DIR)/$(NAME)
NAME := lean4-hellomath
BIN  := $(BUILD_DIR)/$(NAME)

SRCS := flake.nix flake.lock lakefile.lean lake-manifest.json Hellomath.lean

.PHONY: build run test clean

build: $(BIN)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/:
	mkdir -p $@

# the out-link points into the store, where every mtime is epoch 1, so this
# recipe re-runs whenever it is reached; nix is the actual incremental step.
$(BIN): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build .#$(NAME) --out-link $@

run: build
	@echo "lean4-hellomath: proofs type-checked during build ✓ (oleans in $(BIN))"

test: build
	@echo "lean4-hellomath: proofs type-checked ✓"

clean:
	rm -rf $(BUILD_DIR) .lake
