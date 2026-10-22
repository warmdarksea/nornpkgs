#!/usr/bin/env bash
#
# boot-order-assert.sh -- pin the UEFI BootOrder with the NanoKVM entry first.
#
# Windows Boot Manager promotes itself to the head of BootOrder on every boot
# (and after servicing updates), which demotes the NanoKVM virtual-media entry.
# The firmware then never boots the NanoKVM media, the uefi_trampoline never
# runs, and a remote `nanokvmctl boot` silently does nothing -- which from the
# outside is indistinguishable from a Secure Boot rejection.
#
# Nothing in the UEFI spec lets a running OS lock BootOrder (it is a plain
# NV+BS+RT variable, not an authenticated one, and edk2's VariableLock is
# firmware-internal), so both OSes re-assert it instead: this script via
# systemd.services.assert-boot-order on start *and* stop, and its counterpart
# lib/boot-order-assert.ps1 on the Windows side.
#
# Entries are resolved by *label*, never by a hardcoded Boot#### id: the NanoKVM
# entry is firmware-generated -- a device-path-only entry with no file path --
# and the firmware renumbers it whenever it rebuilds the boot list.
#
# Needs efibootmgr, awk, sed, grep, coreutils; must be root to write.
#
#   ESP_GUID=<hex>  leading hex of the GPT guid of the ESP holding the OS
#                   loaders, used to tell the live Windows Boot Manager entry
#                   apart from a stale one on another disk.
#   DRY_RUN=1       report what would change, write nothing.

set -euo pipefail

ESP_GUID="${ESP_GUID:-1d93d9ac}"
DRY_RUN="${DRY_RUN:-}"

# entry_id <label substring> <extra substring, or ""> -> Boot#### of first match.
# awk deliberately does not `exit` on the first hit: that closes the pipe early,
# and efibootmgr dying of SIGPIPE would trip `set -o pipefail`.
entry_id() {
  efibootmgr -v | awk -v a="$1" -v b="$2" '
    found { next }
    /^Boot[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]/ \
      && index($0, a) && (b == "" || index($0, b)) { print substr($1, 5, 4); found = 1 }'
}

nanokvm=$(entry_id "NanoKVM" "")
nixos=$(entry_id "Linux Boot Manager" "")
windows=$(entry_id "Windows Boot Manager" "$ESP_GUID")

current=$(efibootmgr | sed -n 's/^BootOrder: //p')

# NanoKVM first so mounted trampoline media always wins; NixOS second so a
# failed trampoline still leaves an OS that is reachable over the network.
want=$(printf '%s\n' "$nanokvm" "$nixos" "$windows" | grep . | paste -sd,)

if [ -z "$nanokvm" ]; then
  echo "boot-order-assert: no NanoKVM entry present, leaving BootOrder=$current" >&2
  exit 0
fi

if [ "$current" = "$want" ]; then
  echo "boot-order-assert: BootOrder already $current"
  exit 0
fi

echo "boot-order-assert: BootOrder $current -> $want"

if [ -n "$DRY_RUN" ]; then
  exit 0
fi

efibootmgr -o "$want" >/dev/null
