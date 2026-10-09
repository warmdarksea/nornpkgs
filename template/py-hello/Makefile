# everything is built by nix; this Makefile is just ergonomics.
NIX ?= nix
NIX_FLAGS ?= --extra-experimental-features 'nix-command flakes'

# every artifact lands under here: nix is pointed at an --out-link inside
# $(BUILD_DIR) rather than dropping a ./result symlink into the source tree.
BUILD_DIR ?= build
# everything mutable the jupyter server needs: pid, log, and the data,
# runtime and config dirs it would otherwise scatter through $HOME.
STATE_DIR ?= state

# the flake output this template is named after, built to $(BUILD_DIR)/$(NAME)
NAME := py-hello
BIN  := $(BUILD_DIR)/$(NAME)

JUPYTER      := $(BUILD_DIR)/jupyter
JUPYTER_PID  := $(STATE_DIR)/jupyter.pid
JUPYTER_LOG  := $(STATE_DIR)/jupyter.log
# one template, one server: the templates use adjacent ports so several can
# run at once. the server walks forward from here if the port is taken, so
# the url in the log is the authority, not this number.
JUPYTER_PORT ?= 8888

SRCS := flake.nix flake.lock pyproject.toml conftest.py \
        $(shell find py_hello tests -type f)

.PHONY: build run test start_jupyter stop_jupyter clean

build: $(BIN)

# the trailing slash is deliberate: a target named plain `$(BUILD_DIR)` would
# collide with the phony `build` above, and make drops that rule as circular.
$(BUILD_DIR)/ $(STATE_DIR)/:
	mkdir -p $@

# the out-link points into the store, where every mtime is epoch 1, so this
# recipe re-runs whenever it is reached; nix is the actual incremental step.
$(BIN): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build .#$(NAME) --out-link $@

$(JUPYTER): $(SRCS) | $(BUILD_DIR)/
	$(NIX) $(NIX_FLAGS) build .#jupyter --out-link $@

run: build
	$(BIN)/bin/$(NAME)

test:
	$(NIX) $(NIX_FLAGS) develop --command pytest -q tests

# ---- jupyter -------------------------------------------------------------
#
# The kernel brings its own python -- and this project -- from the store, so
# the server is launched straight out of $(JUPYTER) with no devshell in
# between. Auth is jupyter's default single-use token; the url in the log
# carries it.

# `kill -0` succeeds on a zombie as readily as on a live process, and a
# server whose parent never reaped it looks exactly like that: gone, but
# still in the process table. So check the state field in /proc rather than
# trust kill -0 on its own, or stop_jupyter spends its whole grace period
# waiting on a process that already exited. (The field is the one after the
# comm field's closing paren; comm can contain spaces, so counting columns
# from the left is not safe.)
ALIVE = alive() { \
	  { [ -n "$$1" ] && kill -0 "$$1" 2>/dev/null; } || return 1; \
	  s=$$(sed -n 's/.*) \([A-Za-z]\).*/\1/p' /proc/"$$1"/stat 2>/dev/null); \
	  [ -n "$$s" ] && [ "$$s" != Z ]; \
	}

start_jupyter: $(JUPYTER) | $(STATE_DIR)/
	@$(ALIVE); \
	if [ -s $(JUPYTER_PID) ] && alive "$$(cat $(JUPYTER_PID))"; then \
	  echo "jupyter already running (pid $$(cat $(JUPYTER_PID)))"; exit 0; \
	fi; \
	JUPYTER_DATA_DIR=$(abspath $(STATE_DIR))/jupyter-data \
	JUPYTER_RUNTIME_DIR=$(abspath $(STATE_DIR))/jupyter-runtime \
	JUPYTER_CONFIG_DIR=$(abspath $(STATE_DIR))/jupyter-config \
	IPYTHONDIR=$(abspath $(STATE_DIR))/ipython \
	nohup $(JUPYTER)/bin/jupyter-notebook --no-browser --port=$(JUPYTER_PORT) \
	  >$(JUPYTER_LOG) 2>&1 & \
	echo $$! >$(JUPYTER_PID); \
	for _ in $$(seq 1 60); do \
	  url=$$(grep -m1 -o 'http://localhost:[^ ]*' $(JUPYTER_LOG) 2>/dev/null) && \
	    { echo "jupyter up (pid $$(cat $(JUPYTER_PID))): $$url"; exit 0; }; \
	  alive "$$(cat $(JUPYTER_PID))" || \
	    { echo "jupyter died; see $(JUPYTER_LOG):" >&2; tail -20 $(JUPYTER_LOG) >&2; exit 1; }; \
	  sleep 1; \
	done; \
	echo "jupyter is up (pid $$(cat $(JUPYTER_PID))) but printed no url; see $(JUPYTER_LOG)" >&2; \
	exit 1

stop_jupyter:
	@$(ALIVE); \
	if [ ! -s $(JUPYTER_PID) ]; then echo "jupyter not running (no $(JUPYTER_PID))"; exit 0; fi; \
	pid=$$(cat $(JUPYTER_PID)); \
	if alive "$$pid"; then \
	  kill "$$pid"; \
	  for _ in $$(seq 1 30); do alive "$$pid" || break; sleep 1; done; \
	  if alive "$$pid"; then kill -9 "$$pid" 2>/dev/null || true; fi; \
	  echo "jupyter stopped (pid $$pid)"; \
	else \
	  echo "jupyter not running (stale pid $$pid)"; \
	fi; \
	rm -f $(JUPYTER_PID)

# does not stop a running server: `make stop_jupyter` first, or the pid in
# $(STATE_DIR) goes away from under it.
clean:
	rm -rf $(BUILD_DIR) $(STATE_DIR)
