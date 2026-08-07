param(
  [int]$BusinessYear = ((Get-Date).Year - 1),
  [ValidateSet('11011','11012','11013','11014')][string]$ReportCode = '11011',
  [ValidateRange(2,10)][int]$LookbackYears = 5
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

function Convert-Number($value) {
  if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value) -or $value -eq '-') { return $null }
  $clean = ([string]$value).Replace(',','').Replace('%','').Trim()
  [double]$number = 0
  if ([double]::TryParse($clean, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) { return $number }
  return $null
}

function Find-DividendValue($list, [string]$label) {
  $row = $list | Where-Object { ([string]$_.se) -like "*$label*" -and ([string]$_.stock_knd) -like '*보통주*' } | Select-Object -First 1
  if (-not $row) { $row = $list | Where-Object { ([string]$_.se) -like "*$label*" } | Select-Object -First 1 }
  if ($row) { return Convert-Number $row.thstrm }
  return $null
}

function Find-Account($list, [string[]]$names) {
  foreach ($name in $names) {
    $row = $list | Where-Object { ([string]$_.account_nm).Trim() -eq $name } | Select-Object -First 1
    if ($row) { return Convert-Amount $row.thstrm_amount }
  }
  foreach ($name in $names) {
    $row = $list | Where-Object { ([string]$_.account_nm) -like "*$name*" } | Select-Object -First 1
    if ($row) { return Convert-Amount $row.thstrm_amount }
  }
  return $null
}

function Get-FinanceForYear([string]$corpCode, [int]$year, [string]$reportCode) {
  foreach ($fsDiv in @('CFS','OFS')) {
    try {
      $candidate = Invoke-DartJson 'fnlttSinglAcntAll.json' @{ corp_code=$corpCode; bsns_year=$year; reprt_code=$reportCode; fs_div=$fsDiv }
      if ($candidate.list.Count -gt 0) { return $candidate }
    } catch {
      if ($_.Exception.Message -notmatch '013') { throw }
    }
  }
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
      $history = @()
      for ($historyYear = $BusinessYear; $historyYear -gt ($BusinessYear - $LookbackYears); $historyYear--) {
        $yearFinance = if ($historyYear -eq $BusinessYear) { $finance } else { Get-FinanceForYear $corpCode $historyYear '11011' }
        if (-not $yearFinance) { continue }
        $list = @($yearFinance.list)
        $stockStatus = $null
        $dividendInfo = $null
        try { $stockStatus = Invoke-DartJson 'stockTotqySttus.json' @{ corp_code=$corpCode; bsns_year=$historyYear; reprt_code='11011' } } catch { if ($_.Exception.Message -notmatch '013|014') { throw } }
        try { $dividendInfo = Invoke-DartJson 'alotMatter.json' @{ corp_code=$corpCode; bsns_year=$historyYear; reprt_code='11011' } } catch { if ($_.Exception.Message -notmatch '013|014') { throw } }
        $stockRow = @($stockStatus.list) | Where-Object { ([string]$_.se) -like '*보통주*' } | Select-Object -First 1
        if (-not $stockRow) { $stockRow = @($stockStatus.list) | Where-Object { ([string]$_.se) -eq '합계' } | Select-Object -First 1 }
        $dividendRows = @($dividendInfo.list)
        $history += [ordered]@{
          businessYear = $historyYear
          fsDivision = [string]$list[0].fs_div
          revenue = Find-Account $list @('매출액','영업수익','수익(매출액)','이자수익')
          operatingIncome = Find-Account $list @('영업이익','영업이익(손실)','영업손익')
          netIncome = Find-Account $list @('당기순이익','당기순이익(손실)','연결당기순이익')
          assets = Find-Account $list @('자산총계')
          liabilities = Find-Account $list @('부채총계')
          equity = Find-Account $list @('자본총계')
          operatingCashFlow = Find-Account $list @('영업활동현금흐름','영업활동으로 인한 현금흐름')
          investingCashFlow = Find-Account $list @('투자활동현금흐름','투자활동으로 인한 현금흐름')
          financingCashFlow = Find-Account $list @('재무활동현금흐름','재무활동으로 인한 현금흐름')
          issuedShares = Convert-Amount $stockRow.istc_totqy
          treasuryShares = Convert-Amount $stockRow.tesstk_co
          distributedShares = Convert-Amount $stockRow.distb_stock_co
          eps = Find-DividendValue $dividendRows '주당순이익'
          dps = Find-DividendValue $dividendRows '주당 현금배당금'
          dividendYield = Find-DividendValue $dividendRows '현금배당수익률'
          payoutRatio = Find-DividendValue $dividendRows '현금배당성향'
        }
      }
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
        history = @($history | Sort-Object businessYear)
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
