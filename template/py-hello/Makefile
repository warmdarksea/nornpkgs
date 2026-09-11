# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

.PHONY: build run test clean

build:
	$(NIXCMD) build

run: build
	./result/bin/py-hello

test:
	$(NIXCMD) develop --command pytest -q tests

clean:
	rm -f result
