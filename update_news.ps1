param(
  [string[]]$Codes = @('005930'),
  [double]$MoveThreshold = 5,
  [int]$MaxEvents = 12
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stocks = Get-Content (Join-Path $root 'data\stocks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$outputDir = Join-Path $root 'data\news'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$clientId = $env:NAVER_API_HUB_CLIENT_ID
$clientSecret = $env:NAVER_API_HUB_CLIENT_SECRET
$hasNewsApi = -not [string]::IsNullOrWhiteSpace($clientId) -and -not [string]::IsNullOrWhiteSpace($clientSecret)

function Remove-Html([string]$value) {
  if ([string]::IsNullOrWhiteSpace($value)) { return '' }
  return [Net.WebUtility]::HtmlDecode(($value -replace '<[^>]+>', '')).Trim()
}

foreach ($code in $Codes) {
  $stock = $stocks | Where-Object { $_.code -eq $code } | Select-Object -First 1
  if (-not $stock) { throw "Unknown stock code: $code" }
  $marketPath = Join-Path $root "data\market\$code.json"
  if (-not (Test-Path $marketPath)) { throw "Market data missing: $marketPath" }
  $market = Get-Content $marketPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $candidates = @()
  for ($i=1; $i -lt $market.prices.Count; $i++) {
    $previous = [double]$market.prices[$i-1].close
    $current = [double]$market.prices[$i].close
    if ($previous -le 0) { continue }
    $change = ($current / $previous - 1) * 100
    if ([math]::Abs($change) -ge $MoveThreshold) {
      $candidates += [pscustomobject]@{ index=$i; date=[string]$market.prices[$i].date; close=$current; change=[math]::Round($change,2); magnitude=[math]::Abs($change) }
    }
  }
  $selected = @()
  foreach ($candidate in ($candidates | Sort-Object magnitude -Descending)) {
    $date = [datetime]$candidate.date
    if (@($selected | Where-Object { [math]::Abs((([datetime]$_.date)-$date).TotalDays) -lt 10 }).Count -gt 0) { continue }
    $selected += $candidate
    if ($selected.Count -ge $MaxEvents) { break }
  }
  $events = @()
  foreach ($event in ($selected | Sort-Object date -Descending)) {
    $articles = @()
    if ($hasNewsApi) {
      $query = [uri]::EscapeDataString("$($stock.name) $($event.date)")
      $uri = "https://naverapihub.apigw.ntruss.com/search/v1/news?query=$query&display=100&start=1&sort=sim&format=json"
      $response = Invoke-RestMethod -Uri $uri -Headers @{ 'X-NCP-APIGW-API-KEY-ID'=$clientId; 'X-NCP-APIGW-API-KEY'=$clientSecret } -TimeoutSec 60
      $eventDate = [datetime]$event.date
      $articles = @($response.items | ForEach-Object {
        $published = [DateTimeOffset]::Parse([string]$_.pubDate).LocalDateTime
        if ([math]::Abs(($published.Date-$eventDate.Date).TotalDays) -le 3) {
          [ordered]@{ title=Remove-Html $_.title; description=Remove-Html $_.description; link=[string]$_.link; originalLink=[string]$_.originallink; publishedAt=$published.ToString('yyyy-MM-ddTHH:mm:sszzz') }
        }
      } | Select-Object -First 5)
    }
    $events += [ordered]@{ date=$event.date; close=$event.close; changePercent=$event.change; direction=if($event.change -ge 0){'up'}else{'down'}; articles=$articles }
  }
  $payload = [ordered]@{ code=$code; name=[string]$stock.name; generatedAt=(Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz'); thresholdPercent=$MoveThreshold; newsProvider=if($hasNewsApi){'NAVER API HUB'}else{'not configured'}; events=$events }
  [IO.File]::WriteAllText((Join-Path $outputDir "$code.json"), ($payload | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
  Write-Host "[$code] $($events.Count) price events, $(@($events | ForEach-Object {$_.articles}).Count) article groups"
}
