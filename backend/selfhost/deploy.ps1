<#
.SYNOPSIS
  Deploy the self-hosted Omi backend to Fly.io.

.DESCRIPTION
  Runs the whole deploy in one pass: create the app, create the volumes the offline-stage
  storage and the service-account file need, import secrets, deploy.

  Deploy from a tree that actually contains the backend. This fork carries only `app` and
  `backend/selfhost`, so point -SourceRoot at a full upstream checkout with
  patches/selfhost-unlimited.patch applied.

  Windows blocks unsigned scripts by default, so run it as:

    powershell -ExecutionPolicy Bypass -File backend\selfhost\deploy.ps1 -AppName <name>

  Secrets are imported from a file and are never echoed. Nothing in this script prints the
  contents of backend/.env.

.PARAMETER AppName
  Globally unique Fly app name; also the host, so https://<AppName>.fly.dev.

.PARAMETER SourceRoot
  Full backend checkout. Defaults to C:\GitHub Repos\omi-fork.

.PARAMETER EnvFile
  The filled env file. Defaults to <repo>\backend\.env.

.PARAMETER SkipDeploy
  Stop after secrets are set, so the build can be inspected first.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$AppName,
  [string]$SourceRoot = 'C:\GitHub Repos\omi-fork',
  [string]$EnvFile = '',
  [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'

function Find-Flyctl {
  $candidates = @(
    "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Fly-io.flyctl_Microsoft.Winget.Source_8wekyb3d8bbwe\flyctl.exe",
    "$env:USERPROFILE\.fly\bin\flyctl.exe"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
  $found = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter 'flyctl.exe' -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($found) { return $found.FullName }
  throw 'flyctl.exe not found. Install with: winget install --id Fly-io.flyctl'
}

$fly = Find-Flyctl
Write-Host "flyctl: $fly"

if (-not (Test-Path (Join-Path $SourceRoot 'backend'))) {
  throw "No backend/ under '$SourceRoot'. Deploy from a full checkout, not this app-only fork."
}
if (-not $EnvFile) { $EnvFile = Join-Path $SourceRoot 'backend\.env' }
if (-not (Test-Path $EnvFile)) {
  throw "Env file '$EnvFile' is missing. Copy backend/selfhost/env.selfhost.template and fill it in."
}

# Verify the unlock switch is on before spending a deploy on it.
$envText = Get-Content $EnvFile -Raw
if ($envText -notmatch '(?m)^OMI_SELFHOST_UNLIMITED=true\s*$') {
  Write-Warning 'OMI_SELFHOST_UNLIMITED is not set to true - the deployment will still meter usage.'
}
if ($envText -match 'CHANGE-ME|^API_BASE_URL=\s*$') {
  throw "Env file still contains CHANGE-ME placeholders or an empty API_BASE_URL."
}
if ($envText -match '(?m)^BASE_API_URL=.*/\s*$') {
  Write-Warning 'BASE_API_URL ends with a slash; the Google callback would become //v1/auth/callback.'
}

$serviceAccount = Join-Path $SourceRoot 'backend\secrets\firebase-service-account.json'
if (-not (Test-Path $serviceAccount)) {
  throw "Missing $serviceAccount - generate it in Firebase console -> Project settings -> Service accounts."
}

Write-Host "`n=== app ===" -ForegroundColor Cyan
& $fly apps list 2>&1 | Out-String | Write-Verbose
$existing = (& $fly apps list --json 2>$null | ConvertFrom-Json) | Where-Object { $_.Name -eq $AppName }
if ($existing) {
  Write-Host "  app '$AppName' already exists"
} else {
  & $fly apps create $AppName
  if ($LASTEXITCODE -ne 0) { throw "fly apps create failed ($LASTEXITCODE)" }
  Write-Host "  created '$AppName'"
}

Write-Host "`n=== volumes ===" -ForegroundColor Cyan
$volumes = (& $fly volumes list -a $AppName --json 2>$null | ConvertFrom-Json)
foreach ($spec in @(@{ Name = 'omi_data'; Size = 3; Mount = '/app/syncing' }, @{ Name = 'omi_secrets'; Size = 1; Mount = '/app/secrets' })) {
  if ($volumes | Where-Object { $_.Name -eq $spec.Name }) {
    Write-Host "  volume $($spec.Name) exists"
  } else {
    # Fly derives the volume name from the app, so create by explicit name.
    & $fly volumes create $spec.Name --region bom --size $spec.Size -a $AppName --yes
    if ($LASTEXITCODE -ne 0) { throw "fly volumes create $($spec.Name) failed ($LASTEXITCODE)" }
    Write-Host "  created volume $($spec.Name)"
  }
}

Write-Host "`n=== secrets ===" -ForegroundColor Cyan
# Imported from the file; values are never printed. PowerShell has no `<` redirection,
# so the file is piped into stdin instead.
$secretTmp = Join-Path $env:TEMP 'omi-secrets.env'
Get-Content $EnvFile |
  Where-Object { $_ -match '^[A-Za-z_][A-Za-z0-9_]*=' -and $_ -notmatch '^\s*#' } |
  Set-Content $secretTmp -Encoding utf8
Get-Content $secretTmp | & $fly secrets import -a $AppName
if ($LASTEXITCODE -ne 0) { throw "fly secrets import failed ($LASTEXITCODE)" }
Remove-Item $secretTmp -Force
& $fly secrets set -a $AppName FIREBASE_AUTH_CREDENTIALS_PATH=/app/secrets/firebase-service-account.json
Write-Host '  secrets imported'

if ($SkipDeploy) { Write-Host "`n-SkipDeploy set; stopping before build." -ForegroundColor Yellow; return }

Write-Host "`n=== deploy ===" -ForegroundColor Cyan
Push-Location $SourceRoot
try {
  & $fly deploy -a $AppName --dockerfile backend/selfhost/Dockerfile --config backend/selfhost/fly.toml
  if ($LASTEXITCODE -ne 0) { throw "fly deploy failed ($LASTEXITCODE)" }
}
finally { Pop-Location }

Write-Host "`n=== verify ===" -ForegroundColor Cyan
& $fly checks list -a $AppName
Write-Host "`n  base url: https://$AppName.fly.dev"
Write-Host "  authorize: https://$AppName.fly.dev/v1/auth/authorize"
Write-Host "  callback : https://$AppName.fly.dev/v1/auth/callback/google"
