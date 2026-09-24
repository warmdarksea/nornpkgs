# everything is built by nix; this Makefile is just ergonomics.
# `make test` needs neither a gpu nor systemd; `make run` needs systemd.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'
NIXCMD := $(NIX) $(NIX_FLAGS)

# point at a local nornpkgs checkout when hacking on the fetchers:
#   make build NORNPKGS=path:/home/clownpiece/src/nornpkgs
NORNPKGS ?=
OVERRIDE := $(if $(NORNPKGS),--override-input nornpkgs '$(NORNPKGS)' --no-write-lock-file)

PROMPT ?= The capital of France is
HOST ?= nonexistant

.PHONY: build gguf run ask logs status stop test copy clean

build:
	$(NIXCMD) build $(OVERRIDE)

# just the model, no server
gguf:
	$(NIXCMD) build $(OVERRIDE) .#gguf --no-link --print-out-paths

run: build
	./result/bin/hello-llm start

ask: build
	./result/bin/hello-llm ask "$(PROMPT)"

logs status stop: build
	./result/bin/hello-llm $@

# serve, ask one question, shut down. no systemd, no gpu.
test: build
	./result/bin/hello-llm selftest "$(PROMPT)"

# the gguf is in the closure, so this is the whole deployment
copy: build
	$(NIXCMD) copy --to ssh://$(HOST) ./result

clean:
	rm -f result
