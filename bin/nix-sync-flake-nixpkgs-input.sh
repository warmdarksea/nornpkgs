#!/bin/sh

nix flake update --override-input nixpkgs "github:nixos/nixpkgs/$(nixos-version --revision)"
