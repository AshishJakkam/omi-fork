# Finish the OpenMind install whenever the phone is unlocked, with no clicks from the user.
#
# Sideloadly leaves "Installation failed ... Coordinator superseded" plus an enabled Retry button
# when a previous attempt was interrupted mid-transfer; pressing Retry replays the same conflict.
# Cancelling first drops the stale install coordinator so Start begins a clean one.
param(
  [string]$Ipa = 'C:\Users\ashis\Downloads\OpenMind-live.ipa',
  [string]$BundleId = 'com.openmind.app.WB98TW9DCS',
  [int]$WaitMinutes = 240,
  [int]$Attempts = 6
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$ios = 'C:\Users\ashis\Tools\go-ios\ios.exe'
$udid = '00008140-001475300E11801C'
$log = 'C:\Users\ashis\omi-captures\install2.log'

function Write-Log([string]$message) {
  $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $message
  Write-Host $line
  Add-Content -Path $log -Value $line
}

function Test-Unlocked {
  $out = (cmd /c "`"$ios`" info --udid=$udid 2>&1") -join "`n"
  return $out -match '"PasswordProtected":false'
}

function Wait-Unlocked([int]$minutes) {
  $deadline = (Get-Date).AddMinutes($minutes)
  while ((Get-Date) -lt $deadline) {
    if (Test-Unlocked) { return $true }
    Start-Sleep -Seconds 4
  }
  return $false
}

function Get-Sideloadly {
  $win = Get-Process sideloadly -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if (-not $win) { return $null }
  return [System.Windows.Automation.AutomationElement]::FromHandle($win.MainWindowHandle)
}

function Get-Button($root, [string]$name) {
  $cond = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,
      [System.Windows.Automation.ControlType]::Button)),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)))
  return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
}

function Press($element) {
  if (-not $element) { return }
  $invoke = $null
  $element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invoke) | Out-Null
  if ($invoke) { $invoke.Invoke() }
}

function Read-Progress($root) {
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Text)
  $bits = @()
  foreach ($t in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
    $n = $t.Current.Name
    if ($n -match '%|failed|issue|Complete|Signing|Uploading|Installing') { $bits += $n.Trim() }
  }
  return ($bits -join ' | ')
}

if (-not (Wait-Unlocked $WaitMinutes)) { Write-Log 'gave up waiting for unlock'; exit 3 }
Write-Log 'device unlocked'

$installed = $false
for ($i = 1; $i -le $Attempts; $i++) {
  if (-not (Test-Unlocked)) {
    Write-Log "attempt $i waiting for unlock"
    if (-not (Wait-Unlocked $WaitMinutes)) { Write-Log 'gave up waiting for unlock'; exit 3 }
  }

  # A window left in "Sideloading failed!" keeps Start disabled for good, so every attempt gets a
  # fresh process. Nothing is lost by killing it: the coordinator lives on the device, not here.
  $exe = 'C:\Users\ashis\AppData\Local\Sideloadly\Sideloadly.exe'
  Get-Process sideloadly -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 3
  Start-Process -FilePath $exe -ArgumentList ('"' + $Ipa + '"') | Out-Null

  $root = $null
  for ($w = 0; $w -lt 20; $w++) {
    Start-Sleep -Seconds 3
    $root = Get-Sideloadly
    if ($root) { break }
  }
  if (-not $root) { Write-Log "attempt $i Sideloadly window never appeared"; continue }
  Start-Sleep -Seconds 6

  $root = Get-Sideloadly
  $start = Get-Button $root 'Start'
  if ($start -and $start.Current.IsEnabled) {
    Write-Log "attempt $i pressing Start"
    Press $start
  } else {
    Write-Log "attempt $i Start not pressable: $(Read-Progress $root)"
    continue
  }

  $deadline = (Get-Date).AddMinutes(9)
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 6
    if (-not (Test-Unlocked)) { Write-Log "attempt $i device locked mid-install"; break }
    $root = Get-Sideloadly
    if (-not $root) { break }
    $progress = Read-Progress $root
    $retry = Get-Button $root 'Retry'
    $start = Get-Button $root 'Start'
    if (-not $retry -and $start -and $start.Current.IsEnabled -and -not ($progress -match 'failed')) {
      $installed = $true
      Write-Log "attempt $i installed"
      break
    }
    if ($progress -match 'failed') { Write-Log "attempt $i failed: $progress"; break }
  }
  if ($installed) { break }
}

if (-not $installed) { Write-Log 'install did not succeed'; exit 5 }

Write-Log 'launching and collecting the on-device log'
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\omiwork\tools\pull-device-log.ps1' -BundleId $BundleId -Launch 2>&1 |
  ForEach-Object { Write-Log "  $_" }
Write-Log 'done'
