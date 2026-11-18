# Deploy the self-hosted backend to Cloud Run - the free-tier path.
#
#   powershell -ExecutionPolicy Bypass -File backend\selfhost\deploy-cloudrun.ps1 -Project aiwearable-pilot
#
# Cloud Run is what Omi itself runs (backend/deploy/staging/deploy.sh uses `gcloud run deploy`), so
# this follows the same shape at personal scale. It stays inside the monthly free tier for one user:
# 180k vCPU-seconds, 360k GiB-seconds, 2M requests.
#
# What it cannot avoid:
#   * Billing must be enabled on the project even to use the free tier. Set a budget alert.
#   * Cloud Run scales to zero, so the first request after idle pays a 15-30s cold start. Uploads go
#     through a WAL queue that retries, so a cold start delays a sync rather than losing it.
#   * Egress from outside North America may be billed, so a Mumbai deployment can cost cents.
param(
  [Parameter(Mandatory = $true)][string]$Project,
  [string]$Region = 'asia-south1',
  [string]$Service = 'aiwearable-pilot',
  [string]$Repo = 'omi-selfhost',
  [string]$Image = 'backend',
  [string]$EnvFile = '',
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $EnvFile) { $EnvFile = Join-Path $root 'backend\.env' }

function Step($m) { Write-Host "`n== $m ==" -ForegroundColor Cyan }
function Need($cmd) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    throw "$cmd is not installed. Install the Google Cloud SDK, then run 'gcloud auth login'."
  }
}
function EnvMap([string]$path) {
  $map = @{}
  foreach ($line in Get-Content $path) {
    $t = $line.Trim()
    if (-not $t -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $map[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
  }
  return $map
}

Need 'gcloud'
if (-not (Test-Path $EnvFile)) { throw "env file not found: $EnvFile" }

Step 'Check the unlock is in the source before spending a build'
$sub = Join-Path $root 'backend\utils\subscription.py'
if (-not (Select-String -Path $sub -Pattern 'def\s+selfhost_unlimited_enabled' -Quiet)) {
  throw "unlock switch missing from subscription.py - apply backend\selfhost\patches\selfhost-unlimited.patch"
}
Write-Host '  unlock present'

Step "Target project $Project"
gcloud config set project $Project | Out-Null
$billing = (gcloud billing projects describe $Project --format='value(billingEnabled)' 2>$null)
if ($billing -ne 'True') {
  throw "Billing is not enabled on $Project. Cloud Run requires a billing account even for the free tier. Enable it and set a budget alert first."
}
Write-Host '  billing enabled'

Step 'Enable the APIs this needs'
foreach ($api in @('run.googleapis.com', 'artifactregistry.googleapis.com', 'cloudbuild.googleapis.com')) {
  gcloud services enable $api --project $Project | Out-Null
  Write-Host "  $api"
}

Step "Artifact Registry repository $Repo in $Region"
$existing = gcloud artifacts repositories describe $Repo --location $Region --format='value(name)' 2>$null
if (-not $existing) {
  gcloud artifacts repositories create $Repo --repository-format=docker --location $Region --description='self-hosted backend images' | Out-Null
  Write-Host '  created'
} else {
  Write-Host '  already exists'
}

$tag = "$Region-docker.pkg.dev/$Project/$Repo/${Image}:latest"

if (-not $SkipBuild) {
  Step 'Build the image in the cloud (no local Docker needed)'
  Push-Location $root
  try {
    # Build from the repository root: the Dockerfile copies both backend/ and .github/scripts/.
    gcloud builds submit --tag $tag --project $Project .
  } finally {
    Pop-Location
  }
}

Step 'Deploy'
$map = EnvMap $EnvFile
# Cloud Run injects PORT and expects the server to honour it.
$map['PORT'] = '8080'
# The service account JSON is mounted as a secret, not baked into the image.
$map.Remove('FIREBASE_AUTH_CREDENTIALS_PATH') | Out-Null

$envPairs = @()
foreach ($k in $map.Keys | Sort-Object) { $envPairs += "$k=$($map[$k])" }
$envVars = $envPairs -join ','

gcloud run deploy $Service `
  --image $tag `
  --project $Project `
  --region $Region `
  --platform managed `
  --allow-unauthenticated `
  --port 8080 `
  --memory 1Gi `
  --cpu 1 `
  --concurrency 20 `
  --timeout 3600 `
  --min-instances 0 `
  --max-instances 2 `
  --set-env-vars $envVars

$url = (gcloud run services describe $Service --project $Project --region $Region --format='value(status.url)')
Write-Host "`n  deployed: $url" -ForegroundColor Green

Step 'Next'
Write-Host @"
  1. Put the service account JSON where the container can read it. Cloud Run has no persistent
     disk by default, so either:
       a. mount it from Secret Manager (recommended), or
       b. base64 it into an env var and write it at startup.
     Neither is done for you here - this script does not handle secrets.
  2. Set BASE_API_URL in backend/.env to $url and redeploy, so OAuth callbacks point here.
  3. Add $url/v1/auth/callback/google to the OAuth client's authorised redirect URIs.
  4. Set a budget alert: gcloud billing budgets create --budget-amount=5
"@ -ForegroundColor Yellow
