#!/usr/bin/env bash
# Sign (if SB_KEY is set) a trampoline .efi and wrap it in a small hybrid ISO
# (ISO9660 + appended GPT/ESP) that the NanoKVM will accept and boot as USB or CD.
#
# Env in: TEFI (path to unsigned BOOTX64.EFI), OUT (target .iso), TSLUG (volume tag),
#         ESP_MB (FAT16 ESP size, default 4), SB_KEY / SB_CERT (Secure Boot db, optional).
set -euo pipefail
: "${TEFI:?}" "${OUT:?}" "${TSLUG:?}"
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT

if [ -n "${SB_KEY:-}" ] && [ -n "${SB_CERT:-}" ]; then
  echo "signing with $SB_KEY"
  sbsign --key "$SB_KEY" --cert "$SB_CERT" --output "$w/BOOTX64.EFI" "$TEFI"
  sbverify --cert "$SB_CERT" "$w/BOOTX64.EFI"
else
  echo "NOTE: unsigned image (set SB_KEY=<db.key> SB_CERT=<db.pem> for Secure Boot)"
  cp "$TEFI" "$w/BOOTX64.EFI"
fi

export MTOOLS_SKIP_CHECK=1
dd if=/dev/zero of="$w/esp.img" bs=1M count="${ESP_MB:-4}" status=none
mformat -c 1 -i "$w/esp.img" ::            # small FAT16 (UEFI allows FAT16 on removable ESPs)
mmd -i "$w/esp.img" ::/EFI ::/EFI/BOOT
mcopy -i "$w/esp.img" "$w/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mkdir -p "$w/isoroot"; cp "$w/esp.img" "$w/isoroot/efiboot.img"
xorriso -as mkisofs -V "TRAMP_${TSLUG}" \
  -e efiboot.img -no-emul-boot \
  -append_partition 2 0xef "$w/isoroot/efiboot.img" \
  -partition_offset 16 \
  -o "$OUT" "$w/isoroot"
