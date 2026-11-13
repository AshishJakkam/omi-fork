# Read the app's on-device log over USB, with no clicks and no WebDriverAgent.
# The runner writes Documents/on_device.log, so a failed run states its own cause.
param(
  [string]$BundleId = 'com.openmind.app.WB98TW9DCS',
  [string]$OutPath = 'C:\Users\ashis\omi-captures\on_device.log',
  [switch]$Launch,
  [int]$SettleSeconds = 45
)

$ErrorActionPreference = 'Stop'
$ios = 'C:\Users\ashis\Tools\go-ios\ios.exe'

if ($Launch) {
  & $ios launch --bundleid=$BundleId 2>&1 | Out-Null
  Start-Sleep -Seconds $SettleSeconds
}

if (Test-Path $OutPath) { Remove-Item $OutPath -Force }
& $ios file pull --app=$BundleId --remote=Documents/on_device.log --local=$OutPath 2>&1 | Out-Null

if (-not (Test-Path $OutPath)) { Write-Output 'no on_device.log on the device'; exit 1 }
Write-Output "pulled $((Get-Item $OutPath).Length) bytes"
Get-Content $OutPath -Tail 60
