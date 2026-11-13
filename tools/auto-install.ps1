# Load an IPA into the running Sideloadly and press Start, with no clicks from the user.
# Sideloadly is single-instance: passing the IPA path as its argument loads that file into the
# existing window, which is the only reliable way to hand it a build without drag-and-drop.
param(
  [string]$Ipa = 'C:\Users\ashis\Downloads\OpenMind-auto.ipa',
  [int]$TimeoutSeconds = 420
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes

$exe = 'C:\Users\ashis\AppData\Local\Sideloadly\Sideloadly.exe'
if (-not (Test-Path $exe)) { throw "Sideloadly not found at $exe" }
if (-not (Test-Path $Ipa)) { throw "IPA not found: $Ipa" }

# 1. Hand the IPA to Sideloadly. A forwarded argument replaces the loaded file.
$p = Start-Process -FilePath $exe -ArgumentList ('"' + $Ipa + '"') -PassThru
Start-Sleep -Seconds 10
if (-not $p.HasExited) { $p | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue }

$win = Get-Process sideloadly -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $win) { throw 'Sideloadly window not found' }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($win.MainWindowHandle)

# 2. Confirm the intended file is the one loaded, by name, before pressing anything.
$textCond = New-Object System.Windows.Automation.PropertyCondition(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
  [System.Windows.Automation.ControlType]::Text)
$texts = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCond)
$loaded = $null
foreach ($t in $texts) {
  if ($t.Current.Name -match '\.ipa') { $loaded = $t.Current.Name; break }
}
$want = [System.IO.Path]::GetFileName($Ipa)
if ($loaded -and $loaded -notlike "*$want*") { throw "Sideloadly has '$loaded' loaded, expected $want" }

# 3. Press Start.
$cond = New-Object System.Windows.Automation.AndCondition(
  (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)),
  (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Start')))
$start = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
if (-not $start) { throw 'Start button not found' }
$invoke = $null
$start.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$invoke) | Out-Null
$invoke.Invoke()

# 4. Wait for Start to come back enabled, which is how Sideloadly signals it finished.
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 5
  if ($start.Current.IsEnabled) { 'sideload finished'; exit 0 }
}
'still running after timeout'
exit 2
