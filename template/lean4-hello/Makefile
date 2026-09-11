# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

.PHONY: build run test clean

build:
	$(NIXCMD) build

run: build
	./result/bin/lean4-hello

# lean: the build IS the typecheck
test: build
	@echo "lean4-hello: type-checked ✓"

clean:
	rm -f result
	rm -rf .lake
