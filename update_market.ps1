param(
  [string[]]$Codes = @('005930'),
  [int]$Years = 5
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputDir = Join-Path $root 'data\market'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$period2 = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$period1 = [DateTimeOffset]::UtcNow.AddYears(-$Years).ToUnixTimeSeconds()

foreach ($code in $Codes) {
  $ticker = "$code.KS"
  $uri = "https://query1.finance.yahoo.com/v8/finance/chart/$ticker`?period1=$period1&period2=$period2&interval=1d&events=div%2Csplits&includeAdjustedClose=true"
  Write-Host "[$code] Yahoo Finance market data..."
  $response = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent'='Mozilla/5.0' } -TimeoutSec 60
  $result = $response.chart.result[0]
  if (-not $result) { throw "No Yahoo Finance data for $ticker" }
  $quote = $result.indicators.quote[0]
  $adj = $result.indicators.adjclose[0].adjclose
  $prices = @()
  for ($i = 0; $i -lt $result.timestamp.Count; $i++) {
    if ($null -eq $quote.close[$i]) { continue }
    $prices += [ordered]@{
      date = [DateTimeOffset]::FromUnixTimeSeconds([long]$result.timestamp[$i]).UtcDateTime.ToString('yyyy-MM-dd')
      open = [math]::Round([double]$quote.open[$i], 2)
      high = [math]::Round([double]$quote.high[$i], 2)
      low = [math]::Round([double]$quote.low[$i], 2)
      close = [math]::Round([double]$quote.close[$i], 2)
      adjustedClose = if ($null -ne $adj[$i]) { [math]::Round([double]$adj[$i], 2) } else { $null }
      volume = [long]$quote.volume[$i]
    }
  }
  $payload = [ordered]@{
    provider = 'Yahoo Finance'
    ticker = $ticker
    code = $code
    currency = [string]$result.meta.currency
    exchange = [string]$result.meta.exchangeName
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    interval = '1d'
    prices = $prices
    dividends = @($result.events.dividends.PSObject.Properties | ForEach-Object {
      [ordered]@{
        date = [DateTimeOffset]::FromUnixTimeSeconds([long]$_.Value.date).UtcDateTime.ToString('yyyy-MM-dd')
        amount = [math]::Round([double]$_.Value.amount, 4)
      }
    })
  }
  $json = $payload | ConvertTo-Json -Depth 6
  [IO.File]::WriteAllText((Join-Path $outputDir "$code.json"), $json, [Text.UTF8Encoding]::new($false))
  Write-Host "Done: $($prices.Count) rows"
}
