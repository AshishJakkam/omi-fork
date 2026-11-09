<#
.SYNOPSIS
  Check every self-host prerequisite before spending a deploy.

.DESCRIPTION
  Deploy failures from a typo in this setup are slow to diagnose: the container builds for
  minutes, then the app starts and dies on a config error, or sign-in bounces with
  redirect_uri_mismatch long after the deploy. This checks the same things locally, in
  seconds, and prints the exact redirect URI to paste into the Google console.

  Read-only. It never prints secret values - only whether they are present and plausible.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File backend\selfhost\preflight.ps1
#>
[CmdletBinding()]
param(
  [string]$RepoRoot = 'C:\omiwork',
  [string]$AppName = 'omi-open'
)

$ErrorActionPreference = 'Continue'
$fail = 0
$warn = 0

function Ok($m)   { Write-Host "  [ok]   $m" -ForegroundColor Green }
function Bad($m)  { Write-Host "  [FAIL] $m" -ForegroundColor Red; $script:fail++ }
function Warn($m) { Write-Host "  [warn] $m" -ForegroundColor Yellow; $script:Warn++ }

$envPath = Join-Path $RepoRoot 'backend\.env'
$saPath = Join-Path $RepoRoot 'backend\secrets\firebase-service-account.json'

Write-Host "`n== env file ==" -ForegroundColor Cyan
if (-not (Test-Path $envPath)) {
  Bad "missing $envPath"
} else {
  Ok "found $envPath"
  $lines = Get-Content $envPath
  $map = @{}
  foreach ($l in $lines) {
    if ($l -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') { $map[$Matches[1]] = $Matches[2].Trim() }
  }

  foreach ($k in 'OMI_ENV_STAGE','PROVIDER_MODE','OMI_SELFHOST_UNLIMITED','BASE_API_URL','ENCRYPTION_SECRET',
                 'FIREBASE_AUTH_PROJECT_ID','FIREBASE_AUTH_DOMAIN','FIREBASE_AUTH_CREDENTIALS_PATH',
                 'GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GEMINI_API_KEY') {
    if (-not $map.ContainsKey($k)) { Bad "missing key: $k" }
    elseif ($map[$k] -match 'CHANGE-ME' -or $map[$k] -eq '') { Bad "$k still unset or placeholder" }
    else { Ok "$k is set" }
  }

  if ($map['OMI_SELFHOST_UNLIMITED'] -ne 'true') { Bad "OMI_SELFHOST_UNLIMITED must be 'true' to unlock allowances" }
  if ($map['OMI_ENV_STAGE'] -ne 'offline') { Warn "OMI_ENV_STAGE is '$($map['OMI_ENV_STAGE'])'; 'offline' keeps storage on the instance and needs no GCS" }

  if ($map['BASE_API_URL'] -match '/$') {
    Bad "BASE_API_URL ends with '/': the Google callback would become //v1/auth/callback/google"
  } elseif ($map['BASE_API_URL'] -notmatch '^https://') {
    Bad "BASE_API_URL must be https"
  } else { Ok "BASE_API_URL is a slash-free https URL" }

  if ($map['ENCRYPTION_SECRET'] -and $map['ENCRYPTION_SECRET'].Length -lt 32) {
    Bad "ENCRYPTION_SECRET is shorter than 32 bytes; startup refuses to serve"
  } elseif ($map['ENCRYPTION_SECRET']) { Ok "ENCRYPTION_SECRET length is $($map['ENCRYPTION_SECRET'].Length)" }

  if ($map['GOOGLE_CLIENT_ID'] -and $map['GOOGLE_CLIENT_ID'] -notmatch '\.apps\.googleusercontent\.com$') {
    Warn "GOOGLE_CLIENT_ID does not end in .apps.googleusercontent.com - is that a web client id?"
  }
}

Write-Host "`n== service account ==" -ForegroundColor Cyan
if (-not (Test-Path $saPath)) {
  Bad "missing $saPath"
} else {
  Ok "found the service-account JSON"
  try {
    $sa = Get-Content $saPath -Raw | ConvertFrom-Json
    if ($sa.type -ne 'service_account') { Bad "type is '$($sa.type)', expected service_account" } else { Ok "type=service_account" }
    if (-not $sa.project_id) { Bad "no project_id in the JSON" } else { Ok "project_id=$($sa.project_id)" }
    if ($map -and $map['FIREBASE_AUTH_PROJECT_ID'] -and $sa.project_id -ne $map['FIREBASE_AUTH_PROJECT_ID']) {
      Bad "project_id '$($sa.project_id)' does not match FIREBASE_AUTH_PROJECT_ID '$($map['FIREBASE_AUTH_PROJECT_ID'])'"
    } elseif ($map -and $map['FIREBASE_AUTH_PROJECT_ID']) { Ok "project_id matches .env" }
    if ($sa.client_email) { Ok "client_email=$($sa.client_email)" }
    if ($sa.private_key -and $sa.private_key -notmatch 'BEGIN PRIVATE KEY') { Bad "private_key does not look like a PEM key" }
  } catch { Bad "the JSON does not parse: $($_.Exception.Message)" }
}

Write-Host "`n== secrets are not committable ==" -ForegroundColor Cyan
Push-Location $RepoRoot
try {
  foreach ($rel in 'backend/.env','backend/secrets/firebase-service-account.json') {
    $r = git check-ignore $rel 2>$null
    if ($r) { Ok "$rel is gitignored" } else { Bad "$rel is NOT gitignored" }
  }
} catch { Warn "could not run git check-ignore here" } finally { Pop-Location }

Write-Host "`n== fly ==" -ForegroundColor Cyan
$flyCandidates = @(
  "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Fly-io.flyctl_Microsoft.Winget.Source_8wekyb3d8bbwe\flyctl.exe",
  "$env:USERPROFILE\.fly\bin\flyctl.exe"
)
$fly = $flyCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $fly) { Bad "flyctl not found" } else {
  Ok "flyctl present"
  & $fly auth whoami *> $null
  if ($LASTEXITCODE -eq 0) { Ok "authenticated as $((& $fly auth whoami 2>$null))" }
  else { Bad "not logged in - run: fly auth login" }
}
if ($AppName) {
  if ($AppName -match '^omi-open') { Ok "app name '$AppName'" }
  else { Warn "app name '$AppName' differs from the assumed 'omi-open'; update BASE_API_URL and the OAuth redirect to match" }
}

Write-Host "`n== paste this into the Google OAuth client ==" -ForegroundColor Cyan
if ($map -and $map['BASE_API_URL']) {
  Write-Host "  $($map['BASE_API_URL'])/v1/auth/callback/google" -ForegroundColor White
  Write-Host "  (authorize endpoint: $($map['BASE_API_URL'])/v1/auth/authorize)"
} else { Warn "BASE_API_URL unknown, cannot build the redirect URI" }

Write-Host ""
if ($fail -gt 0) {
  Write-Host "  $fail check(s) failed - fix these before deploying." -ForegroundColor Red
  exit 1
} else {
  Write-Host "  All preflight checks passed." -ForegroundColor Green
  exit 0
}
