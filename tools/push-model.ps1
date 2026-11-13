# Put the whisper model back into the freshly installed app and restart it, then pull the log.
#
# A Sideloadly reinstall replaces the app's data container, so the downloaded ggml model that makes
# on-device transcription work lives in the old, orphaned container. Pushing a local copy restores
# it without a 141 MB download on the phone.
param(
  [string]$Model = 'C:\omiwork\ggml-base.bin',
  [string]$BundleId = 'com.openmind.app.WB98TW9DCS',
  [int]$WaitMinutes = 240
)

$ErrorActionPreference = 'Continue'
$ios = 'C:\Users\ashis\Tools\go-ios\ios.exe'
$udid = '00008140-001475300E11801C'
$log = 'C:\Users\ashis\omi-captures\push-model.log'

function Write-Log([string]$message) {
  $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $message
  Write-Host $line
  Add-Content -Path $log -Value $line
}

function Test-Unlocked {
  $out = (cmd /c "`"$ios`" info --udid=$udid 2>&1") -join "`n"
  return $out -match '"PasswordProtected":false'
}

if (-not (Test-Path $Model)) { Write-Log "model not found: $Model"; exit 3 }

$deadline = (Get-Date).AddMinutes($WaitMinutes)
while ((Get-Date) -lt $deadline) {
  if (Test-Unlocked) { break }
  Start-Sleep -Seconds 5
}
if (-not (Test-Unlocked)) { Write-Log 'gave up waiting for unlock'; exit 3 }
Write-Log 'device unlocked'

$remote = 'Library/Application Support/models/' + [System.IO.Path]::GetFileName($Model)
$arg = 'file push --app=' + $BundleId + ' --local="' + $Model + '" --remote="' + $remote + '"'
Write-Log "pushing to $remote"
cmd /c "`"$ios`" $arg 2>&1" | ForEach-Object { Write-Log "  $_" }

$lsArg = 'file ls --app=' + $BundleId + ' --path="Library/Application Support/models"'
$listing = (cmd /c "`"$ios`" $lsArg 2>&1") -join "`n"
Write-Log "models now: $listing"

Write-Log 'launching and collecting the on-device log'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\omiwork\tools\pull-device-log.ps1' -BundleId $BundleId -Launch 2>&1 |
  ForEach-Object { Write-Log "  $_" }
Write-Log 'done'
