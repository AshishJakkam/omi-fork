# Build the fork and stage the IPA, retrying past GitHub's macOS capacity refusals
# (they report failure with zero steps, because the job never reached a runner).
param(
  [int]$MaxAttempts = 8,
  [string]$Profile = 'production',
  [string]$OutFile = 'C:\Users\ashis\Downloads\OpenMind-auto.ipa'
)

$ErrorActionPreference = 'Stop'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$repo = 'AshishJakkam/omi-fork'
$log = 'C:\Users\ashis\omi-captures\auto-build.log'

function Log([string]$m) {
  $line = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m
  Add-Content -Path $log -Value $line
}

Log "start: up to $MaxAttempts attempts"

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
  Log "attempt ${attempt}: dispatching"
  & $gh workflow run ios-unsigned.yml -R $repo -f app_profile=$Profile -f force_on_device=true -f include_watch=false 2>$null | Out-Null
  Start-Sleep -Seconds 20

  $run = (& $gh run list -R $repo -L 1 --json databaseId 2>$null | ConvertFrom-Json)[0]
  $id = $run.databaseId
  Log "attempt ${attempt}: run $id"

  $status = $null
  for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Seconds 15
    try {
      $status = & $gh run view $id -R $repo --json status,conclusion 2>$null | ConvertFrom-Json
      if ($status.status -eq 'completed') { break }
    } catch {
      # A dropped connection must not end the loop; the run keeps going regardless.
      Log "poll error (continuing): $($_.Exception.Message.Split([char]10)[0])"
    }
  }
  if (-not $status) { Log "attempt ${attempt}: no status after polling - retrying"; continue }

  if ($status.conclusion -ne 'success') {
    $stepCount = 0
    try {
      $jobsRaw = & $gh api "repos/$repo/actions/runs/$id/jobs" 2>$null
      $j = $jobsRaw | ConvertFrom-Json
      $stepCount = ($j.jobs | ForEach-Object { $_.steps.Count } | Measure-Object -Sum).Sum
    } catch {}
    Log "attempt ${attempt}: failed (steps=$stepCount) - retrying in 60s"
    Start-Sleep -Seconds 60
    continue
  }

  Log "attempt ${attempt}: build succeeded, downloading"
  $dest = 'C:\Users\ashis\Downloads\_auto_dl'
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  & $gh run download $id -R $repo -n OpenMind-ipa -D $dest 2>$null | Out-Null
  $ipa = Get-ChildItem $dest -Recurse -Filter '*.ipa' | Select-Object -First 1
  if (-not $ipa) { Log 'no ipa in artifact'; continue }
  Copy-Item $ipa.FullName $OutFile -Force
  Log "staged $OutFile ($([math]::Round($ipa.Length/1MB,1)) MB)"
  Log 'done'
  exit 0
}

Log 'exhausted attempts without a successful build'
exit 1

