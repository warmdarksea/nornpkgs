<#
.SYNOPSIS
  Pin the UEFI BootOrder so the NanoKVM virtual-media entry boots first.

.DESCRIPTION
  Windows Boot Manager promotes itself to the head of BootOrder on every boot
  and after servicing updates, which demotes the NanoKVM entry. The firmware
  then never boots the NanoKVM media, the uefi_trampoline never runs, and a
  remote `nanokvmctl boot` silently does nothing.

  Nothing in the UEFI spec lets a running OS lock BootOrder, so both OSes
  re-assert it: lib/boot-order-assert.sh on the NixOS side (systemd, on start
  and stop) and this script here.

  The entry is resolved by label on every run rather than from a baked-in GUID,
  because the firmware regenerates and renumbers its own USB boot entries.
  /addfirst only moves the match to the head and leaves the rest of the order
  alone, so this is idempotent and will not fight the NixOS unit over the
  relative order of the two OS entries.

.PARAMETER Match
  Regex matched against each `bcdedit /enum firmware` block. Default 'NanoKVM'.

.PARAMETER DryRun
  Report what would change, write nothing.

.NOTES
  Must run elevated. Install as a SYSTEM task that runs at startup:

    copy boot-order-assert.ps1 C:\ProgramData\
    schtasks /create /f /tn "Assert BootOrder" /ru SYSTEM /rl HIGHEST /sc ONSTART ^
      /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\boot-order-assert.ps1"

  Startup alone is enough: the clobbering happens during Windows' own boot, so
  repairing it straight afterwards restores the order for every later reset.
  To cover update-driven shutdowns too, point a Group Policy shutdown script
  (gpedit.msc -> Computer Configuration -> Windows Settings -> Scripts) at it;
  Task Scheduler has no clean shutdown trigger.
#>

param(
    [string]$Match = 'NanoKVM',
    [switch]$DryRun
)

$blocks = (bcdedit /enum firmware | Out-String) -split "`r?`n`r?`n"
$entry = $blocks | Where-Object { $_ -match $Match } | Select-Object -First 1

if (-not $entry) {
    Write-Output "boot-order-assert: no firmware entry matching '$Match'; leaving BootOrder alone"
    exit 0
}

if ($entry -notmatch '(\{[0-9a-fA-F-]{36}\})') {
    Write-Output "boot-order-assert: no identifier GUID in the '$Match' entry; leaving BootOrder alone"
    exit 1
}
$guid = $Matches[1]

Write-Output "boot-order-assert: moving '$Match' ($guid) to the head of BootOrder"
if ($DryRun) { exit 0 }

bcdedit /set '{fwbootmgr}' displayorder $guid /addfirst
if ($LASTEXITCODE -ne 0) {
    Write-Output "boot-order-assert: bcdedit failed ($LASTEXITCODE)"
    exit $LASTEXITCODE
}
