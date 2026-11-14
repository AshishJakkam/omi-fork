# Arm the live-transcription demo and run it unattended.
#
# The installer and the log reader both need the device to be unlocked AND trusted with this host;
# a re-sign drops that trust and only the person holding the phone can tap Trust. So wait for it,
# then do the whole demo - start a capture, screenshot the live transcript, and pull the app log
# that names the engine - without needing anyone at the keyboard.
param(
  [string]$BundleId = 'com.openmind.app.WB98TW9DCS',
  [int]$WaitMinutes = 240
)

$ErrorActionPreference = 'Continue'
$ios = 'C:\Users\ashis\Tools\go-ios\ios.exe'
$udid = '00008140-001475300E11801C'
$out = 'C:\Users\ashis\omi-captures\demo'
$log = Join-Path $out 'demo.log'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Write-Log([string]$message) {
  $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $message
  Write-Host $line
  Add-Content -Path $log -Value $line
}

function Get-DeviceInfo {
  return ((cmd /c "`"$ios`" info --udid=$udid 2>&1") -join "`n")
}

function Test-Ready {
  $info = Get-DeviceInfo
  $trusted = $info -match '"TrustedHostAttached":true'
  $unlocked = $info -match '"PasswordProtected":false'
  return $trusted -and $unlocked
}

function Test-Tunnel {
  $a = 'file ls --app=' + $BundleId + ' --path=/Documents'
  $res = ((cmd /c "`"$ios`" $a 2>&1") -join "`n")
  return $res -match '"path":"/Documents"'
}

function Start-Tunnel {
  Get-Process ios -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  Start-Process -FilePath $ios -ArgumentList @('tunnel', 'start', '--userspace', "--udid=$udid") -WindowStyle Hidden | Out-Null
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 3
    if (Test-Tunnel) { return $true }
  }
  return $false
}

Write-Log "waiting for an unlocked, trusted device (up to $WaitMinutes minutes)"
$deadline = (Get-Date).AddMinutes($WaitMinutes)
while ((Get-Date) -lt $deadline -and -not (Test-Ready)) { Start-Sleep -Seconds 10 }
if (-not (Test-Ready)) { Write-Log 'gave up waiting for trust'; exit 3 }
Write-Log 'device unlocked and trusted'

$tunnel = Start-Tunnel
Write-Log "tunnel: $tunnel"

Write-Log 'running the demo'
Push-Location 'C:\Users\ashis\omi-captures'
python demo_taps.py 2>&1 | ForEach-Object { Write-Log "  $_" }
Pop-Location

Write-Log 'reading the app log'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\omiwork\tools\pull-device-log.ps1' -BundleId $BundleId 2>&1 |
  ForEach-Object { Write-Log "  $_" }
$deviceLog = 'C:\Users\ashis\omi-captures\on_device.log'
if (Test-Path $deviceLog) {
  Copy-Item $deviceLog (Join-Path $out 'on_device.log') -Force
  $interesting = Select-String -Path $deviceLog -Pattern 'live engine|polling service=|engine=|decision run=|run done'
  Write-Log "--- engine lines ---"
  $interesting | Select-Object -Last 25 | ForEach-Object { Write-Log "  $($_.Line)" }
}
Write-Log 'done'
