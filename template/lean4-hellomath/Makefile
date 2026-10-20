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

# every artifact lands under here: nix is pointed at an --out-link inside
# $(BUILD_DIR) rather than dropping a ./result symlink into the source tree.
BUILD_DIR ?= build

# the flake output this template is named after, built to $(BUILD_DIR)/$(NAME)
NAME := lean4-hellomath
BIN  := $(BUILD_DIR)/$(NAME)

# every lean module in the project, i.e. everything `make test` expects to find
# a compiled olean for. lakefile.lean is lake's own config, not a module.
LEANS := $(shell find . -name '*.lean' ! -name lakefile.lean \
                   -not -path './.lake/*' -not -path './$(BUILD_DIR)/*')
SRCS  := flake.nix flake.lock lakefile.lean lake-manifest.json $(LEANS)

.PHONY: build run test clean

build: $(BIN)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/:
	mkdir -p $@

$(BIN): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build .#$(NAME) --out-link $@

# depends on the artifact rather than on the phony `build`, so an out-link that
# is already in place is run as-is, without nix being consulted at all.
run: $(BIN)
	$(BIN)/bin/$(NAME)

# in lean the build *is* the typecheck, and Hellomath.lean's `assert_no_sorry`
# turns an admitted proof into a build error rather than a warning. so what is
# left to check is coverage: that every module in the project really did produce
# an olean, and none was silently left out of the lakefile's targets.
test: $(BIN)
	@fail=; for f in $(LEANS); do \
	  mod=$$(echo "$${f#./}" | sed 's/\.lean$$//; s#/#.#g'); \
	  if [ -e "$(BIN)/.lake/build/lib/lean/$$mod.olean" ]; then \
	    echo "type-checked: $$mod"; \
	  else \
	    echo "NOT BUILT:    $$mod (no $$mod.olean -- missing from lakefile.lean?)"; \
	    fail=1; \
	  fi; \
	done; \
	test -z "$$fail" || exit 1
	@echo "$(NAME): proofs type-checked, no sorry ✓"

clean:
	rm -rf $(BUILD_DIR) .lake
