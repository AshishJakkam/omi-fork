<#
.SYNOPSIS
  Move the whisper model and the recoverable recordings into the OpenMind app container.

.DESCRIPTION
  OpenMind carries a different bundle id (com.openmind.app) than the old fork
  (com.omi.fork.WB98TW9DCS), so iOS gives it a separate container and it starts empty. That is
  fine for preferences, but the 61 recording files that still had audio on disk would otherwise
  be stranded in the old app and never transcribed.

  Copies, in this order:
    1. a whisper model -> Library/Application Support/models/ggml-<name>.bin
    2. wals.json + the audio it references -> Documents/

  Why the model name matters: FreemiumTranscriptionService prefers the SMALLEST ggml-*.bin it
  finds (tiny, base, small, medium, large-v1, large-v2). A fresh container has no model, so the
  pushed one is selected. If you ever push a second, smaller model, that one wins silently - the
  script prints the directory before and after so you can see what the app will actually use.

  go-ios has no `file rm`, so this cannot delete a stale model. If one is already present in the
  target container, reinstall the app to clear the container instead.

  Requires: phone connected and unlocked, and OpenMind already installed once, because the
  container must exist before anything can be written into it.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File iphone\restore-to-openmind.ps1 -Model base
#>
[CmdletBinding()]
param(
  [string]$TargetBundleId = 'com.openmind.app',
  [string]$Model = 'base',
  [string]$ModelFile = 'C:\omiwork\ggml-base.bin',
  [string]$BackupDir = 'C:\Users\ashis\omi-captures\recoverable-audio'
)

$ErrorActionPreference = 'Stop'
$ios = 'C:\go-ios\ios.exe'
if (-not (Test-Path $ios)) { throw "go-ios not found at $ios" }

function Invoke-Ios {
  param([string]$Arguments, [int]$TimeoutSeconds = 120, [switch]$Capture)
  $out = Join-Path $env:TEMP ("ios_" + [guid]::NewGuid().ToString('N') + ".txt")
  $p = Start-Process -FilePath $ios -ArgumentList $Arguments -RedirectStandardOutput $out `
        -RedirectStandardError "$out.err" -NoNewWindow -PassThru
  $null = $p.WaitForExit($TimeoutSeconds * 1000)
  if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; throw "timed out: $Arguments" }
  $text = if (Test-Path $out) { Get-Content $out -Raw } else { '' }
  Remove-Item $out -Force -ErrorAction SilentlyContinue
  Remove-Item "$out.err" -Force -ErrorAction SilentlyContinue
  if ($Capture) { return $text }
  return $p.ExitCode
}

Write-Host "`n== preflight ==" -ForegroundColor Cyan
$devices = Invoke-Ios -Arguments 'list' -Capture
if ($devices -notmatch '\d{8}-[0-9A-Fa-f]{16}') { throw 'no device. Connect it, unlock it, tap Trust.' }
Write-Host '  device connected'

$apps = Invoke-Ios -Arguments 'apps' -Capture
if ($apps -notmatch [regex]::Escape($TargetBundleId)) {
  throw "$TargetBundleId is not installed. Sideload OpenMind.ipa first - the container must exist."
}
Write-Host "  $TargetBundleId installed"

if (-not (Test-Path $ModelFile)) { throw "model file missing: $ModelFile" }
Write-Host ("  model: $ModelFile ({0} MB)" -f [math]::Round((Get-Item $ModelFile).Length / 1MB, 1))

$audio = @(Get-ChildItem $BackupDir -Filter '*.bin' -File -ErrorAction SilentlyContinue)
if (-not $audio) { throw "no backed-up audio in $BackupDir" }
$walsPath = Join-Path $BackupDir 'wals.json'
if (-not (Test-Path $walsPath)) { throw "wals.json missing in $BackupDir" }
Write-Host "  recordings: $($audio.Count) audio files + wals.json"

Write-Host "`n== 1. model ==" -ForegroundColor Cyan
$modelsDir = 'Library/Application Support/models'
$before = Invoke-Ios -Arguments "file ls --app=$TargetBundleId `"--path=$modelsDir`"" -Capture
Write-Host "  before: $($before.Trim())"
Invoke-Ios -Arguments "file push --app=$TargetBundleId `"--remote=$modelsDir/ggml-$Model.bin`" --local=$ModelFile" -TimeoutSeconds 600 | Out-Null
$after = Invoke-Ios -Arguments "file ls --app=$TargetBundleId `"--path=$modelsDir`"" -Capture
Write-Host "  after : $($after.Trim())"
Write-Host "  (the app selects the smallest ggml-*.bin present)" -ForegroundColor Yellow

Write-Host "`n== 2. recordings ==" -ForegroundColor Cyan
Invoke-Ios -Arguments "file push --app=$TargetBundleId --remote=Documents/wals.json --local=$walsPath" -TimeoutSeconds 180 | Out-Null
Write-Host '  pushed wals.json'
$i = 0
foreach ($f in $audio) {
  $i++
  Invoke-Ios -Arguments "file push --app=$TargetBundleId --remote=Documents/$($f.Name) --local=$($f.FullName)" -TimeoutSeconds 120 | Out-Null
  if ($i % 10 -eq 0) { Write-Host "  ... $i / $($audio.Count)" }
}
Write-Host "  pushed $($audio.Count) audio files"

Write-Host "`n== 3. launch ==" -ForegroundColor Cyan
Invoke-Ios -Arguments "launch $TargetBundleId" -TimeoutSeconds 60 | Out-Null
Write-Host "  launched $TargetBundleId"
Write-Host "`nNow open Settings -> Recording & transcription -> Transcription and confirm the model row says installed." -ForegroundColor Yellow
Write-Host "Then watch Offline Sync: the pending queue should start draining." -ForegroundColor Yellow
