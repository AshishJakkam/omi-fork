# Prove live transcription on the phone and capture it, unattended.
#
# iOS refuses WDA screenshots with "Not authorized for performing UI testing actions" once the
# XCTest runner loses its authorization (a re-sign or a long lock does it), and only relaunching the
# runner over a trusted USB tunnel restores it. So this waits for the device, owns the tunnel,
# relaunches the runner, and only then records and screenshots - reporting the refusal instead of
# tapping blind when a step does not hold.
param(
  [string]$BundleId = 'com.openmind.app.WB98TW9DCS',
  [string]$RunnerId = 'com.facebook.WebDriverAgentRunner.xctrunner.WB98TW9DCS',
  [int]$WaitMinutes = 240,
  [int]$RecordSeconds = 60,
  [string]$Ipa = 'C:\Users\ashis\Downloads\OpenMind-auto.ipa'
)

$ErrorActionPreference = 'Continue'
$ios = 'C:\Users\ashis\Tools\go-ios\ios.exe'
$udid = '00008140-001475300E11801C'
$out = 'C:\Users\ashis\omi-captures\demo'
$log = Join-Path $out 'verify.log'
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Write-Log([string]$message) {
  $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $message
  Write-Host $line
  Add-Content -Path $log -Value $line
}

function Get-Info { ((cmd /c "`"$ios`" info --udid=$udid 2>&1") -join "`n") }

function Test-Attached {
  $list = ((cmd /c "`"$ios`" list 2>&1") -join "`n")
  return $list -match [regex]::Escape($udid)
}

function Test-Ready {
  if (-not (Test-Attached)) { return $false }
  $info = Get-Info
  return ($info -match '"TrustedHostAttached":true') -and ($info -match '"PasswordProtected":false')
}

function Test-Tunnel {
  $a = 'file ls --app=' + $BundleId + ' --path=/Documents'
  return (((cmd /c "`"$ios`" $a 2>&1") -join "`n") -match '"path":"/Documents"')
}

function Repair-Tunnel {
  if (Test-Tunnel) { return $true }
  # Only the port's owner is stale; killing every ios process also kills a tunnel that works.
  foreach ($conn in (Get-NetTCPConnection -LocalPort 60105 -ErrorAction SilentlyContinue)) {
    Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
  }
  Start-Sleep -Seconds 2
  Start-Process -FilePath $ios -ArgumentList @('tunnel', 'start', '--userspace', "--udid=$udid") -WindowStyle Hidden | Out-Null
  for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Seconds 3
    if (Test-Tunnel) { return $true }
  }
  return $false
}

function Start-Runner {
  $existing = $null
  try { $existing = Invoke-WebRequest -Uri 'http://192.168.1.10:8100/status' -TimeoutSec 3 -UseBasicParsing } catch { }
  $runnerArgs = @('runwda', "--udid=$udid", '--tunnel-info-port=60105',
    "--bundleid=$RunnerId", "--testrunnerbundleid=$RunnerId",
    '--xctestconfig=WebDriverAgentRunner.xctest',
    "--log-output=$(Join-Path $out 'wda.log')")
  Start-Process -FilePath $ios -ArgumentList $runnerArgs -WindowStyle Hidden | Out-Null
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 4
    try { if ((Invoke-WebRequest -Uri 'http://192.168.1.10:8100/status' -TimeoutSec 3 -UseBasicParsing).StatusCode -eq 200) { return $true } } catch { }
  }
  return $false
}

for ($round = 1; $round -le 40; $round++) {
  Write-Log "round $round waiting for an unlocked, trusted USB device"
  $deadline = (Get-Date).AddMinutes($WaitMinutes / 40)
  while ((Get-Date) -lt $deadline -and -not (Test-Ready)) { Start-Sleep -Seconds 5 }
  if (-not (Test-Ready)) { continue }

  Write-Log 'device ready'
  if (-not (Repair-Tunnel)) { Write-Log 'tunnel could not be established'; continue }
  Write-Log 'tunnel up'

  # Install before touching the runner: a reinstall voids WDA's UI-testing authorization, so the
  # runner has to come last or the demo is refused.
  $marker = Join-Path $out 'installed.marker'
  $needInstall = (Test-Path $Ipa) -and ((Test-Path $marker) -eq $false -or (Get-Item $Ipa).LastWriteTime -gt (Get-Item $marker).LastWriteTime)
  if ($needInstall) {
    Write-Log "installing $Ipa"
    powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\omiwork\tools\finish-install.ps1' -Ipa $Ipa -WaitMinutes 20 -Attempts 3 2>&1 |
      ForEach-Object { Write-Log "  $_" }
    if (-not (Test-Tunnel) -and -not (Repair-Tunnel)) { Write-Log 'tunnel lost after install'; continue }
    Set-Content -Path $marker -Value (Get-Date -Format o)
  } else {
    Write-Log 'staged build already installed'
  }

  if (-not (Start-Runner)) { Write-Log 'WDA runner did not come up'; continue }
  Write-Log 'WDA listening; relaunching the driver session'

  Push-Location 'C:\Users\ashis\omi-captures'
  $probe = (python -c "import wda,base64; s=wda.session(); print('SID',s); r=wda._req('GET','/session/%s/screenshot'%s) if s else {}; v=r.get('value'); print('SHOT','ok' if isinstance(v,str) else str(v)[:100])" 2>&1) -join "`n"
  Pop-Location
  Write-Log "probe: $($probe -replace '\r?\n', ' | ')"

  if ($probe -notmatch 'SHOT ok') {
    Write-Log 'screenshots still refused; a human may need to accept the UI-testing prompt'
    Start-Sleep -Seconds 30
    continue
  }

  Write-Log "recording for $RecordSeconds seconds"
  Push-Location 'C:\Users\ashis\omi-captures'
  python demo_taps.py 2>&1 | ForEach-Object { Write-Log "  $_" }
  Pop-Location

  Write-Log 'reading the app log'
  powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\omiwork\tools\pull-device-log.ps1' -BundleId $BundleId 2>&1 |
    ForEach-Object { Write-Log "  $_" }
  $deviceLog = 'C:\Users\ashis\omi-captures\on_device.log'
  if (Test-Path $deviceLog) {
    Copy-Item $deviceLog (Join-Path $out 'on_device.log') -Force
    Write-Log '--- engine and flush lines ---'
    Select-String -Path $deviceLog -Pattern 'live engine|polling service=|engine=|run done|ingestion' |
      Select-Object -Last 30 | ForEach-Object { Write-Log "  $($_.Line)" }
  }
  Write-Log 'demo complete'
  exit 0
}

Write-Log 'gave up'
exit 3
