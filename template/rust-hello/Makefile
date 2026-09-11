# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

.PHONY: build run test clean

build:
	$(NIXCMD) build

run: build
	./result/bin/rust-hello

test:
	$(NIXCMD) develop --command cargo test

clean:
	rm -f result
	rm -rf target
