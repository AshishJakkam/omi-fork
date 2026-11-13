# Trigger on-device transcription on the phone and dump the app's own log.
# Assumes WDA is running (see start-wda.ps1) and the app is installed.
param(
  [string]$LogOut = 'C:\Users\ashis\omi-captures\on_device.log',
  [int]$WaitSeconds = 45
)

$ErrorActionPreference = 'Stop'
$ios = 'C:\Users\ashis\Tools\go-ios\ios.exe'
$udid = '00008140-001475300E11801C'
$bundle = $null

function Log([string]$m) { Write-Host ((Get-Date -Format 'HH:mm:ss') + ' ' + $m) }

# Resolve the installed bundle id: Sideloadly appends a suffix to the plain id.
$apps = & $ios apps --udid=$udid 2>$null | Out-String
$m = [regex]::Match($apps, '"CFBundleIdentifier":"(com\.openmind\.app[^"]*)"')
if (-not $m.Success) { throw 'OpenMind is not installed' }
$bundle = $m.Groups[1].Value
Log "bundle: $bundle"

# Pull the log the runner writes. Missing file simply means no run happened yet.
& $ios file pull --udid=$udid --app=$bundle "--remote=Documents/on_device.log" "--local=$LogOut" 2>$null | Out-Null
if (Test-Path $LogOut) { Log "existing log: $((Get-Content $LogOut | Measure-Object -Line).Lines) lines" } else { Log 'no log yet' }

# Drive the app: Activity page carries the queue banner with Try Again / Transcribe now.
$py = @'
import sys, time
sys.path.insert(0, r"C:\Users\ashis\omi-captures")
import wda

sid = wda.session(BUNDLE)
if not sid or isinstance(sid, dict):
    print("session failed:", sid)
    sys.exit(1)
time.sleep(5)
wda.tap(200, 742)      # dismiss paywall if present
time.sleep(2)
wda.tap(324, 90)       # Activity
time.sleep(2.5)
r = wda.tap_text('Try Again')
print("try again:", r)
if isinstance(r, dict) and r.get('error'):
    r = wda.tap_text('Transcribe now')
    print("transcribe now:", r)
time.sleep(WAIT)
'@ -replace 'BUNDLE', "'$bundle'" -replace 'WAIT', "$WaitSeconds"
$tmp = Join-Path $env:TEMP 'drive.py'
[System.IO.File]::WriteAllText($tmp, $py, (New-Object System.Text.UTF8Encoding($false)))
python $tmp
Remove-Item $tmp -Force

Start-Sleep -Seconds 5
& $ios file pull --udid=$udid --app=$bundle "--remote=Documents/on_device.log" "--local=$LogOut" 2>$null | Out-Null
if (Test-Path $LogOut) {
  Log '--- on_device.log tail ---'
  Get-Content $LogOut -Tail 25
} else {
  Log 'still no log written'
}
