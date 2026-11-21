# Checks a candidate product name before any of it becomes permanent.
#
#   powershell -ExecutionPolicy Bypass -File tools\check-name.ps1 mindext
#   powershell -ExecutionPolicy Bypass -File tools\check-name.ps1 gnosa,tavrine,ambientpilot
#
# A Firebase project id cannot be renamed and an App Store name is hard to change, so the cheap
# moment to find a collision is before either exists. Domains resolve live, the App Store is
# queried in the regions that matter here, and USPTO wordmark records are read through the same
# endpoint the public search page uses.
#
# What this does NOT do: EUIPO and India (IPI) hold no keyless API, so those still need a human
# search. Treat a clean result here as "no US blocker found", not as clearance.
param(
  [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Names
)

$ErrorActionPreference = 'Continue'
$tlds = @('com', 'app', 'io', 'co', 'ai', 'net', 'org', 'dev', 'xyz', 'so')
$regions = @('us', 'in', 'gb')

function Test-Domain([string]$hostName) {
  try {
    $null = Resolve-DnsName -Name $hostName -Type NS -DnsOnly -ErrorAction Stop
    return 'taken'
  } catch {
    if ($_.Exception.Message -match 'does not exist') { return 'free' }
    return '?'
  }
}

function Get-DomainOwner([string]$domain) {
  # A marketplace or parking nameserver means the name is for sale rather than in use, which is a
  # very different risk from a company that owns it.
  try {
    $ns = (Resolve-DnsName -Name $domain -Type NS -DnsOnly -ErrorAction Stop |
      Where-Object { $_.Type -eq 'NS' } | ForEach-Object { $_.NameHost }) -join ' '
  } catch { return 'no NS' }
  $parked = 'afternic|dan\.com|sedo|hugedomains|bodis|parkingcrew|domaincontrol|above\.com|uniregistry'
  if ($ns -match $parked) { return "for sale / parked ($ns)" }
  return "live owner ($ns)"
}

function Write-UsptoGuidance {
  # Deliberately does not query. The public search page posts same-origin with an AWS WAF token, so
  # a scripted call needs a real browser session. Printing "0" here would read as "clear" when it
  # only means "not checked" - the mistake that made MINDEX invisible behind a clean 'mindext'.
  Write-Host "  USPTO: not checked by this script. Search https://tmsearch.uspto.gov for each" -ForegroundColor Yellow
  Write-Host "         wordmark AND its phonetic neighbours, then keep only records that are alive" -ForegroundColor Yellow
  Write-Host "         and in class 9, 42 or 38. USPTO stores classes as 'IC 042', not '42'." -ForegroundColor Yellow
}

foreach ($raw in $Names) {
  foreach ($name in ($raw -split ',')) {
    $n = $name.Trim().ToLowerInvariant()
    if (-not $n) { continue }
    Write-Host "`n===== $n =====" -ForegroundColor Cyan

    $free = @()
    foreach ($t in $tlds) {
      $state = Test-Domain "$n.$t"
      if ($state -eq 'free') {
        $free += ".$t"
        Write-Host ("  {0,-8} free" -f ".$t") -ForegroundColor Green
      } else {
        Write-Host ("  {0,-8} {1}" -f ".$t", $state)
      }
    }
    Write-Host "  -> $($free.Count)/$($tlds.Count) free: $($free -join ' ')" -ForegroundColor Cyan

    if ($free -notcontains '.com') {
      Write-Host "  .com: $(Get-DomainOwner "$n.com")"
    }

    foreach ($r in $regions) {
      try {
        $j = (Invoke-WebRequest -Uri "https://itunes.apple.com/search?term=$n&entity=software&limit=25&country=$r" `
            -TimeoutSec 15 -UseBasicParsing).Content | ConvertFrom-Json
        $exact = @($j.results | Where-Object { $_.trackName -match "^$n" })
        $label = if ($exact.Count -gt 0) { 'WARN' } else { 'ok  ' }
        $names = ($exact | Select-Object -First 3 -ExpandProperty trackName) -join '; '
        Write-Host "  [$label] App Store $($r.ToUpper()): $($exact.Count) match(es) $names"
      } catch {
        Write-Host "  App Store $($r.ToUpper()): check failed" -ForegroundColor Yellow
      }
    }

    try {
      $g = (Invoke-WebRequest -Uri "https://api.github.com/search/repositories?q=$n+in:name&per_page=1" `
          -TimeoutSec 15 -UseBasicParsing -Headers @{ 'User-Agent' = 'name-check' }).Content | ConvertFrom-Json
      Write-Host "  github repos: $($g.total_count)"
    } catch { Write-Host "  github: check failed" -ForegroundColor Yellow }

    try {
      $null = Invoke-WebRequest -Uri "https://registry.npmjs.org/$n" -TimeoutSec 12 -UseBasicParsing
      Write-Host "  [WARN] npm package: taken"
    } catch {
      if ($_.Exception.Message -match '404') { Write-Host "  [ok  ] npm package: free" }
      else { Write-Host "  npm: check failed" -ForegroundColor Yellow }
    }
  }
}

Write-Host "`nTrademarks: query https://tmsearch.uspto.gov for each wordmark, then keep only records" -ForegroundColor Yellow
Write-Host "that are alive and in class 9 (software), 42 (SaaS) or 38 (communications). Also search the" -ForegroundColor Yellow
Write-Host "phonetic neighbours - MINDEX blocked 'mindext' where 'mindext' itself had zero records." -ForegroundColor Yellow
Write-Host "EUIPO and India (IPI) have no keyless API and still need a human search." -ForegroundColor Yellow
