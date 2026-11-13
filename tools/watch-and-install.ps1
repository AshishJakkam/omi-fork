# Watch one existing workflow run, then stage and sideload its IPA with no clicks.
# Separate from auto-build.ps1 because dispatching again would only add to the macOS queue.
param(
  [Parameter(Mandatory = $true)][string]$RunId,
  [string]$OutFile = 'C:\Users\ashis\Downloads\OpenMind-live.ipa'
)

$ErrorActionPreference = 'Stop'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$repo = 'AshishJakkam/omi-fork'
$log = 'C:\Users\ashis\omi-captures\watch.log'

function Log([string]$m) {
  Add-Content -Path $log -Value ('{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m)
}

Log "watching run $RunId"
$status = $null
for ($i = 0; $i -lt 240; $i++) {
  Start-Sleep -Seconds 15
  try {
    $status = & $gh run view $RunId -R $repo --json status,conclusion 2>$null | ConvertFrom-Json
    if ($status.status -eq 'completed') { break }
  } catch {
    Log "poll error (continuing): $($_.Exception.Message.Split([char]10)[0])"
  }
}

if (-not $status -or $status.status -ne 'completed') { Log 'timed out waiting for the run'; exit 1 }
Log "run finished: $($status.conclusion)"
if ($status.conclusion -ne 'success') { exit 1 }

$dest = 'C:\Users\ashis\Downloads\_live_dl'
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
& $gh run download $RunId -R $repo -n OpenMind-ipa -D $dest 2>$null | Out-Null
$ipa = Get-ChildItem $dest -Recurse -Filter '*.ipa' | Select-Object -First 1
if (-not $ipa) { Log 'no ipa in artifact'; exit 1 }
Copy-Item $ipa.FullName $OutFile -Force
Log "staged $OutFile ($([math]::Round($ipa.Length / 1MB, 1)) MB)"

Log 'installing'
& (Join-Path $PSScriptRoot 'auto-install.ps1') -Ipa $OutFile 2>&1 | ForEach-Object { Log "  $_" }
Log "install exit: $LASTEXITCODE"

if ($LASTEXITCODE -eq 0) {
  Log 'launching and collecting the on-device log'
  & (Join-Path $PSScriptRoot 'pull-device-log.ps1') -Launch 2>&1 | ForEach-Object { Log "  $_" }
}
