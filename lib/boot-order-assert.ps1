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

  Everything is logged to -LogFile, because as a SYSTEM startup task there is
  nowhere for console output to go. Check that file to see whether it worked.

.PARAMETER Label
  Regex matched against each `bcdedit /enum firmware` block. Default 'NanoKVM'.

.PARAMETER DryRun
  Report what would change, write nothing.

.PARAMETER LogFile
  Append a timestamped line per run. Default %ProgramData%\boot-order-assert.log.
  Pass '' to disable logging to disk.

.NOTES
  Must run elevated -- bcdedit cannot read firmware entries otherwise, which
  this script detects and reports rather than failing silently.

  Install as a SYSTEM task that runs at startup:

    copy boot-order-assert.ps1 C:\ProgramData\
    schtasks /create /f /tn "Assert BootOrder" /ru SYSTEM /rl HIGHEST /sc ONSTART ^
      /tr "powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\boot-order-assert.ps1"

  Dry run it once by hand first, from an elevated prompt:

    powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\boot-order-assert.ps1 -DryRun

  Startup alone is enough: the clobbering happens during Windows' own boot, so
  repairing it straight afterwards restores the order for every later reset.
  To cover update-driven shutdowns too, point a Group Policy shutdown script
  (gpedit.msc -> Computer Configuration -> Windows Settings -> Scripts) at it;
  Task Scheduler has no clean shutdown trigger.

  Exit codes: 0 ok or nothing to do, 1 could not read/parse, 2 the write failed
  or did not take effect.
#>

param(
    [string]$Label = 'NanoKVM',
    [switch]$DryRun,
    [string]$LogFile = "$env:ProgramData\boot-order-assert.log"
)

# A GUID as bcdedit prints it on an `identifier` line.
$guidRe = '\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\}'

function Write-Log {
    param([string]$Message)
    $line = '{0} boot-order-assert: {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Output $line
    if ($LogFile) {
        try { Add-Content -LiteralPath $LogFile -Value $line -Encoding ASCII } catch { }
    }
}

# Head of {fwbootmgr} displayorder, i.e. what the firmware will try first.
function Get-FirstInOrder {
    $raw = (& bcdedit /enum '{fwbootmgr}' 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { return $null }
    $m = [regex]::Match($raw, '(?im)^\s*displayorder\s+(\{[^}]+\})')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

$raw = (& bcdedit /enum firmware 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    Write-Log ("bcdedit /enum firmware failed (exit {0}); must run elevated. Output: {1}" -f $LASTEXITCODE, $raw.Trim())
    exit 1
}

# bcdedit separates entries with a blank line and uses CRLF; tolerate LF too.
$entry = $null
foreach ($block in ($raw -split '(?:\r?\n){2,}')) {
    if ($block -match $Label) { $entry = $block; break }
}

if (-not $entry) {
    Write-Log ("no firmware entry matching '{0}'; leaving BootOrder alone" -f $Label)
    exit 0
}

# Anchor on the identifier line rather than taking the first GUID anywhere in
# the block, so a GUID appearing in some other field cannot be picked up.
$idMatch = [regex]::Match($entry, '(?im)^\s*identifier\s+(' + $guidRe + ')\s*$')
if (-not $idMatch.Success) {
    Write-Log ("found a '{0}' entry but no identifier GUID in it; leaving BootOrder alone. Entry was: {1}" -f $Label, ($entry.Trim() -replace '\s+', ' '))
    exit 1
}
$guid = $idMatch.Groups[1].Value

$first = Get-FirstInOrder
if ($first -and $first -eq $guid) {
    Write-Log ("'{0}' ({1}) is already first; nothing to do" -f $Label, $guid)
    exit 0
}

Write-Log ("moving '{0}' ({1}) to the head of BootOrder (currently {2})" -f $Label, $guid, $(if ($first) { $first } else { 'unknown' }))
if ($DryRun) {
    Write-Log 'dry run, wrote nothing'
    exit 0
}

$out = (& bcdedit /set '{fwbootmgr}' displayorder $guid /addfirst 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    Write-Log ("bcdedit /set failed (exit {0}): {1}" -f $LASTEXITCODE, $out.Trim())
    exit 2
}

# Confirm it actually took, rather than trusting a zero exit.
$now = Get-FirstInOrder
if ($now -eq $guid) {
    Write-Log 'ok, BootOrder now starts with the NanoKVM entry'
    exit 0
}
Write-Log ("bcdedit reported success but BootOrder still starts with {0}" -f $(if ($now) { $now } else { 'unknown' }))
exit 2
