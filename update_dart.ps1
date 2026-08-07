param(
  [int]$BusinessYear = ((Get-Date).Year - 1),
  [ValidateSet('11011','11012','11013','11014')][string]$ReportCode = '11011'
)

$ErrorActionPreference = 'Stop'
$apiKey = $env:DART_API_KEY
if ([string]::IsNullOrWhiteSpace($apiKey)) {
  throw 'DART_API_KEY is missing. Set the OpenDART API key in the environment and retry.'
}

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stocksPath = Join-Path $root 'data\stocks.json'
$outputPath = Join-Path $root 'data\financials.json'
$stocks = Get-Content -LiteralPath $stocksPath -Raw -Encoding UTF8 | ConvertFrom-Json
$reportNames = @{ '11011'='Annual report'; '11012'='Half-year report'; '11013'='First-quarter report'; '11014'='Third-quarter report' }

function Invoke-DartJson([string]$endpoint, [hashtable]$parameters) {
  $parameters.crtfc_key = $apiKey
  $query = ($parameters.GetEnumerator() | ForEach-Object {
    [uri]::EscapeDataString([string]$_.Key) + '=' + [uri]::EscapeDataString([string]$_.Value)
  }) -join '&'
  $response = Invoke-RestMethod -Method Get -Uri ("https://opendart.fss.or.kr/api/{0}?{1}" -f $endpoint,$query) -TimeoutSec 60
  if ($response.status -and $response.status -ne '000') {
    throw "OpenDART $endpoint error $($response.status): $($response.message)"
  }
  return $response
}

function Convert-Amount($value) {
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value) -or $value -eq '-') { return $null }
  $clean = ([string]$value).Replace(',','').Trim()
  [long]$number = 0
  if ([long]::TryParse($clean, [ref]$number)) { return $number }
  return $null
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("ssfamily-dart-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
  $zipPath = Join-Path $temp 'corpCode.zip'
  Invoke-WebRequest -Uri ("https://opendart.fss.or.kr/api/corpCode.xml?crtfc_key={0}" -f [uri]::EscapeDataString($apiKey)) -OutFile $zipPath -TimeoutSec 60
  Expand-Archive -LiteralPath $zipPath -DestinationPath $temp
  [xml]$corpXml = Get-Content -LiteralPath (Join-Path $temp 'CORPCODE.xml') -Raw -Encoding UTF8
  $corpByStock = @{}
  foreach ($item in $corpXml.result.list) {
    $stockCode = ([string]$item.stock_code).Trim()
    if ($stockCode) { $corpByStock[$stockCode] = $item }
  }

  $resultStocks = [ordered]@{}
  foreach ($stock in $stocks) {
    $code = [string]$stock.code
    Write-Host "[$code] Fetching $($stock.name)..."
    $corp = $corpByStock[$code]
    if (-not $corp) { Write-Warning "$code has no matching DART corporation code."; continue }
    $corpCode = [string]$corp.corp_code
    try {
      $company = Invoke-DartJson 'company.json' @{ corp_code=$corpCode }
      $finance = $null
      foreach ($fsDiv in @('CFS','OFS')) {
        try {
          $candidate = Invoke-DartJson 'fnlttSinglAcntAll.json' @{ corp_code=$corpCode; bsns_year=$BusinessYear; reprt_code=$ReportCode; fs_div=$fsDiv }
          if ($candidate.list.Count -gt 0) { $finance = $candidate; break }
        } catch {
          if ($_.Exception.Message -notmatch '013') { throw }
        }
      }
      if (-not $finance) { Write-Warning "$code has no financial statements for the requested period."; continue }
      $accounts = @($finance.list | ForEach-Object {
        [ordered]@{
          statement = [string]$_.sj_div
          statementName = [string]$_.sj_nm
          accountId = [string]$_.account_id
          accountName = [string]$_.account_nm
          currentAmount = Convert-Amount $_.thstrm_amount
          previousAmount = Convert-Amount $_.frmtrm_amount
          currency = [string]$_.currency
          order = [int]$_.ord
        }
      })
      $resultStocks[$code] = [ordered]@{
        businessYear = $BusinessYear
        reportCode = $ReportCode
        reportName = $reportNames[$ReportCode]
        fsDivision = [string]$finance.list[0].fs_div
        company = [ordered]@{
          corpCode = $corpCode
          corpName = [string]$company.corp_name
          ceoName = [string]$company.ceo_nm
          corpClass = [string]$company.corp_cls
          accMonth = [string]$company.acc_mt
          address = [string]$company.adres
          homepage = [string]$company.hm_url
        }
        accounts = $accounts
      }
    } catch {
      Write-Warning "$code fetch failed: $($_.Exception.Message)"
    }
  }

  $output = [ordered]@{
    generatedAt = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
    businessYear = $BusinessYear
    reportCode = $ReportCode
    reportName = $reportNames[$ReportCode]
    stocks = $resultStocks
  }
  $json = $output | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($outputPath, $json, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Done: $($resultStocks.Count)/$($stocks.Count) companies -> $outputPath"
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
