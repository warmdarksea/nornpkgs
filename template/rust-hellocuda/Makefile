# everything is built by nix; this Makefile is just ergonomics.
# `make build` and `make test` need no GPU; `make run` does.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

.PHONY: build run test clean

build:
	$(NIXCMD) build

run: build
	./result/bin/rust-hellocuda

test:
	$(NIXCMD) develop --command cargo test

clean:
	rm -f result
	rm -rf target
