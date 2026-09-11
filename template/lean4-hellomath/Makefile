# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

.PHONY: build run test clean

build:
	$(NIXCMD) build

run: build
	@echo "lean4-hellomath: proofs type-checked during build ✓ (oleans in ./result)"

test: build
	@echo "lean4-hellomath: proofs type-checked ✓"

clean:
	rm -f result
	rm -rf .lake
